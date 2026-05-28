import logging
import mimetypes
from pathlib import Path
from decimal import Decimal, InvalidOperation
from datetime import datetime
from urllib.parse import urlencode

from django.conf import settings
from django.core.paginator import EmptyPage, Paginator
from django.db.models import Count, Q
from django.core.exceptions import ValidationError
from django.http import FileResponse, Http404, HttpResponse, JsonResponse
from django.contrib import messages
from django.shortcuts import redirect, render
from django.urls import reverse
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from django.views.decorators.http import require_GET, require_http_methods
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from backend.apps.telecalling.auth import (
    clear_auth_cookies,
    get_staff_from_request,
    issue_tokens_for_user,
    rotate_auth_session,
    set_auth_cookies,
)
from backend.apps.telecalling.models import (
    AppNotification,
    AppRelease,
    Call,
    InterestedLeadDetail,
    Lead,
    ReferralReward,
    Salary,
    SalaryPaymentTransaction,
    Session,
    Staff,
    StaffAction,
    TrainingLesson,
)
from backend.apps.telecalling.permissions import IsAdminStaff, IsCallingStaff
from backend.apps.telecalling.serializers import (
    AdminProfileSerializer,
    AdminProfileUpdateSerializer,
    CallSerializer,
    CompanyProfileSerializer,
    CompanyProfileUpdateSerializer,
    CallStatusSerializer,
    CreateStaffReferralSubmissionSerializer,
    CreateAppReleaseSerializer,
    CreateLeadSerializer,
    CreateStaffSerializer,
    CreateTrainingLessonSerializer,
    EndCallSerializer,
    FollowupUpdateUploadSerializer,
    HeartbeatSerializer,
    InterestedLeadCaptureSerializer,
    InterestedLeadDetailSerializer,
    LeadSerializer,
    LeadImportUploadSerializer,
    LoginSerializer,
    SalaryPaymentSerializer,
    SalarySettingsSerializer,
    SessionSerializer,
    StaffActionSerializer,
    StaffLeadRecoverySerializer,
    StaffReferralSubmissionSerializer,
    StaffSerializer,
    StartCallSerializer,
    StaffProfileSerializer,
    StaffProfileUpdateSerializer,
    TrainingLessonSerializer,
    UpdateLeadSerializer,
    UpdateStaffSerializer,
    UpdateTrainingLessonSerializer,
)
from backend.apps.telecalling.services import (
    build_cached_admin_web_alert_payload,
    assign_selected_leads_to_staff_queue,
    auto_allocate_leads,
    authenticate_staff,
    build_app_update_payload,
    build_app_notification_management_payload,
    build_callback_csv_response,
    build_callback_excel_response,
    build_callback_payload,
    build_call_detail_payload,
    build_dashboard_payload,
    build_developer_release_payload,
    build_followup_csv_response,
    build_followup_excel_response,
    build_followup_payload,
    build_interested_lead_csv_response,
    build_interested_lead_excel_response,
    build_interested_lead_payload,
    build_learning_management_payload,
    build_lead_management_payload,
    build_live_monitoring_payload,
    build_recovery_lead_payload,
    build_salary_control_payload,
    build_staff_salary_details_payload,
    build_salary_detail_payload,
    build_salary_page_payload,
    _format_currency,
    _format_datetime,
    _format_work_duration_label,
    _month_range_for_reference,
    _parse_month_value,
    _shift_month,
    _build_staff_quality_metrics,
    build_referral_monitoring_payload,
    build_settings_payload,
    build_work_review_payload,
    build_staff_profile_payload,
    build_staff_learning_payload,
    build_staff_followups_payload,
    build_staff_followup_sla_gate_status,
    build_staff_active_notifications_payload,
    build_staff_today_payload,
    build_team_management_payload,
    build_work_hours_payload,
    complete_training_lesson,
    delete_salary_payment_transaction,
    delete_app_release,
    delete_oldest_manageable_leads,
    end_staff_call,
    end_staff_session,
    get_assigned_leads,
    get_pending_status_call,
    get_recoverable_open_call,
    get_company_profile,
    publish_app_release,
    queue_salary_payment_acknowledgement,
    reassign_unassigned_followup_owners,
    record_referral_reward_payment,
    save_interested_lead_detail,
    import_leads_from_upload,
    is_staff_lead_visible_now,
    mark_staff_seen,
    read_root_file,
    reassign_staff_review_leads,
    record_staff_salary_payment,
    record_session_heartbeat,
    reset_staff_review_leads_to_new_queue,
    release_staff_queue,
    reactivate_oldest_recovery_leads,
    recover_recovery_lead_to_owner,
    reallocate_expired_followup_to_owner,
    run_automatic_lead_cleanup_if_due,
    set_active_app_release,
    retry_pending_staff_call,
    search_staff_customer_history,
    start_staff_call,
    start_staff_session,
    TrainingRequiredError,
    update_staff_call_status,
    update_followups_from_upload,
    recover_staff_customer_lead,
    calculate_staff_payout_for_dates,
    delete_recovery_leads_filtered,
    ensure_converted_call_credit,
)


logger = logging.getLogger(__name__)


def _fallback_admin_alert_payload():
    return {
        "summary": {
            "total_alerts": 0,
            "critical_alerts": 0,
            "warning_alerts": 0,
            "generated_at_label": _format_datetime(timezone.now()),
        },
        "alerts": [],
    }


def _admin_web_context(
    request,
    current_user,
    *,
    active_page,
    page_title,
    page_heading,
    page_subtitle,
    extra_context=None,
    admin_alert_payload=None,
):
    mark_staff_seen(current_user)
    company_profile = get_company_profile()
    show_admin_welcome = bool(request.session.pop("show_admin_welcome", False))
    context = {
        "admin_user": current_user,
        "company_profile": company_profile,
        "active_page": active_page,
        "page_title": page_title,
        "page_heading": page_heading,
        "page_subtitle": page_subtitle,
        "show_admin_welcome": show_admin_welcome,
        # Let the page render immediately and hydrate alerts asynchronously
        # from the admin alerts API instead of blocking every admin page load.
        "admin_alert_payload": admin_alert_payload or _fallback_admin_alert_payload(),
    }
    if extra_context:
        context.update(extra_context)
    return context


def _get_admin_user_or_redirect(request):
    current_user = get_staff_from_request(request)
    if not current_user or current_user.role != Staff.Role.ADMIN or not current_user.is_active:
        return None
    return current_user


def _get_developer_user_or_redirect(request):
    current_user = get_staff_from_request(request)
    if (
        not current_user
        or not current_user.is_active
        or current_user.role not in {Staff.Role.ADMIN, Staff.Role.DEVELOPER}
    ):
        return None
    return current_user

def _normalize_errors(error_dict):
    normalized = {}
    for field, value in error_dict.items():
        if isinstance(value, dict):
            nested = _normalize_errors(value)
            normalized[field] = " ".join(nested.values())
            continue
        if isinstance(value, (list, tuple)):
            normalized[field] = " ".join(str(item) for item in value)
            continue
        normalized[field] = str(value)
    return normalized


def _fallback_today_label():
    return timezone.localdate().strftime("%A, %d %b %Y")


def _fallback_schedule_label(staff):
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return f"Every {staff.get_weekly_payout_day_display()}"
    if staff.compensation_type == Staff.CompensationType.MONTHLY:
        return "Last day of every month"
    return "Running earned amount"


def _fallback_basic_staff_rows():
    staff_queryset = Staff.objects.filter(role=Staff.Role.STAFF).order_by("name")
    rows = []
    for staff in staff_queryset:
        active_lead_count = Lead.objects.filter(
            assigned_to=staff,
            status__in=[Lead.Status.NEW, Lead.Status.CALL_BACK, Lead.Status.INTERESTED],
        ).count()
        rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "email": staff.email or "",
                "is_active": staff.is_active,
                "receives_new_leads": staff.receives_new_leads,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": f"Rs. {float(staff.hourly_rate or 0):,.2f}",
                "weekly_salary": f"Rs. {float(staff.weekly_salary or 0):,.2f}",
                "monthly_salary": f"Rs. {float(staff.monthly_salary or 0):,.2f}",
                "target_hours_per_week": float(staff.target_hours_per_week or 0),
                "target_hours_per_month": float(staff.target_hours_per_month or 0),
                "call_rate": f"Rs. {float(staff.call_rate or 0):,.2f}",
                "bonus_per_conversion": f"Rs. {float(staff.bonus_per_conversion or 0):,.2f}",
                "online_label": "Offline",
                "status_filter": "paused" if staff.is_active and not staff.receives_new_leads else ("offline" if staff.is_active else "inactive"),
                "lead_intake_label": "Lead intake paused" if staff.is_active and not staff.receives_new_leads else "Receiving new leads",
                "lead_intake_tone": "warning" if staff.is_active and not staff.receives_new_leads else "success",
                "status_tone": "warning" if staff.is_active and not staff.receives_new_leads else "muted",
                "session_state": "stopped",
                "active_hours_today": "0s",
                "active_seconds_today": 0,
                "calls_today": 0,
                "converted_today": 0,
                "assigned_leads": active_lead_count,
                "last_seen": "--",
                "is_available": False,
                "quality_score": 0,
                "quality_label": "Temporarily Unavailable",
                "quality_tone": "muted",
                "quality_note": "Live activity metrics are temporarily unavailable. Basic staff details are still shown.",
                "outcome_consistency_label": "--",
                "followup_completion_label": "--",
                "missed_callbacks": 0,
                "attempt_review_label": "--",
                "away_review_label": "Unavailable",
                "suspicious_block_count": 0,
                "zero_only_block_count": 0,
                "zero_second_attempt_count": 0,
                "real_call_count": 0,
            }
        )
    return rows


def _fallback_dashboard_payload():
    staff_rows = _fallback_basic_staff_rows()
    live_staff = [
        {
            "name": row["name"],
            "status_text": "Activity metrics are temporarily unavailable",
            "is_online": False,
        }
        for row in staff_rows[:8]
    ]
    total_leads = Lead.objects.count()
    no_answer = Lead.objects.filter(status=Lead.Status.NO_ANSWER).count()
    interested = Lead.objects.filter(status=Lead.Status.INTERESTED).count()
    converted = Lead.objects.filter(status=Lead.Status.CONVERTED).count()
    callbacks = Lead.objects.filter(status=Lead.Status.CALL_BACK).count()
    return {
        "dashboard": {
            "today_label": _fallback_today_label(),
            "staff_active": 0,
            "calls_today": 0,
            "conversion_rate": "0.0%",
            "callbacks": callbacks,
            "work_coverage": 0,
            "short_calls_blocked": 0,
            "salary_ready": 0,
            "total_leads": total_leads,
            "no_answer": no_answer,
            "interested": interested,
            "converted": converted,
            "salary_estimate": "Rs. 0.00",
            "active_hours": "0s",
        },
        "chart_payload": {
            "callVolume": {"labels": [], "calls": [], "conversions": []},
            "leadPipeline": {"labels": ["New", "Follow Up", "Scheduled Follow Up", "No Response", "Converted"], "values": [0, 0, 0, 0, 0]},
            "activityBalance": {"labels": [], "activeHours": [], "callMinutes": []},
        },
        "live_staff": live_staff,
        "lead_rows": [],
        "salary_records": [],
        "team_directory": staff_rows,
    }


def _fallback_team_payload():
    team_rows = _fallback_basic_staff_rows()
    return {
        "today_label": _fallback_today_label(),
        "team_summary": {
            "total_staff": len(team_rows),
            "active_accounts": sum(1 for row in team_rows if row["is_active"]),
            "lead_intake_paused": sum(1 for row in team_rows if row["is_active"] and not row.get("receives_new_leads")),
            "online_now": 0,
            "attention_needed": sum(1 for row in team_rows if row["is_active"]),
            "total_assigned": sum(row["assigned_leads"] for row in team_rows),
            "total_calls_today": 0,
            "total_converted_today": 0,
        },
        "team_rows": team_rows,
    }


def _fallback_work_hours_payload():
    company_profile = get_company_profile()
    summary_rows = [
        {
            "id": row["id"],
            "name": row["name"],
            "phone": row["phone"],
            "active_hours_today": "0s",
            "active_seconds_today": 0,
            "session_count_today": 0,
            "first_login": "--",
            "last_logout": "--",
            "state_label": "Unavailable",
            "online_label": "Offline",
            "gap_count": 0,
            "gap_total_label": "0s",
            "gap_uncounted_label": "0s",
            "gap_buffer_label": "0s",
            "gap_rows": [],
            "gap_extra_count": 0,
            "call_time_label": "0s",
            "first_call": "--",
            "last_call": "--",
        }
        for row in _fallback_basic_staff_rows()
    ]
    return {
        "today_label": _fallback_today_label(),
        "selected_date": timezone.localdate().isoformat(),
        "work_gap_rules": {
            "idle_gap_seconds": int(company_profile.work_review_idle_gap_seconds or 60),
            "connected_cooldown_seconds": int(company_profile.work_review_connected_cooldown_seconds or 90),
            "attempt_threshold": int(company_profile.work_review_zero_talk_attempt_threshold or 10),
            "followup_expired_penalty_points": int(
                company_profile.work_review_followup_expired_penalty_points or 4
            ),
            "followup_expired_penalty_cap": int(company_profile.work_review_followup_expired_penalty_cap or 24),
        },
        "summary_rows": summary_rows,
        "session_rows": [],
    }


def _fallback_work_review_payload():
    company_profile = get_company_profile()
    team_payload = _fallback_team_payload()
    review_rows = []
    for row in team_payload["team_rows"]:
        review_rows.append(
            {
                **row,
                "review_state": "quiet",
                "review_state_label": "Temporarily Unavailable",
                "review_state_tone": "muted",
                "review_state_note": "Detailed review metrics are temporarily unavailable right now.",
                "review_day_rows": [],
                "review_day_count": 0,
                "extra_review_day_count": 0,
                "zero_only_block_details": [],
                "zero_only_block_extra": 0,
                "real_call_ratio_label": "--",
                "invalid_short_count": row.get("invalid_short_count", 0),
                "verified_attempt_count": row.get("verified_attempt_count", 0),
            }
        )

    return {
        "today_label": team_payload["today_label"],
        "lookback_days": 30,
        "search_query": "",
        "review_filter": "all",
        "month_value": timezone.localdate().strftime("%Y-%m"),
        "month_options": [],
        "period_label": timezone.localdate().strftime("%b %Y"),
        "work_review_rules": {
            "attempt_threshold": int(company_profile.work_review_zero_talk_attempt_threshold or 10),
            "idle_gap_seconds": int(company_profile.work_review_idle_gap_seconds or 60),
            "connected_cooldown_seconds": int(company_profile.work_review_connected_cooldown_seconds or 90),
            "followup_expired_penalty_points": int(
                company_profile.work_review_followup_expired_penalty_points or 4
            ),
            "followup_expired_penalty_cap": int(company_profile.work_review_followup_expired_penalty_cap or 24),
        },
        "review_summary": {
            "total_staff": len(review_rows),
            "filtered_staff_count": len(review_rows),
            "review_needed_count": 0,
            "attention_count": 0,
            "stable_count": 0,
            "quiet_count": len(review_rows),
            "zero_talk_total": 0,
            "invalid_short_total": 0,
            "missed_callbacks_total": 0,
            "flagged_day_total": 0,
            "expired_followup_total": 0,
        },
        "review_rows": review_rows,
        "zero_talk_staff_rows": [],
    }


def _fallback_live_monitoring_payload():
    team_payload = _fallback_team_payload()
    staff_rows = []
    for row in team_payload["team_rows"]:
        staff_rows.append(
            {
                **row,
                "session_state_label": "Unavailable",
                "gap_count": 0,
                "gap_total_label": "0s",
                "gap_uncounted_label": "0s",
                "gap_buffer_label": "0s",
                "call_time_label": "0s",
                "status_note": "Live monitoring details are temporarily unavailable. Basic staff details are still shown.",
                "is_on_call": False,
                "current_call": None,
            }
        )
    return {
        "today_label": _fallback_today_label(),
        "generated_at_label": _fallback_today_label(),
        "summary": {
            "total_staff": team_payload["team_summary"]["total_staff"],
            "active_accounts": team_payload["team_summary"]["active_accounts"],
            "online_now": 0,
            "on_call_now": 0,
            "away_now": 0,
            "offline_now": team_payload["team_summary"]["total_staff"],
            "review_needed_now": 0,
            "alert_now": 0,
            "total_assigned": team_payload["team_summary"]["total_assigned"],
            "total_calls_today": 0,
            "total_converted_today": 0,
            "active_hours_label": "0.0h",
        },
        "spotlight_rows": staff_rows[:6],
        "staff_rows": staff_rows,
    }


def _fallback_referral_monitoring_payload():
    return {
        "today_label": _fallback_today_label(),
        "search_query": "",
        "stage_filter": "all",
        "reward_filter": "all",
        "summary": {
            "total": 0,
            "not_joined": 0,
            "joined": 0,
            "started_working": 0,
            "completed": 0,
            "pending_rewards": 0,
            "paid_rewards": 0,
            "pending_total_label": "Rs. 0.00",
            "program_enabled": False,
            "required_hours_label": "0.0h",
            "reward_amount_label": "Rs. 0.00",
        },
        "rows": [],
    }


def _fallback_salary_payload():
    salary_rows = []
    for row in _fallback_basic_staff_rows():
        staff = Staff.objects.filter(id=row["id"]).first()
        schedule_label = _fallback_schedule_label(staff) if staff else "Running earned amount"
        weekly_payout_day_label = staff.get_weekly_payout_day_display() if staff and staff.weekly_payout_day else ""
        salary_rows.append(
            {
                "id": row["id"],
                "name": row["name"],
                "phone": row["phone"],
                "email": row["email"],
                "compensation_type": row["compensation_type"],
                "compensation_type_label": row["compensation_type_label"],
                "schedule_label": schedule_label,
                "weekly_payout_day_label": weekly_payout_day_label,
                "hourly_rate": row["hourly_rate"],
                "bank_name": "Bank details available in staff profile" if staff and staff.bank_name else "Bank details not added",
                "bank_account_number": staff.bank_account_number if staff and staff.bank_account_number else "Account number not added",
                "due_balance_raw": "0.00",
                "due_balance": "Rs. 0.00",
                "due_period_label": "Temporarily unavailable",
                "due_earned_total": "Rs. 0.00",
                "due_paid_total": "Rs. 0.00",
                "due_hours_label": "0s",
                "due_base_pay": "Rs. 0.00",
                "due_call_earnings": "Rs. 0.00",
                "due_bonus_earnings": "Rs. 0.00",
                "advance_available_raw": "0.00",
                "advance_available": "Rs. 0.00",
                "running_period_label": "Temporarily unavailable",
                "running_earned_total": "Rs. 0.00",
                "running_paid_total": "Rs. 0.00",
                "can_pay_salary": False,
                "can_pay_advance": False,
                "can_pay_referral_rewards": False,
                "pending_referral_reward_total": "Rs. 0.00",
                "pending_referral_reward_total_raw": "0.00",
                "pending_referral_reward_count": 0,
                "pending_referral_rewards": [],
            }
        )
    return {
        "today_label": _fallback_today_label(),
        "summary": {
            "pending_total": "Rs. 0.00",
            "credited_total": "Rs. 0.00",
            "pending_staff_count": 0,
            "advance_total": "Rs. 0.00",
            "advance_staff_count": 0,
            "pending_referral_total": "Rs. 0.00",
            "pending_referral_count": 0,
            "referral_enabled": False,
            "paid_transaction_count": 0,
        },
        "salary_rows": salary_rows,
        "pending_salary_rows": salary_rows,
        "recent_payment_rows": [],
        "recent_referral_reward_rows": [],
        "payment_method_options": [
            {"value": value, "label": label}
            for value, label in Salary.PaymentMethod.choices
        ],
    }


def _safe_admin_payload(builder, fallback_factory, *, label, request=None, **builder_kwargs):
    try:
        return builder(**builder_kwargs)
    except Exception as error:
        logger.exception("Admin payload build failed for %s", label)
        if request is not None:
            messages.error(
                request,
                f"Some admin data could not be loaded right now. "
                f"{error.__class__.__name__}: {error}. A safe fallback view is being shown.",
            )
        return fallback_factory()


def _apply_staff_post_save_actions(staff, was_active):
    released_count = 0
    if was_active and not staff.is_active:
        rotate_auth_session(staff)
        end_staff_session(staff, close_reason="admin_disabled")
        released_count = release_staff_queue(staff)
        auto_allocate_leads()
    elif staff.is_active and staff.receives_new_leads:
        auto_allocate_leads(target_staff=staff)
    return released_count


def _refresh_queue_after_admin_lead_save(*, lead, previous_assigned_to_id=None, explicit_assignment=False):
    previous_staff = None
    if previous_assigned_to_id and previous_assigned_to_id != lead.assigned_to_id:
        previous_staff = Staff.objects.filter(
            id=previous_assigned_to_id,
            role=Staff.Role.STAFF,
            is_active=True,
        ).first()

    lead_is_active_queue = lead.status in (
        Lead.Status.NEW,
        Lead.Status.CALL_BACK,
        Lead.Status.INTERESTED,
    )

    if explicit_assignment and lead_is_active_queue and lead.assigned_to_id:
        target_staff = Staff.objects.filter(
            id=lead.assigned_to_id,
            role=Staff.Role.STAFF,
            is_active=True,
        ).first()
        if previous_staff:
            auto_allocate_leads(target_staff=previous_staff)
        if target_staff:
            auto_allocate_leads(
                target_staff=target_staff,
                prioritized_lead_ids=[lead.id],
            )
        return

    if previous_staff:
        auto_allocate_leads(target_staff=previous_staff)
        if lead.assigned_to_id and lead_is_active_queue:
            return

    if lead.assigned_to_id is None and lead_is_active_queue:
        auto_allocate_leads()
        return

    auto_allocate_leads()


_PROFILE_DOCUMENT_FIELDS = {
    "aadhar": "aadhar_photo",
    "passbook": "passbook_photo",
}


def _get_staff_document_file(staff, document_type):
    field_name = _PROFILE_DOCUMENT_FIELDS.get(document_type)
    if not field_name:
        raise Http404("Unknown document.")
    file_field = getattr(staff, field_name, None)
    if not file_field:
        raise Http404("Document not found.")
    if not file_field.name or not file_field.storage.exists(file_field.name):
        raise Http404("Document not found.")
    return file_field


def _document_response(file_field, *, content_type=None, as_attachment=False):
    guessed_type, _ = mimetypes.guess_type(file_field.name)
    resolved_content_type = content_type or guessed_type or "application/octet-stream"
    filename = Path(file_field.name).name
    disposition = "attachment" if as_attachment else "inline"
    response = FileResponse(file_field.open("rb"), content_type=resolved_content_type)
    response["Content-Disposition"] = f'{disposition}; filename="{filename}"'
    response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0, private"
    response["Pragma"] = "no-cache"
    response["Expires"] = "0"
    response["X-Content-Type-Options"] = "nosniff"
    return response


@require_http_methods(["GET", "POST"])
def web_login_page(request):
    current_user = get_staff_from_request(request)
    if current_user and current_user.role == Staff.Role.ADMIN:
        return redirect("dashboard")

    if request.method == "GET":
        return render(request, "admin_login.html", {"company_profile": get_company_profile()})

    serializer = LoginSerializer(data=request.POST)
    if not serializer.is_valid():
        return render(
            request,
            "admin_login.html",
            {
                "submitted_identifier": (
                    request.POST.get("identifier", "").strip()
                    or request.POST.get("phone", "").strip()
                ),
                "company_profile": get_company_profile(),
            },
            status=400,
        )

    staff = authenticate_staff(
        serializer.validated_data["identifier"],
        serializer.validated_data["password"],
        required_role=Staff.Role.ADMIN,
    )
    if not staff:
        messages.error(request, "Invalid admin credentials.")
        return render(
            request,
            "admin_login.html",
            {
                "submitted_identifier": serializer.validated_data["identifier"],
                "company_profile": get_company_profile(),
            },
            status=400,
        )

    mark_staff_seen(staff)
    tokens = issue_tokens_for_user(staff)
    request.session["show_admin_welcome"] = True
    response = redirect("dashboard")
    set_auth_cookies(response, tokens["refresh_token"])
    return response


@require_http_methods(["POST"])
def web_logout(request):
    current_user = get_staff_from_request(request)
    if current_user and current_user.is_active:
        rotate_auth_session(current_user)
    response = redirect("web-login")
    clear_auth_cookies(response)
    return response


@require_http_methods(["GET", "POST"])
def developer_login_page(request):
    current_user = get_staff_from_request(request)
    if current_user and current_user.is_active and current_user.role in {Staff.Role.ADMIN, Staff.Role.DEVELOPER}:
        return redirect("developer-releases-page")

    if request.method == "GET":
        return render(request, "developer_login.html", {"company_profile": get_company_profile()})

    serializer = LoginSerializer(data=request.POST)
    if not serializer.is_valid():
        return render(
            request,
            "developer_login.html",
            {
                "submitted_identifier": (
                    request.POST.get("identifier", "").strip()
                    or request.POST.get("phone", "").strip()
                ),
                "company_profile": get_company_profile(),
            },
            status=400,
        )

    staff = authenticate_staff(
        serializer.validated_data["identifier"],
        serializer.validated_data["password"],
    )
    if not staff or staff.role not in {Staff.Role.ADMIN, Staff.Role.DEVELOPER}:
        messages.error(request, "Invalid developer credentials.")
        return render(
            request,
            "developer_login.html",
            {
                "submitted_identifier": serializer.validated_data["identifier"],
                "company_profile": get_company_profile(),
            },
            status=400,
        )

    mark_staff_seen(staff)
    tokens = issue_tokens_for_user(staff)
    response = redirect("developer-releases-page")
    set_auth_cookies(response, tokens["refresh_token"])
    return response


@require_http_methods(["POST"])
def developer_logout(request):
    current_user = get_staff_from_request(request)
    if current_user and current_user.is_active:
        rotate_auth_session(current_user)
    response = redirect("developer-login")
    clear_auth_cookies(response)
    return response


@require_http_methods(["GET", "POST"])
def developer_releases_page(request):
    current_user = _get_developer_user_or_redirect(request)
    if not current_user:
        return redirect("developer-login")

    release_form_data = {
        "version_name": "",
        "version_code": "",
        "minimum_supported_version_code": "0",
        "release_notes": "",
        "is_mandatory": False,
        "is_active": True,
        "published_at": timezone.localtime().strftime("%Y-%m-%dT%H:%M"),
    }
    release_errors = {}

    if request.method == "POST":
        release_action = request.POST.get("release_action", "upload_release")
        if release_action == "set_active_release":
            release_id = request.POST.get("release_id", "").strip()
            try:
                release = AppRelease.objects.get(id=release_id)
            except AppRelease.DoesNotExist:
                messages.error(request, "Release not found.")
            else:
                set_active_app_release(release)
                messages.success(request, f"{release.version_name} is now the active published release.")
                return redirect("developer-releases-page")
        elif release_action == "delete_release":
            release_id = request.POST.get("release_id", "").strip()
            try:
                release = AppRelease.objects.get(id=release_id)
            except AppRelease.DoesNotExist:
                messages.error(request, "Release not found.")
            else:
                release_name = release.version_name
                try:
                    delete_app_release(release)
                except ValueError as error:
                    messages.error(request, str(error))
                else:
                    messages.success(request, f"{release_name} was removed from stored updates.")
                    return redirect("developer-releases-page")
        elif release_action == "reassign_followup_owners":
            repair_summary = reassign_unassigned_followup_owners()
            if repair_summary["scanned_count"] == 0:
                messages.info(request, "No unassigned follow-up leads were found to repair.")
            elif repair_summary["reassigned_count"] == 0:
                messages.warning(
                    request,
                    f"Checked {repair_summary['scanned_count']} unassigned follow-up lead(s), but none had a clear active staff owner to restore.",
                )
            else:
                messages.success(
                    request,
                    f"Follow-up owner repair completed. Reassigned {repair_summary['reassigned_count']} of {repair_summary['scanned_count']} unassigned follow-up lead(s)."
                    + (
                        f" {repair_summary['still_unassigned_count']} still need manual review."
                        if repair_summary["still_unassigned_count"] > 0
                        else ""
                    ),
                )
            return redirect("developer-releases-page")
        else:
            release_form_data = {
                "version_name": request.POST.get("version_name", "").strip(),
                "version_code": request.POST.get("version_code", "").strip(),
                "minimum_supported_version_code": request.POST.get("minimum_supported_version_code", "0").strip(),
                "release_notes": request.POST.get("release_notes", "").strip(),
                "is_mandatory": request.POST.get("is_mandatory") == "on",
                "is_active": request.POST.get("is_active") == "on",
                "published_at": request.POST.get("published_at", "").strip(),
            }
            serializer_data = {
                "version_name": release_form_data["version_name"],
                "version_code": release_form_data["version_code"],
                "minimum_supported_version_code": release_form_data["minimum_supported_version_code"],
                "release_notes": release_form_data["release_notes"],
                "is_mandatory": release_form_data["is_mandatory"],
                "is_active": release_form_data["is_active"],
                "apk_file": request.FILES.get("apk_file"),
            }
            if release_form_data["published_at"]:
                serializer_data["published_at"] = release_form_data["published_at"]
            serializer = CreateAppReleaseSerializer(data=serializer_data)
            if serializer.is_valid():
                release = publish_app_release(created_by=current_user, validated_data=serializer.validated_data)
                messages.success(request, f"Mobile update {release.version_name} published successfully.")
                return redirect("developer-releases-page")

            release_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the update details and upload the file again.")

    context = {
        "developer_user": current_user,
        "company_profile": get_company_profile(),
        "page_title": "Mobile Updates",
        "release_form_data": release_form_data,
        "release_errors": release_errors,
        **build_developer_release_payload(request),
    }
    return render(request, "developer_releases.html", context)


@require_GET
def app_release_download(request, release_id):
    release = AppRelease.objects.filter(id=release_id).first()
    if not release or not release.apk_file:
        raise Http404("Release not found.")
    return _document_response(
        release.apk_file,
        content_type="application/vnd.android.package-archive",
        as_attachment=True,
    )

@require_GET
def health_check(request):
    return JsonResponse({"status": "ok"})


@require_GET
def dashboard_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = _safe_admin_payload(
        build_dashboard_payload,
        _fallback_dashboard_payload,
        label="dashboard-page",
        request=request,
    )
    context = _admin_web_context(
        request,
        current_user,
        active_page="dashboard",
        page_title="Dashboard",
        page_heading="Dashboard",
        page_subtitle="Overview of live activity, lead flow, and salary projection.",
        extra_context={
            "dashboard": payload["dashboard"],
            "live_staff": payload["live_staff"],
            "lead_rows": payload["lead_rows"],
            "salary_records": payload["salary_records"],
            "team_directory": payload["team_directory"],
            "chart_payload": payload["chart_payload"],
        },
    )
    return render(request, "heavenection_calltrack_web.html", context)


@require_http_methods(["GET", "POST"])
def settings_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    settings_payload = build_settings_payload(current_user)
    company_profile = settings_payload["company_profile"]
    profile_form_data = {
        "name": current_user.name,
        "phone": current_user.phone,
        "password": "",
    }
    company_form_data = {
        "company_name": company_profile.company_name,
        "legal_name": company_profile.legal_name,
        "company_email": company_profile.company_email,
        "company_phone": company_profile.company_phone,
        "support_phone": company_profile.support_phone,
        "website": company_profile.website,
        "address_line_1": company_profile.address_line_1,
        "address_line_2": company_profile.address_line_2,
        "city": company_profile.city,
        "state": company_profile.state,
        "postal_code": company_profile.postal_code,
        "country": company_profile.country,
        "tax_identifier": company_profile.tax_identifier,
        "lead_queue_target_per_staff": company_profile.lead_queue_target_per_staff,
        "description": company_profile.description,
        "remove_logo": False,
    }
    profile_errors = {}
    company_errors = {}
    active_settings_tab = "profile"

    if request.method == "POST":
        settings_section = request.POST.get("settings_section", "profile")
        active_settings_tab = settings_section

        if settings_section == "profile":
            password_value = request.POST.get("password", "")
            profile_form_data = {
                "name": request.POST.get("name", "").strip(),
                "phone": request.POST.get("phone", "").strip(),
                "password": password_value,
            }
            profile_data = {
                "name": profile_form_data["name"],
                "phone": profile_form_data["phone"],
            }
            if password_value.strip():
                profile_data["password"] = password_value.strip()
            serializer = AdminProfileUpdateSerializer(current_user, data=profile_data, partial=True)
            if serializer.is_valid():
                current_user = serializer.save()
                messages.success(request, "Admin profile updated successfully.")
                return redirect("settings-page")
            profile_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the admin profile details and try again.")

        elif settings_section == "company":
            company_form_data = {
                "company_name": request.POST.get("company_name", "").strip(),
                "legal_name": request.POST.get("legal_name", "").strip(),
                "company_email": request.POST.get("company_email", "").strip(),
                "company_phone": request.POST.get("company_phone", "").strip(),
                "support_phone": request.POST.get("support_phone", "").strip(),
                "website": request.POST.get("website", "").strip(),
                "address_line_1": request.POST.get("address_line_1", "").strip(),
                "address_line_2": request.POST.get("address_line_2", "").strip(),
                "city": request.POST.get("city", "").strip(),
                "state": request.POST.get("state", "").strip(),
                "postal_code": request.POST.get("postal_code", "").strip(),
                "country": request.POST.get("country", "").strip(),
                "tax_identifier": request.POST.get("tax_identifier", "").strip(),
                "lead_queue_target_per_staff": request.POST.get("lead_queue_target_per_staff", "").strip(),
                "description": request.POST.get("description", "").strip(),
                "remove_logo": request.POST.get("remove_logo") == "on",
            }
            company_data = company_form_data.copy()
            if request.FILES.get("logo"):
                company_data["logo"] = request.FILES["logo"]
            serializer = CompanyProfileUpdateSerializer(company_profile, data=company_data, partial=True)
            if serializer.is_valid():
                serializer.save()
                messages.success(request, "Company settings updated successfully.")
                return redirect("settings-page")
            company_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the company details and try again.")

    settings_payload = build_settings_payload(current_user)
    context = _admin_web_context(
        request,
        current_user,
        active_page="settings",
        page_title="Admin Profile",
        page_heading="Admin Profile",
        page_subtitle="Manage admin access, branding, company contact information, and address details.",
        extra_context={
            **settings_payload,
            "profile_form_data": profile_form_data,
            "company_form_data": company_form_data,
            "profile_errors": profile_errors,
            "company_errors": company_errors,
            "active_settings_tab": active_settings_tab,
        },
    )
    return render(request, "admin_profile.html", context)


@require_GET
def staff_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = _safe_admin_payload(
        build_team_management_payload,
        _fallback_team_payload,
        label="staff-page",
        request=request,
    )
    context = _admin_web_context(
        request,
        current_user,
        active_page="staff",
        page_title="Staff Management",
        page_heading="Staff Management",
        page_subtitle="Create, update, activate, and review telecalling staff members.",
        extra_context=payload,
    )
    return render(request, "admin_staff.html", context)


@require_http_methods(["GET", "POST"])
def staff_profile_page(request, staff_id):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    try:
        staff = Staff.objects.get(id=staff_id, role=Staff.Role.STAFF)
    except Staff.DoesNotExist:
        return redirect("staff-page")

    staff_form_data = {
        "name": staff.name,
        "phone": staff.phone,
        "email": staff.email,
        "password": "",
        "hourly_rate": staff.hourly_rate,
        "call_rate": staff.call_rate,
        "bonus_per_conversion": staff.bonus_per_conversion,
        "bank_account_name": staff.bank_account_name,
        "bank_name": staff.bank_name,
        "bank_account_number": staff.bank_account_number,
        "bank_ifsc_code": staff.bank_ifsc_code,
        "aadhar_number": staff.aadhar_number,
        "remove_aadhar_photo": False,
        "remove_passbook_photo": False,
        "is_active": staff.is_active,
        "receives_new_leads": staff.receives_new_leads,
    }
    staff_errors = {}

    if request.method == "POST":
        staff_action = request.POST.get("staff_action", "save_profile")
        if staff_action == "toggle_active":
            desired_active = request.POST.get("set_active") == "1"
            serializer = UpdateStaffSerializer(staff, data={"is_active": desired_active}, partial=True)
            if serializer.is_valid():
                was_active = staff.is_active
                staff = serializer.save()
                released_count = _apply_staff_post_save_actions(staff, was_active)
                if staff.is_active:
                    if staff.receives_new_leads:
                        messages.success(request, f"{staff.name} is now enabled and can receive leads again.")
                    else:
                        messages.success(
                            request,
                            f"{staff.name} is now enabled, but new lead intake is still paused.",
                        )
                else:
                    messages.success(
                        request,
                        f"{staff.name} is now disabled. {released_count} active leads were unassigned.",
                    )
                return redirect("staff-profile-page", staff_id=staff.id)

            staff_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Unable to change the staff account status.")
        elif staff_action == "toggle_lead_intake":
            desired_receives = request.POST.get("set_receives_new_leads") == "1"
            serializer = UpdateStaffSerializer(staff, data={"receives_new_leads": desired_receives}, partial=True)
            if serializer.is_valid():
                staff = serializer.save()
                if staff.receives_new_leads:
                    messages.success(request, f"{staff.name} will receive new leads again.")
                    if staff.is_active:
                        auto_allocate_leads(target_staff=staff)
                else:
                    messages.success(request, f"{staff.name} will stay active, but new leads are paused.")
                return redirect("staff-profile-page", staff_id=staff.id)

            staff_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Unable to update lead intake control.")
        elif staff_action == "reassign_review_leads":
            summary = reassign_staff_review_leads(staff)
            if summary["review_count"] <= 0:
                messages.info(request, "No review leads were found for this staff member.")
            else:
                messages.success(
                    request,
                    (
                        f"{summary['assigned_count']} review lead(s) were returned to {staff.name}'s queue. "
                        f"{summary['waiting_count']} remain waiting for the next queue slot. "
                        f"{summary['released_count']} current queue lead(s) were released first."
                    ),
                )
            return redirect("staff-profile-page", staff_id=staff.id)
        elif staff_action == "reset_review_leads":
            summary = reset_staff_review_leads_to_new_queue(staff)
            if summary["review_count"] <= 0:
                messages.info(request, "No review leads were found for this staff member.")
            else:
                messages.success(
                    request,
                    f"{summary['reopened_count']} review lead(s) were reopened as new leads.",
                )
            return redirect("staff-profile-page", staff_id=staff.id)
        else:
            password_value = request.POST.get("password", "")
            was_receiving_new_leads = staff.receives_new_leads
            staff_form_data = {
                "name": request.POST.get("name", "").strip(),
                "phone": request.POST.get("phone", "").strip(),
                "email": request.POST.get("email", "").strip(),
                "password": password_value,
                "hourly_rate": request.POST.get("hourly_rate", "").strip(),
                "call_rate": request.POST.get("call_rate", "").strip(),
                "bonus_per_conversion": request.POST.get("bonus_per_conversion", "").strip(),
                "bank_account_name": request.POST.get("bank_account_name", "").strip(),
                "bank_name": request.POST.get("bank_name", "").strip(),
                "bank_account_number": request.POST.get("bank_account_number", "").strip(),
                "bank_ifsc_code": request.POST.get("bank_ifsc_code", "").strip(),
                "aadhar_number": request.POST.get("aadhar_number", "").strip(),
                "remove_aadhar_photo": request.POST.get("remove_aadhar_photo") == "on",
                "remove_passbook_photo": request.POST.get("remove_passbook_photo") == "on",
                "is_active": request.POST.get("is_active") == "on",
                "receives_new_leads": request.POST.get("receives_new_leads") == "on",
            }
            staff_data = {
                "name": staff_form_data["name"],
                "phone": staff_form_data["phone"],
                "email": staff_form_data["email"],
                "hourly_rate": staff_form_data["hourly_rate"] or "0",
                "call_rate": staff_form_data["call_rate"] or "0",
                "bonus_per_conversion": staff_form_data["bonus_per_conversion"] or "0",
                "bank_account_name": staff_form_data["bank_account_name"],
                "bank_name": staff_form_data["bank_name"],
                "bank_account_number": staff_form_data["bank_account_number"],
                "bank_ifsc_code": staff_form_data["bank_ifsc_code"],
                "aadhar_number": staff_form_data["aadhar_number"],
                "remove_aadhar_photo": staff_form_data["remove_aadhar_photo"],
                "remove_passbook_photo": staff_form_data["remove_passbook_photo"],
                "is_active": staff_form_data["is_active"],
                "receives_new_leads": staff_form_data["receives_new_leads"],
            }
            if password_value.strip():
                staff_data["password"] = password_value.strip()
            if request.FILES.get("aadhar_photo"):
                staff_data["aadhar_photo"] = request.FILES["aadhar_photo"]
            if request.FILES.get("passbook_photo"):
                staff_data["passbook_photo"] = request.FILES["passbook_photo"]

            serializer = UpdateStaffSerializer(staff, data=staff_data, partial=True)
            if serializer.is_valid():
                was_active = staff.is_active
                staff = serializer.save()
                released_count = _apply_staff_post_save_actions(staff, was_active)
                if was_active and not staff.is_active:
                    messages.success(
                        request,
                        f"Staff profile updated. {staff.name} was disabled and {released_count} active leads were unassigned.",
                    )
                elif staff.is_active and was_receiving_new_leads and not staff.receives_new_leads:
                    messages.success(
                        request,
                        f"{staff.name}'s profile updated and new lead intake is now paused.",
                    )
                elif staff.is_active and not was_receiving_new_leads and staff.receives_new_leads:
                    messages.success(
                        request,
                        f"{staff.name}'s profile updated and new lead intake is now enabled.",
                    )
                else:
                    messages.success(request, f"{staff.name}'s profile updated successfully.")
                return redirect("staff-profile-page", staff_id=staff.id)

            staff_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the staff profile details and try again.")

    payload = build_staff_profile_payload(request, staff)
    context = _admin_web_context(
        request,
        current_user,
        active_page="staff",
        page_title=f"{staff.name} Profile",
        page_heading=f"{staff.name} Profile",
        page_subtitle="Review staff activity, manage account access, and monitor assigned leads from one page.",
        extra_context={
            **payload,
            "staff_form_data": staff_form_data,
            "staff_errors": staff_errors,
        },
    )
    return render(request, "admin_staff_profile.html", context)


def staff_profile_report_pdf(request, staff_id):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    try:
        staff = Staff.objects.get(id=staff_id, role=Staff.Role.STAFF)
    except Staff.DoesNotExist:
        return redirect("staff-page")

    try:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.utils import ImageReader
        from reportlab.pdfgen import canvas
    except ImportError:
        messages.error(request, "PDF reports are not available on this server yet.")
        return redirect("staff-profile-page", staff_id=staff.id)

    month_value = request.GET.get("month", "").strip()
    month_date = _parse_month_value(month_value)
    if not month_date:
        month_date = _shift_month(timezone.localdate().replace(day=1), -1)
    range_start, range_end = _month_range_for_reference(
        month_date,
        end_at=timezone.localtime(timezone.now()),
    )
    breakdown = calculate_staff_payout_for_dates(
        staff,
        range_start.date(),
        range_end.date(),
    )
    quality = _build_staff_quality_metrics(
        [staff.id],
        range_start=range_start,
        range_end=range_end,
    ).get(staff.id, {})

    calls = Call.objects.filter(staff=staff, start_time__range=(range_start, range_end))
    total_calls = calls.exclude(status=Call.Status.STARTED).count()
    qualifying_calls = calls.filter(is_qualifying=True).count()
    connected_calls = calls.filter(is_verified=True, duration_seconds__gt=0).count()
    converted_calls = calls.filter(status=Call.Status.CONVERTED).count()
    followup_calls = calls.filter(status=Call.Status.INTERESTED).count()
    callback_calls = calls.filter(status=Call.Status.CALL_BACK).count()
    rejected_calls = calls.filter(status=Call.Status.NOT_INTERESTED).count()
    no_answer_calls = calls.filter(status=Call.Status.NO_ANSWER).count()
    invalid_short_calls = calls.filter(status=Call.Status.INVALID_SHORT).count()

    sessions = Session.objects.filter(staff=staff, login_time__range=(range_start, range_end))
    session_count = sessions.count()
    first_login = sessions.order_by("login_time").first()
    last_logout = sessions.exclude(logout_time=None).order_by("-logout_time").first()

    company_profile = get_company_profile()
    response = HttpResponse(content_type="application/pdf")
    file_month = month_date.strftime("%b-%Y")
    generated_stamp = timezone.localtime(timezone.now()).strftime("%Y%m%d-%H%M")
    safe_name = "".join(char for char in staff.name if char.isalnum() or char in (" ", "-", "_")).strip()
    safe_name = safe_name.replace(" ", "-") or "staff"
    response["Content-Disposition"] = (
        f'attachment; filename="staff-report-{safe_name}-{file_month}-{generated_stamp}.pdf"'
    )
    response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response["Pragma"] = "no-cache"

    page_width, page_height = A4
    pdf = canvas.Canvas(response, pagesize=A4)
    margin = 40
    content_width = page_width - (margin * 2)
    y = page_height - margin

    brand_color = colors.HexColor("#4d5c90")
    accent_color = colors.HexColor("#4d5c90")
    muted_color = colors.HexColor("#5d6c85")
    light_fill = colors.HexColor("#f3f6fd")
    border_color = colors.HexColor("#dbe4f3")

    def draw_divider(y_pos):
        pdf.setStrokeColor(border_color)
        pdf.setLineWidth(1)
        pdf.line(margin, y_pos, page_width - margin, y_pos)

    def ensure_space(required_height):
        nonlocal y
        if y - required_height < 60:
            pdf.showPage()
            y = page_height - margin

    def draw_page_border():
        pdf.setStrokeColor(colors.HexColor("#ccd6ea"))
        pdf.setLineWidth(1)
        pdf.rect(margin - 12, margin - 16, content_width + 24, page_height - (margin * 2) + 32, stroke=1, fill=0)

    def draw_kv_block(title, rows, *, columns=2, box_height=0, row_font=9.5):
        nonlocal y
        line_height = 14
        box_padding = 12
        row_count = len(rows)
        rows_per_col = (row_count + columns - 1) // columns
        box_height = box_height or (rows_per_col + 1) * line_height + box_padding * 2
        ensure_space(box_height + 12)

        pdf.setFillColor(light_fill)
        pdf.setStrokeColor(border_color)
        pdf.roundRect(margin, y - box_height, content_width, box_height, 12, fill=1, stroke=1)
        pdf.setFillColor(brand_color)
        pdf.setFont("Helvetica-Bold", 11)
        pdf.drawString(margin + box_padding, y - box_padding - 8, title)

        pdf.setFillColor(colors.black)
        pdf.setFont("Helvetica", row_font)
        column_width = (content_width - box_padding * 2) / columns
        text_y_start = y - box_padding - 24
        for col in range(columns):
            text_y = text_y_start
            start_index = col * rows_per_col
            end_index = min(start_index + rows_per_col, row_count)
            for label, value in rows[start_index:end_index]:
                pdf.drawString(margin + box_padding + (column_width * col), text_y, f"{label}: {value}")
                text_y -= line_height

        y = y - box_height - 16

    def draw_stat_row(stats, *, start_y):
        nonlocal y
        card_gap = 10
        card_count = len(stats)
        card_width = (content_width - (card_gap * (card_count - 1))) / card_count
        card_height = 62
        ensure_space(card_height + 12)
        for index, (label, value, helper) in enumerate(stats):
            x = margin + index * (card_width + card_gap)
            pdf.setFillColor(light_fill)
            pdf.setStrokeColor(border_color)
            pdf.roundRect(x, start_y - card_height, card_width, card_height, 10, fill=1, stroke=1)
            pdf.setFillColor(muted_color)
            pdf.setFont("Helvetica-Bold", 8.5)
            pdf.drawString(x + 10, start_y - 18, label.upper())
            pdf.setFillColor(brand_color)
            pdf.setFont("Helvetica-Bold", 13)
            pdf.drawString(x + 10, start_y - 36, value)
            if helper:
                pdf.setFillColor(muted_color)
                pdf.setFont("Helvetica", 8)
                pdf.drawString(x + 10, start_y - 50, helper)
        y = start_y - card_height - 18

    draw_page_border()
    pdf.setFillColor(brand_color)
    pdf.rect(0, page_height - 140, page_width, 140, fill=1, stroke=0)
    pdf.setFillColor(accent_color)
    accent_path = pdf.beginPath()
    accent_path.moveTo(0, page_height - 140)
    accent_path.lineTo(page_width * 0.55, page_height - 140)
    accent_path.lineTo(page_width, page_height - 230)
    accent_path.lineTo(page_width, page_height - 140)
    accent_path.close()
    pdf.drawPath(accent_path, fill=1, stroke=0)
    pdf.setFillColor(colors.white)
    pdf.setFont("Helvetica-Bold", 20)
    pdf.drawString(margin, page_height - 50, company_profile.company_name or "Heavenection")
    pdf.setFont("Helvetica", 11)
    pdf.drawString(margin, page_height - 72, "Staff Performance Report")
    pdf.setFont("Helvetica-Bold", 13)
    pdf.drawRightString(page_width - margin, page_height - 62, month_date.strftime("%B %Y"))

    logo_stream = None
    try:
        if company_profile.logo and company_profile.logo.storage.exists(company_profile.logo.name):
            logo_stream = company_profile.logo.open("rb")
        else:
            default_logo_path = settings.BASE_DIR / "static" / "images" / "heavenection-logo.png"
            if default_logo_path.exists():
                logo_stream = default_logo_path.open("rb")
        if logo_stream:
            logo_reader = ImageReader(logo_stream)
            pdf.drawImage(
                logo_reader,
                margin,
                page_height - 122,
                width=46,
                height=46,
                mask="auto",
            )
    except Exception:
        pass
    finally:
        if logo_stream:
            try:
                logo_stream.close()
            except Exception:
                pass

    y = page_height - 160
    pdf.setFillColor(muted_color)
    pdf.setFont("Helvetica", 9)
    contact_line = " | ".join(
        part
        for part in (
            company_profile.legal_name or "",
            company_profile.company_email or "",
            company_profile.company_phone or "",
            company_profile.website or "",
        )
        if part
    )
    if contact_line:
        pdf.drawString(margin, y, contact_line)
        y -= 20
    address_line = ", ".join(
        part
        for part in (
            company_profile.address_line_1,
            company_profile.address_line_2,
            company_profile.city,
            company_profile.state,
            company_profile.postal_code,
            company_profile.country,
        )
        if part
    )
    if address_line:
        pdf.drawString(margin, y, address_line)
        y -= 20
    draw_divider(y)
    y -= 14

    stat_rows = [
        ("Work Hours", _format_work_duration_label(breakdown["active_seconds"]), "Monthly total"),
        ("Total Calls", f"{total_calls}", "All attempts"),
        ("Conversions", f"{converted_calls}", "Successful leads"),
        ("Total Earnings", _format_currency(breakdown["total_pay"]), "Monthly total"),
    ]
    draw_stat_row(stat_rows, start_y=y)

    pdf.setFillColor(colors.black)
    pdf.setFont("Helvetica-Bold", 21)
    pdf.drawString(margin, y - 8, staff.name)
    pdf.setFont("Helvetica", 10)
    pdf.setFillColor(muted_color)
    pdf.drawString(margin, y - 28, f"{staff.phone} | {staff.get_compensation_type_display()} staff")
    pdf.drawRightString(
        page_width - margin,
        y - 28,
        f"Report Period: {range_start.date().strftime('%d %b %Y')} to {range_end.date().strftime('%d %b %Y')}",
    )
    y -= 52
    pdf.setFont("Helvetica", 9.5)
    pdf.setFillColor(muted_color)
    pdf.drawString(margin, y + 18, f"Prepared for: {staff.name}")
    pdf.drawRightString(page_width - margin, y + 18, f"Issued by: {company_profile.company_name or 'Heavenection'}")

    cover_summary_rows = [
        ("Total Calls", str(total_calls)),
        ("Connected Calls", str(connected_calls)),
        ("Converted Leads", str(converted_calls)),
        ("Work Hours", _format_work_duration_label(breakdown["active_seconds"])),
        ("Total Earnings", _format_currency(breakdown["total_pay"])),
    ]
    draw_kv_block("Executive Summary", cover_summary_rows, columns=2, box_height=108, row_font=9)

    pdf.setFillColor(muted_color)
    pdf.setFont("Helvetica", 8.5)
    pdf.drawString(margin, 36, "This report is confidential and intended for internal use only.")
    pdf.showPage()

    y = page_height - margin
    draw_page_border()
    pdf.setFillColor(brand_color)
    pdf.rect(0, page_height - 60, page_width, 60, fill=1, stroke=0)
    pdf.setFillColor(colors.white)
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(margin, page_height - 38, "Detailed Performance Overview")
    pdf.setFont("Helvetica", 9.5)
    pdf.drawRightString(page_width - margin, page_height - 38, month_date.strftime("%B %Y"))
    y = page_height - 80

    staff_rows = [
        ("Name", staff.name),
        ("Phone", staff.phone),
        ("Email", staff.email or "--"),
        ("Role", staff.get_role_display()),
        ("Compensation", staff.get_compensation_type_display()),
    ]
    draw_kv_block("Staff Details", staff_rows, columns=2, row_font=9)

    summary_rows = [
        ("Call Minutes", f"{float(breakdown['call_minutes']):,.1f} min"),
        ("Connected Calls", str(connected_calls)),
        ("Follow Up", str(followup_calls)),
        ("Scheduled Follow Up", str(callback_calls)),
        ("Rejected", str(rejected_calls)),
        ("No Response", str(no_answer_calls)),
        ("Invalid Short", str(invalid_short_calls)),
        ("Sessions", str(session_count)),
        ("First Login", _format_datetime(first_login.login_time) if first_login else "--"),
        ("Last Logout", _format_datetime(last_logout.logout_time) if last_logout else "--"),
    ]
    draw_kv_block("Call & Session Summary", summary_rows, columns=2, row_font=9)

    earnings_rows = [
        ("Base Pay", _format_currency(breakdown["base_pay"])),
        ("Call Earnings", _format_currency(breakdown["call_earnings"])),
        ("Bonus Earnings", _format_currency(breakdown["bonus_earnings"])),
        ("Total Earnings", _format_currency(breakdown["total_pay"])),
        ("Qualifying Calls", str(qualifying_calls)),
        ("Converted Leads", str(converted_calls)),
    ]
    draw_kv_block("Earnings Breakdown", earnings_rows, columns=2, row_font=9)

    review_rows = [
        ("Score", f"{quality.get('score', 0)} / 100"),
        ("Status", quality.get("label", "No Recent Activity")),
        ("Note", quality.get("note", "--")),
    ]
    draw_kv_block("Review Score", review_rows, columns=1, row_font=9)

    ensure_space(60)
    pdf.setFillColor(muted_color)
    pdf.setFont("Helvetica", 9)
    pdf.drawString(margin, y, "Authorized Signature")
    pdf.setStrokeColor(border_color)
    pdf.line(margin, y - 10, margin + 200, y - 10)

    pdf.setFillColor(muted_color)
    pdf.setFont("Helvetica", 8.5)
    pdf.drawString(margin, 32, "For staff reference only.")
    pdf.drawRightString(page_width - margin, 32, f"Generated on {timezone.localdate().strftime('%d %b %Y')}")
    pdf.showPage()
    pdf.save()
    return response


@require_GET
def company_logo_view(request):
    company_profile = get_company_profile()
    logo_file = None
    logo_name = None
    if company_profile.logo and company_profile.logo.storage.exists(company_profile.logo.name):
        try:
            logo_file = company_profile.logo.open("rb")
            logo_name = company_profile.logo.name
        except Exception:
            logo_file = None
    if logo_file is None:
        default_logo_path = settings.BASE_DIR / "static" / "images" / "heavenection-logo.png"
        if not default_logo_path.exists():
            raise Http404("Logo not found.")
        logo_file = default_logo_path.open("rb")
        logo_name = str(default_logo_path)
    content_type, _ = mimetypes.guess_type(logo_name or "")
    return FileResponse(logo_file, content_type=content_type or "image/png")


@require_GET
def staff_document_page(request, staff_id, document_type):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    mark_staff_seen(current_user)
    staff = Staff.objects.filter(id=staff_id).first()
    if not staff:
        raise Http404("Staff member not found.")
    return _document_response(_get_staff_document_file(staff, document_type))


@require_http_methods(["GET", "POST"])
def leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        lead_action = request.POST.get("lead_action")
        if lead_action == "import":
            serializer = LeadImportUploadSerializer(
                data={
                    "file": request.FILES.get("file"),
                    "assignment_mode": request.POST.get("assignment_mode", "auto"),
                    "assigned_staff_ids": request.POST.getlist("assigned_staff_ids"),
                }
            )
            if serializer.is_valid():
                try:
                    summary = import_leads_from_upload(
                        serializer.validated_data["file"],
                        assignment_mode=serializer.validated_data.get("assignment_mode", "auto"),
                        assigned_staff=serializer.validated_data.get("assigned_staff_ids") or [],
                    )
                except ValueError as error:
                    messages.error(request, str(error))
                else:
                    assignment_note = ""
                    if summary.get("assignment_mode") == "selected_staff":
                        selected_names = ", ".join(summary.get("selected_staff_names") or [])
                        assignment_note = (
                            f" Replaced {summary.get('released_count', 0)} existing assigned leads and loaded the imported batch into: {selected_names or 'selected staff'}."
                        )
                    messages.success(
                        request,
                        "Lead import completed. "
                        f"Imported {summary['created_count']}, skipped {summary['skipped_count']}, "
                        f"assigned {summary['assigned_count']}, waiting {summary['remaining_unassigned_count']}."
                        f"{assignment_note}",
                    )
                return redirect("leads-page")

            messages.error(
                request,
                "Lead import failed. "
                + " ".join(_normalize_errors(serializer.errors).values()),
            )
            return redirect("leads-page")

        if lead_action == "queue_settings":
            raw_value = request.POST.get("lead_queue_target_per_staff", "").strip()
            try:
                queue_target = int(raw_value)
            except (TypeError, ValueError):
                messages.error(request, "Enter a valid lead target per staff.")
                return redirect("leads-page")

            if queue_target < 1:
                messages.error(request, "Lead target per staff must be at least 1.")
                return redirect("leads-page")

            company_profile = get_company_profile()
            company_profile.lead_queue_target_per_staff = queue_target
            company_profile.save(update_fields=["lead_queue_target_per_staff", "updated_at"])
            auto_allocate_leads()
            messages.success(
                request,
                f"Lead target updated. The system will now maintain {queue_target} active leads per staff whenever enough waiting leads are available.",
            )
            return redirect("leads-page")

        if lead_action == "bulk_delete":
            selected_lead_ids = [lead_id.strip() for lead_id in request.POST.getlist("selected_lead_ids") if lead_id.strip()]
            if not selected_lead_ids:
                messages.error(request, "Select at least one lead to delete.")
                return redirect("leads-page")

            deleted_count = Lead.objects.filter(id__in=selected_lead_ids).count()
            if deleted_count == 0:
                messages.error(request, "The selected leads could not be found.")
                return redirect("leads-page")

            Lead.objects.filter(id__in=selected_lead_ids).delete()
            auto_allocate_leads()
            messages.success(request, f"Deleted {deleted_count} selected leads successfully.")
            return redirect("leads-page")

        if lead_action == "bulk_allocate":
            selected_lead_ids = [
                lead_id.strip()
                for lead_id in request.POST.getlist("selected_lead_ids")
                if lead_id.strip()
            ]
            if not selected_lead_ids:
                messages.error(request, "Select at least one lead to allocate.")
                return redirect("leads-page")

            target_staff_id = request.POST.get("target_staff_id", "").strip()
            target_staff = Staff.objects.filter(
                id=target_staff_id,
                role=Staff.Role.STAFF,
                is_active=True,
            ).first()
            if not target_staff:
                messages.error(request, "Choose an active staff member for allocation.")
                return redirect("leads-page")

            summary = assign_selected_leads_to_staff_queue(
                selected_lead_ids=selected_lead_ids,
                target_staff=target_staff,
            )
            if summary["selected_count"] == 0:
                messages.error(request, "The selected leads could not be found.")
                return redirect("leads-page")
            if summary["eligible_count"] == 0:
                messages.error(
                    request,
                    "Only New or Follow Up leads can be moved into a staff queue.",
                )
                return redirect("leads-page")

            message = (
                f"Allocated {summary['assigned_count']} selected lead(s) to {target_staff.name}. "
                f"{summary['waiting_count']} remain waiting for the next queue slot."
            )
            if summary["displaced_count"]:
                message += (
                    f" {summary['displaced_count']} bottom queue lead(s) were moved out first."
                )
            if summary["skipped_count"]:
                message += (
                    f" {summary['skipped_count']} non-active lead(s) were skipped."
                )
            messages.success(request, message)
            return redirect("leads-page")

        if lead_action == "bulk_unassign":
            selected_lead_ids = [
                lead_id.strip()
                for lead_id in request.POST.getlist("selected_lead_ids")
                if lead_id.strip()
            ]
            if not selected_lead_ids:
                messages.error(request, "Select at least one lead to unassign.")
                return redirect("leads-page")

            unassignable_queryset = Lead.objects.filter(
                id__in=selected_lead_ids,
                assigned_to__isnull=False,
            )
            unassignable_count = unassignable_queryset.count()
            if unassignable_count == 0:
                messages.error(request, "The selected leads are already unassigned or could not be found.")
                return redirect("leads-page")

            unassignable_queryset.update(assigned_to=None, updated_at=timezone.now())
            messages.success(
                request,
                f"Moved {unassignable_count} selected lead(s) back to the waiting queue.",
            )
            return redirect("leads-page")

        if lead_action == "delete_oldest":
            delete_mode = request.POST.get("delete_mode", "").strip()
            raw_days = request.POST.get("older_than_days", "").strip()
            raw_count = request.POST.get("oldest_count", "").strip()
            try:
                if delete_mode == "age_days":
                    summary = delete_oldest_manageable_leads(older_than_days=raw_days)
                    messages.success(
                        request,
                        f"Deleted {summary['deleted_count']} lead(s) older than {int(raw_days)} day(s).",
                    )
                elif delete_mode == "oldest_count":
                    summary = delete_oldest_manageable_leads(oldest_count=raw_count)
                    messages.success(
                        request,
                        f"Deleted {summary['deleted_count']} oldest lead(s) from lead management.",
                    )
                else:
                    messages.error(request, "Choose delete by age or delete by oldest count.")
                    return redirect("leads-page")
            except (TypeError, ValueError) as error:
                messages.error(request, str(error))
            return redirect("leads-page")

        if lead_action == "save_auto_delete_settings":
            company_profile = get_company_profile()
            auto_enabled = request.POST.get("lead_auto_delete_enabled") == "on"
            mode = request.POST.get("lead_auto_delete_mode", "").strip()
            raw_days = request.POST.get("lead_auto_delete_days", "").strip() or str(company_profile.lead_auto_delete_days)
            raw_count = request.POST.get("lead_auto_delete_count", "").strip() or str(company_profile.lead_auto_delete_count)
            try:
                days_value = int(raw_days)
                count_value = int(raw_count)
            except (TypeError, ValueError):
                messages.error(request, "Enter valid automatic delete values.")
                return redirect("leads-page")

            if mode not in {"age_days", "oldest_count"}:
                messages.error(request, "Choose a valid automatic delete mode.")
                return redirect("leads-page")
            if days_value < 1:
                messages.error(request, "Automatic delete days must be at least 1.")
                return redirect("leads-page")
            if count_value < 1:
                messages.error(request, "Automatic delete count must be at least 1.")
                return redirect("leads-page")

            company_profile.lead_auto_delete_enabled = auto_enabled
            company_profile.lead_auto_delete_mode = mode
            company_profile.lead_auto_delete_days = days_value
            company_profile.lead_auto_delete_count = count_value
            company_profile.save(
                update_fields=[
                    "lead_auto_delete_enabled",
                    "lead_auto_delete_mode",
                    "lead_auto_delete_days",
                    "lead_auto_delete_count",
                    "updated_at",
                ]
            )
            if auto_enabled:
                messages.success(request, "Automatic lead delete is now active.")
            else:
                messages.success(request, "Automatic lead delete is now turned off.")
            return redirect("leads-page")

        messages.error(request, "Lead request could not be processed.")
        return redirect("leads-page")

    cleanup_summary = run_automatic_lead_cleanup_if_due()
    if cleanup_summary["ran"] and cleanup_summary["deleted_count"] > 0:
        messages.info(
            request,
            f"Automatic lead cleanup removed {cleanup_summary['deleted_count']} old lead(s) today.",
        )

    payload = build_lead_management_payload(
        query=request.GET.get("q", ""),
        status=request.GET.get("status", "all"),
        assignment=request.GET.get("assignment", "all"),
        callback_window=request.GET.get("callback_window", "all"),
        contact_state=request.GET.get("contact_state", "all"),
        notes_state=request.GET.get("notes_state", "all"),
        date_field=request.GET.get("date_field", "updated_at"),
        date_from=request.GET.get("date_from", ""),
        date_to=request.GET.get("date_to", ""),
        sort_by=request.GET.get("sort_by", "updated_at"),
        sort_dir=request.GET.get("sort_dir", "desc"),
        readd_only=request.GET.get("readd_only") == "on",
        page=request.GET.get("page", 1),
        page_size=request.GET.get("page_size", 25),
    )
    context = _admin_web_context(
        request,
        current_user,
        active_page="leads",
        page_title="Lead Management",
        page_heading="Lead Management",
        page_subtitle="Add new leads, assign them to staff, and monitor their latest call outcome.",
        extra_context=payload,
    )
    return render(request, "admin_leads.html", context)


@require_http_methods(["GET", "POST"])
def followups_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        followup_action = request.POST.get("followup_action")
        if followup_action == "update_followup_expiry_settings":
            company_profile = get_company_profile()
            settings_data = {
                "followup_auto_expire_enabled": request.POST.get("followup_auto_expire_enabled") == "on",
                "followup_auto_expire_days": (request.POST.get("followup_auto_expire_days") or "").strip(),
                "followup_staff_warning_days": (request.POST.get("followup_staff_warning_days") or "").strip(),
                "followup_sla_gate_enabled": request.POST.get("followup_sla_gate_enabled") == "on",
                "followup_sla_gate_mode": (request.POST.get("followup_sla_gate_mode") or "").strip(),
                "followup_uncalled_alert_enabled": request.POST.get("followup_uncalled_alert_enabled") == "on",
                "followup_uncalled_alert_hours": (request.POST.get("followup_uncalled_alert_hours") or "").strip(),
                "work_review_followup_expired_penalty_points": (
                    request.POST.get("work_review_followup_expired_penalty_points") or ""
                ).strip(),
                "work_review_followup_expired_penalty_cap": (
                    request.POST.get("work_review_followup_expired_penalty_cap") or ""
                ).strip(),
            }
            serializer = CompanyProfileUpdateSerializer(company_profile, data=settings_data, partial=True)
            if serializer.is_valid():
                serializer.save()
                if settings_data["followup_auto_expire_enabled"]:
                    messages.success(
                        request,
                        "Follow-up controls updated. "
                        f"Auto-expiry: {settings_data['followup_auto_expire_days']} day(s). "
                        f"Warning: {settings_data['followup_staff_warning_days']} day(s). "
                        f"SLA gate: {settings_data['followup_sla_gate_mode'] or 'allow_normal_calls'}. "
                        f"Uncalled alert: {settings_data['followup_uncalled_alert_hours']} hour(s).",
                    )
                else:
                    messages.success(request, "Follow-up controls updated. Auto-expiry disabled.")
            else:
                messages.error(
                    request,
                    "Unable to update follow-up expiry settings. "
                    + " ".join(_normalize_errors(serializer.errors).values()),
                )
            return redirect("followups-page")
        if followup_action == "recover_rejected_followup":
            lead_id = (request.POST.get("lead_id") or "").strip()
            recover_mode = (request.POST.get("recover_mode") or "").strip()
            target_status = Lead.Status.INTERESTED if recover_mode == "mark_interested_same_staff" else Lead.Status.NEW
            try:
                summary = recover_recovery_lead_to_owner(lead_id, target_status=target_status)
            except ValueError as error:
                messages.error(request, str(error))
                return redirect("followups-page")
            if summary["target_status"] == Lead.Status.INTERESTED:
                messages.success(
                    request,
                    f"{summary['lead_name']} moved to Follow Up under {summary['owner_name']}.",
                )
            else:
                messages.success(
                    request,
                    f"{summary['lead_name']} reassigned to {summary['owner_name']} as New lead.",
                )
            return redirect("followups-page")
        if followup_action == "reallocate_expired_followup":
            lead_id = (request.POST.get("lead_id") or "").strip()
            return_query = _expired_followup_redirect_query(request)
            try:
                summary = reallocate_expired_followup_to_owner(lead_id)
            except ValueError as error:
                messages.error(request, str(error))
                return redirect(reverse("expired-followups-page") + return_query)
            messages.success(
                request,
                f"{summary['lead_name']} moved back to the active queue under {summary['owner_name']}.",
            )
            return redirect(reverse("expired-followups-page") + return_query)
        if followup_action == "mark_rejected":
            lead_id = (request.POST.get("lead_id") or "").strip()
            if not lead_id:
                messages.error(request, "Select a follow-up lead to mark as rejected.")
                return redirect("followups-page")
            try:
                lead = Lead.objects.select_related("assigned_to").get(id=lead_id)
            except Lead.DoesNotExist:
                messages.error(request, "Follow-up lead not found.")
                return redirect("followups-page")

            if lead.status not in {Lead.Status.INTERESTED, Lead.Status.CALL_BACK}:
                messages.warning(
                    request,
                    f"{lead.name} is no longer in the follow-up queue.",
                )
                return redirect("followups-page")

            previous_assigned_to_id = lead.assigned_to_id
            lead.status = Lead.Status.NOT_INTERESTED
            lead.callback_window = ""
            lead.callback_date = None
            lead.save(
                update_fields=[
                    "status",
                    "callback_window",
                    "callback_date",
                    "updated_at",
                ]
            )
            _refresh_queue_after_admin_lead_save(
                lead=lead,
                previous_assigned_to_id=previous_assigned_to_id,
                explicit_assignment=False,
            )
            messages.success(
                request,
                f"{lead.name} marked as Rejected and removed from staff follow-up queue.",
            )
            return redirect("followups-page")

        if followup_action == "csv_update":
            serializer = FollowupUpdateUploadSerializer(data={"file": request.FILES.get("file")})
            if serializer.is_valid():
                try:
                    summary = update_followups_from_upload(serializer.validated_data["file"])
                except ValueError as error:
                    messages.error(request, str(error))
                else:
                    if summary["error_messages"]:
                        messages.warning(
                            request,
                            "Follow-up updates finished with some skipped rows. "
                            + " ".join(summary["error_messages"]),
                        )
                    messages.success(
                        request,
                        "Follow-up CSV processed. "
                        f"Updated {summary['updated_count']}, skipped {summary['skipped_count']}, "
                        f"not found {summary['missing_count']}.",
                    )
                return redirect("followups-page")

            messages.error(
                request,
                "Follow-up CSV update failed. "
                + " ".join(_normalize_errors(serializer.errors).values()),
            )
            return redirect("followups-page")

        messages.error(request, "Follow-up request could not be processed.")
        return redirect("followups-page")

    if request.GET.get("download") == "csv":
        csv_content = build_followup_csv_response()
        response = HttpResponse(csv_content, content_type="text/csv")
        response["Content-Disposition"] = 'attachment; filename="heavenection-followups.csv"'
        return response
    if request.GET.get("download") == "xlsx":
        excel_content = build_followup_excel_response()
        response = HttpResponse(
            excel_content,
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = 'attachment; filename="heavenection-followups.xlsx"'
        return response

    context = _admin_web_context(
        request,
        current_user,
        active_page="followups",
        page_title="Follow-Up Queue",
        page_heading="Follow-Up Queue",
        page_subtitle="Keep the main follow-up queue focused on live work. Open the other queue pages for callbacks, recovery, and expired follow-ups.",
        extra_context=build_followup_payload(
            paginate=True,
            page=request.GET.get("page", 1),
            page_size=request.GET.get("page_size", 25),
        ),
    )
    return render(request, "admin_followups.html", context)


@require_GET
def interested_leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    search_query = request.GET.get("q", "").strip()
    date_from = request.GET.get("date_from", "").strip()
    date_to = request.GET.get("date_to", "").strip()
    staff_id = request.GET.get("staff_id", "").strip()
    outcome = request.GET.get("outcome", "all").strip()
    if request.GET.get("download") == "csv":
        csv_content = build_interested_lead_csv_response(
            query=search_query,
            date_from=date_from,
            date_to=date_to,
            staff_id=staff_id,
            outcome=outcome,
        )
        response = HttpResponse(csv_content, content_type="text/csv")
        response["Content-Disposition"] = 'attachment; filename="heavenection-interested-outcomes.csv"'
        return response
    if request.GET.get("download") == "xlsx":
        excel_content = build_interested_lead_excel_response(
            query=search_query,
            date_from=date_from,
            date_to=date_to,
            staff_id=staff_id,
            outcome=outcome,
        )
        response = HttpResponse(
            excel_content,
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = 'attachment; filename="heavenection-interested-outcomes.xlsx"'
        return response
    context = _admin_web_context(
        request,
        current_user,
        active_page="interested-leads",
        page_title="Interested Leads",
        page_heading="Interested Leads",
        page_subtitle="Track interested outcomes, review staff follow-up quality, and mark each lead as successful or unsuccessful.",
        extra_context=build_interested_lead_payload(
            query=search_query,
            date_from=date_from,
            date_to=date_to,
            staff_id=staff_id,
            outcome=outcome,
        ),
    )
    return render(request, "admin_interested_leads.html", context)


@require_GET
def callbacks_page(request):
    return redirect("followups-page")


def _expired_followup_redirect_query(request):
    query_params = {}
    for key in ("page", "page_size", "sort_by", "sort_dir"):
        value = (request.POST.get(f"return_{key}") or "").strip()
        if value:
            query_params[key] = value
    return f"?{urlencode(query_params)}" if query_params else ""


@require_GET
def expired_followups_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = build_followup_payload()
    expired_rows = list(payload.get("expired_followup_rows", []))
    try:
        normalized_page_size = int(request.GET.get("page_size", 25) or 25)
    except (TypeError, ValueError):
        normalized_page_size = 25
    normalized_page_size = max(10, min(normalized_page_size, 100))
    normalized_sort_by = (request.GET.get("sort_by", "updated_at") or "updated_at").strip()
    normalized_sort_dir = (request.GET.get("sort_dir", "desc") or "desc").strip().lower()
    normalized_sort_dir = "asc" if normalized_sort_dir == "asc" else "desc"
    valid_sort_fields = {"updated_at", "days_idle", "name", "phone", "assigned_to", "last_contacted"}
    if normalized_sort_by not in valid_sort_fields:
        normalized_sort_by = "updated_at"

    reverse_sort = normalized_sort_dir == "desc"
    if normalized_sort_by == "days_idle":
        expired_rows.sort(key=lambda row: int(row.get("days_idle") or 0), reverse=reverse_sort)
    elif normalized_sort_by == "name":
        expired_rows.sort(key=lambda row: str(row.get("name") or "").lower(), reverse=reverse_sort)
    elif normalized_sort_by == "phone":
        expired_rows.sort(key=lambda row: str(row.get("phone") or ""), reverse=reverse_sort)
    elif normalized_sort_by == "assigned_to":
        expired_rows.sort(key=lambda row: str(row.get("assigned_to") or "").lower(), reverse=reverse_sort)
    elif normalized_sort_by == "last_contacted":
        expired_rows.sort(key=lambda row: str(row.get("last_contacted_sort") or ""), reverse=reverse_sort)
    else:
        expired_rows.sort(key=lambda row: str(row.get("updated_at_sort") or ""), reverse=reverse_sort)

    paginator = Paginator(expired_rows, normalized_page_size)
    try:
        page_obj = paginator.page(request.GET.get("page", 1) or 1)
    except EmptyPage:
        page_obj = paginator.page(paginator.num_pages or 1)

    page_window = 2
    start_page = max(1, page_obj.number - page_window)
    end_page = min(paginator.num_pages or 1, page_obj.number + page_window)
    base_query_params = [
        ("page_size", str(normalized_page_size)),
        ("sort_by", normalized_sort_by),
        ("sort_dir", normalized_sort_dir),
    ]
    base_querystring = f"?{urlencode(base_query_params)}" if base_query_params else ""

    context = _admin_web_context(
        request,
        current_user,
        active_page="expired-followups",
        page_title="Expired Follow-Ups",
        page_heading="Expired Follow-Ups",
        page_subtitle="Review follow-up leads that aged out, then move them back to the active queue when needed.",
        extra_context={
            **payload,
            "expired_followup_rows": list(page_obj.object_list),
            "expired_followup_filters": {
                "page_size": normalized_page_size,
                "sort_by": normalized_sort_by,
                "sort_dir": normalized_sort_dir,
            },
            "expired_followup_filter_options": {
                "sort_fields": [
                    {"value": "updated_at", "label": "Updated time"},
                    {"value": "days_idle", "label": "Days idle"},
                    {"value": "name", "label": "Lead name"},
                    {"value": "phone", "label": "Phone number"},
                    {"value": "assigned_to", "label": "Last owner"},
                    {"value": "last_contacted", "label": "Last contact"},
                ],
                "sort_directions": [
                    {"value": "desc", "label": "Newest / highest first"},
                    {"value": "asc", "label": "Oldest / lowest first"},
                ],
                "page_sizes": [
                    {"value": 25, "label": "25 per page"},
                    {"value": 50, "label": "50 per page"},
                    {"value": 100, "label": "100 per page"},
                ],
            },
            "expired_followup_pagination": {
                "page_number": page_obj.number,
                "num_pages": paginator.num_pages or 1,
                "filtered_count": len(expired_rows),
                "has_previous": page_obj.has_previous(),
                "has_next": page_obj.has_next(),
                "previous_page_number": page_obj.previous_page_number() if page_obj.has_previous() else 1,
                "next_page_number": page_obj.next_page_number() if page_obj.has_next() else (paginator.num_pages or 1),
                "start_index": page_obj.start_index() if expired_rows else 0,
                "end_index": page_obj.end_index() if expired_rows else 0,
                "page_numbers": [
                    {"number": page_number, "is_current": page_number == page_obj.number}
                    for page_number in range(start_page, end_page + 1)
                ],
                "base_querystring": base_querystring,
            },
            "expired_followup_return_query": reverse("expired-followups-page") + base_querystring,
        },
    )
    return render(request, "admin_expired_followups.html", context)


@require_http_methods(["GET", "POST"])
def recovery_leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        recovery_action = request.POST.get("recovery_action")
        if recovery_action == "recover_single":
            lead_id = (request.POST.get("lead_id") or "").strip()
            recover_mode = (request.POST.get("recover_mode") or "").strip()
            target_status = Lead.Status.INTERESTED if recover_mode == "mark_interested_same_staff" else Lead.Status.NEW
            try:
                summary = recover_recovery_lead_to_owner(lead_id, target_status=target_status)
            except ValueError as error:
                messages.error(request, str(error))
                return redirect("recovery-leads-page")
            if summary["target_status"] == Lead.Status.INTERESTED:
                messages.success(
                    request,
                    f"{summary['lead_name']} moved to Follow Up under {summary['owner_name']}.",
                )
            else:
                messages.success(
                    request,
                    f"{summary['lead_name']} reassigned to {summary['owner_name']} as New lead.",
                )
            return redirect("recovery-leads-page")
        if recovery_action == "reactivate_oldest":
            raw_count = request.POST.get("readd_count", "").strip()
            scope = request.POST.get("readd_scope", "all").strip() or "all"
            raw_max_readd = request.POST.get("max_readd_count", "").strip()
            try:
                readd_count = int(raw_count)
            except (TypeError, ValueError):
                messages.error(request, "Enter a valid number of leads to re-add.")
                return redirect("recovery-leads-page")
            max_readd_count = None
            if raw_max_readd != "":
                try:
                    max_readd_count = int(raw_max_readd)
                except (TypeError, ValueError):
                    messages.error(request, "Enter a valid re-add count filter.")
                    return redirect("recovery-leads-page")

            if readd_count < 1:
                messages.error(request, "Re-add count must be at least 1.")
                return redirect("recovery-leads-page")

            summary = reactivate_oldest_recovery_leads(
                readd_count,
                scope=scope,
                max_readd_count=max_readd_count,
            )
            if scope == "rejected":
                messages.warning(request, "Rejected leads can no longer be re-added to the calling queue.")
                return redirect("recovery-leads-page")
            if summary["reactivated_count"] == 0:
                messages.warning(request, "No no-response leads were available for re-allocation.")
            else:
                messages.success(
                    request,
                    "Recovery leads re-added. "
                    f"Moved {summary['reactivated_count']} oldest leads back to the active queue, "
                    f"assigned {summary['assigned_count']}, waiting {summary['remaining_unassigned_count']}.",
                )
            return redirect("recovery-leads-page")
        if recovery_action == "delete_selected":
            selected_ids = request.POST.getlist("selected_recovery_ids")
            try:
                summary = delete_recovery_leads_by_ids(selected_ids)
            except Exception as error:
                logger.exception("Recovery lead delete selected failed.")
                messages.error(request, f"Delete failed. {error.__class__.__name__}: {error}")
                return redirect("recovery-leads-page")
            if summary["deleted_count"] <= 0:
                messages.warning(request, "No leads were deleted. Select rejected or no response leads first.")
            else:
                messages.success(request, f"Deleted {summary['deleted_count']} recovery lead(s).")
            return redirect("recovery-leads-page")
        if recovery_action == "delete_filtered":
            raw_count = request.POST.get("delete_count", "").strip()
            scope = request.POST.get("delete_scope", "all").strip() or "all"
            raw_max_readd = request.POST.get("delete_max_readd_count", "").strip()
            try:
                delete_count = int(raw_count)
            except (TypeError, ValueError):
                messages.error(request, "Enter a valid number of leads to delete.")
                return redirect("recovery-leads-page")
            max_readd_count = None
            if raw_max_readd != "":
                try:
                    max_readd_count = int(raw_max_readd)
                except (TypeError, ValueError):
                    messages.error(request, "Enter a valid re-add count filter.")
                    return redirect("recovery-leads-page")
            try:
                summary = delete_recovery_leads_filtered(
                    delete_count,
                    scope=scope,
                    max_readd_count=max_readd_count,
                )
            except Exception as error:
                logger.exception("Recovery lead delete filtered failed.")
                messages.error(request, f"Delete failed. {error.__class__.__name__}: {error}")
                return redirect("recovery-leads-page")
            if summary["deleted_count"] <= 0:
                messages.warning(request, "No leads matched the delete filters.")
            else:
                messages.success(request, f"Deleted {summary['deleted_count']} recovery lead(s).")
            return redirect("recovery-leads-page")

        messages.error(request, "Recovery lead request could not be processed.")
        return redirect("recovery-leads-page")

    context = _admin_web_context(
        request,
        current_user,
        active_page="recovery",
        page_title="Rejected & No Response",
        page_heading="Rejected & No Response",
        page_subtitle="Review closed leads with clear filters, clean paging, and quick recovery actions.",
        extra_context=build_recovery_lead_payload(
            query=request.GET.get("q", ""),
            status=request.GET.get("status", "all"),
            assignment=request.GET.get("assignment", "all"),
            sort_by=request.GET.get("sort_by", "updated_at"),
            sort_dir=request.GET.get("sort_dir", "desc"),
            page=request.GET.get("page", 1),
            page_size=request.GET.get("page_size", 25),
            readd_min=request.GET.get("readd_min", ""),
            readd_max=request.GET.get("readd_max", ""),
        ),
    )
    return render(request, "admin_recovery_leads.html", context)


@require_GET
def learning_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    context = _admin_web_context(
        request,
        current_user,
        active_page="learning",
        page_title="Learning Center",
        page_heading="Learning Center",
        page_subtitle="Publish training lessons, assign mandatory learning, and track lesson completion across the team.",
        extra_context=build_learning_management_payload(),
    )
    return render(request, "admin_learning.html", context)


@require_http_methods(["GET", "POST"])
def work_review_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST" and request.POST.get("work_review_action") == "update_rules":
        company_profile = get_company_profile()
        update_payload = {
            "work_review_zero_talk_attempt_threshold": request.POST.get(
                "work_review_zero_talk_attempt_threshold", ""
            ).strip(),
            "work_review_idle_gap_seconds": request.POST.get("work_review_idle_gap_seconds", "").strip(),
            "work_review_connected_cooldown_seconds": request.POST.get(
                "work_review_connected_cooldown_seconds", ""
            ).strip(),
            "work_review_followup_expired_penalty_points": request.POST.get(
                "work_review_followup_expired_penalty_points", ""
            ).strip(),
            "work_review_followup_expired_penalty_cap": request.POST.get(
                "work_review_followup_expired_penalty_cap", ""
            ).strip(),
        }
        serializer = CompanyProfileUpdateSerializer(company_profile, data=update_payload, partial=True)
        if serializer.is_valid():
            serializer.save()
            messages.success(request, "Work review rules updated successfully.")
        else:
            errors = _normalize_errors(serializer.errors)
            error_message = " ".join(errors.values()) if errors else "Please correct the work review rule values."
            messages.error(request, f"Unable to update work review rules. {error_message}")
        return_query = request.POST.get("return_query", "").strip()
        if return_query:
            return redirect(f"{request.path}?{return_query}")
        return redirect(request.path)

    search_query = request.GET.get("q", "").strip()
    review_filter = request.GET.get("review", "all").strip().lower() or "all"
    month_value = request.GET.get("month", "").strip()
    payload = _safe_admin_payload(
        lambda: build_work_review_payload(
            search_query=search_query,
            review_filter=review_filter,
            month_value=month_value,
        ),
        _fallback_work_review_payload,
        label="work-review-page",
        request=request,
    )
    payload["return_query"] = request.GET.urlencode()
    context = _admin_web_context(
        request,
        current_user,
        active_page="work-review",
        page_title="Work Review Center",
        page_heading="Work Review Center",
        page_subtitle="Review calling patterns, empty attempts, and callback gaps from one dedicated monitoring page.",
        extra_context=payload,
    )
    return render(request, "admin_work_review.html", context)


@require_GET
def live_monitoring_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = _safe_admin_payload(
        build_live_monitoring_payload,
        _fallback_live_monitoring_payload,
        label="live-monitoring-page",
        request=request,
    )
    context = _admin_web_context(
        request,
        current_user,
        active_page="live-monitoring",
        page_title="Command Center",
        page_heading="Command Center",
        page_subtitle="Control live staff behaviour, call intelligence, queue pressure, and review signals from one futuristic dashboard.",
        extra_context={
            **payload,
            "live_monitoring_payload": payload,
        },
    )
    return render(request, "admin_live_monitoring.html", context)


def performance_monitoring_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = _safe_admin_payload(
        build_live_monitoring_payload,
        _fallback_live_monitoring_payload,
        label="performance-monitoring-page",
        request=request,
    )
    context = _admin_web_context(
        request,
        current_user,
        active_page="performance-monitoring",
        page_title="Performance Monitoring",
        page_heading="Performance Monitoring",
        page_subtitle="Advanced performance watch with live motion, queue pressure, risk scoring, and staff comparison on one rich monitoring page.",
        extra_context={
            **payload,
            "performance_monitoring_payload": payload,
        },
    )
    return render(request, "admin_performance_monitoring.html", context)


def referral_monitoring_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    search_query = request.GET.get("q", "").strip()
    stage_filter = request.GET.get("stage", "all").strip().lower() or "all"
    reward_filter = request.GET.get("reward", "all").strip().lower() or "all"
    context = _admin_web_context(
        request,
        current_user,
        active_page="referrals",
        page_title="Referral Monitoring",
        page_heading="Referral Monitoring",
        page_subtitle="Track who referred, who joined, and where rewards stand across the team.",
        extra_context=_safe_admin_payload(
            lambda: build_referral_monitoring_payload(
                search_query=search_query,
                stage_filter=stage_filter,
                reward_filter=reward_filter,
            ),
            _fallback_referral_monitoring_payload,
            label="referral-monitoring-page",
            request=request,
        ),
    )
    return render(request, "admin_referral_monitoring.html", context)


@require_http_methods(["GET", "POST"])
def app_notifications_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        action = request.POST.get("notification_action", "").strip()
        if action == "send_notification":
            title = request.POST.get("title", "").strip()
            message_text = request.POST.get("message", "").strip()
            severity = request.POST.get("severity", AppNotification.Severity.NORMAL).strip()
            audience = request.POST.get("audience", AppNotification.Audience.ALL_STAFF).strip()
            delivery_mode = request.POST.get("delivery_mode", "instant").strip()
            target_staff_id = request.POST.get("target_staff_id", "").strip()
            auto_dismiss_value = request.POST.get("auto_dismiss_seconds", "6").strip()
            show_from_value = request.POST.get("show_from", "").strip()
            show_until_value = request.POST.get("show_until", "").strip()

            if not message_text:
                messages.error(request, "Enter the notification message.")
                return redirect("app-notifications-page")
            if severity not in AppNotification.Severity.values:
                messages.error(request, "Choose a valid notification level.")
                return redirect("app-notifications-page")
            if audience not in AppNotification.Audience.values:
                messages.error(request, "Choose who should receive this notification.")
                return redirect("app-notifications-page")

            target_staff = None
            if audience == AppNotification.Audience.SINGLE_STAFF:
                target_staff = Staff.objects.filter(
                    id=target_staff_id,
                    role=Staff.Role.STAFF,
                    is_active=True,
                ).first()
                if not target_staff:
                    messages.error(request, "Choose an active staff member for a single-staff notification.")
                    return redirect("app-notifications-page")

            try:
                auto_dismiss_seconds = max(1, min(int(auto_dismiss_value or "6"), 60))
            except ValueError:
                messages.error(request, "Auto close seconds must be between 1 and 60.")
                return redirect("app-notifications-page")

            show_from = timezone.now()
            if delivery_mode == "future":
                if not show_from_value:
                    messages.error(request, "Enter a future start time for the scheduled notification.")
                    return redirect("app-notifications-page")
                parsed = parse_datetime(show_from_value)
                if parsed is None:
                    try:
                        parsed = datetime.fromisoformat(show_from_value)
                    except ValueError:
                        parsed = None
                if parsed is None:
                    messages.error(request, "Enter a valid start time for this notification.")
                    return redirect("app-notifications-page")
                if timezone.is_naive(parsed):
                    parsed = timezone.make_aware(parsed, timezone.get_current_timezone())
                show_from = parsed
                if show_from <= timezone.now():
                    messages.error(request, "Scheduled notification start time must be in the future.")
                    return redirect("app-notifications-page")
            elif delivery_mode != "instant":
                messages.error(request, "Choose send now or schedule for later.")
                return redirect("app-notifications-page")

            show_until = None
            if show_until_value:
                parsed = parse_datetime(show_until_value)
                if parsed is None:
                    try:
                        parsed = datetime.fromisoformat(show_until_value)
                    except ValueError:
                        parsed = None
                if parsed is None:
                    messages.error(request, "Enter a valid end time for this notification.")
                    return redirect("app-notifications-page")
                if timezone.is_naive(parsed):
                    parsed = timezone.make_aware(parsed, timezone.get_current_timezone())
                show_until = parsed
                if show_until <= show_from:
                    messages.error(request, "Notification end time must be after the start time.")
                    return redirect("app-notifications-page")

            AppNotification.objects.create(
                title=title,
                message=message_text,
                severity=severity,
                source=AppNotification.Source.MANUAL,
                audience=audience,
                target_staff=target_staff,
                auto_dismiss_seconds=auto_dismiss_seconds,
                show_from=show_from,
                show_until=show_until,
                created_by=current_user,
            )
            if delivery_mode == "future":
                messages.success(request, "Future notification scheduled successfully.")
            else:
                messages.success(request, "Instant notification sent successfully.")
            return redirect("app-notifications-page")

        notification_id = request.POST.get("notification_id", "").strip()
        notification = AppNotification.objects.filter(id=notification_id).first()
        if not notification:
            messages.error(request, "Notification not found.")
            return redirect("app-notifications-page")

        if action == "deactivate_notification":
            notification.is_active = False
            notification.save(update_fields=["is_active", "updated_at"])
            messages.warning(request, "Notification deactivated.")
            return redirect("app-notifications-page")
        if action == "activate_notification":
            notification.is_active = True
            notification.save(update_fields=["is_active", "updated_at"])
            messages.success(request, "Notification activated again.")
            return redirect("app-notifications-page")
        if action == "delete_notification":
            notification.delete()
            messages.success(request, "Notification deleted.")
            return redirect("app-notifications-page")

        messages.error(request, "Notification action could not be processed.")
        return redirect("app-notifications-page")

    payload = build_app_notification_management_payload()
    context = _admin_web_context(
        request,
        current_user,
        active_page="app-notifications",
        page_title="App Notifications",
        page_heading="App Notifications",
        page_subtitle="Send top in-app messages with color-coded levels, auto close timing, and manual close support.",
        extra_context={
            **payload,
            "active_staff_rows": Staff.objects.filter(role=Staff.Role.STAFF, is_active=True).order_by("name"),
            "severity_choices": AppNotification.Severity.choices,
            "audience_choices": AppNotification.Audience.choices,
        },
    )
    return render(request, "admin_app_notifications.html", context)


@require_http_methods(["GET", "POST"])
def salary_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payment_errors_by_staff = {}
    payment_form_values_by_staff = {}

    if request.method == "POST":
        payment_action = request.POST.get("payment_action", "").strip()

        if payment_action == "delete_payment_transaction":
            transaction_id = request.POST.get("transaction_id", "").strip()
            transaction = (
                SalaryPaymentTransaction.objects.select_related("salary_record", "salary_record__staff")
                .filter(id=transaction_id)
                .first()
            )
            if not transaction:
                messages.error(request, "Payment transaction not found.")
            else:
                delete_salary_payment_transaction(transaction)
                messages.success(request, "Payment transaction deleted successfully.")
                return redirect("salary-page")
        elif payment_action == "pay_current_salary":
            staff_id = request.POST.get("staff_id", "").strip()
            staff = Staff.objects.filter(id=staff_id, role=Staff.Role.STAFF).first()
            if not staff:
                messages.error(request, "Staff member not found.")
            else:
                form_data = {
                    "payout_cycle": request.POST.get("payout_cycle"),
                    "period_start": request.POST.get("period_start"),
                    "period_end": request.POST.get("period_end"),
                    "paid_amount": request.POST.get("paid_amount"),
                    "payment_kind": request.POST.get("payment_kind", SalaryPaymentTransaction.PaymentKind.SALARY),
                    "payment_method": request.POST.get("payment_method", Salary.PaymentMethod.BANK_TRANSFER),
                    "payment_reference": request.POST.get("payment_reference", ""),
                    "payment_note": request.POST.get("payment_note", ""),
                }
                serializer = SalaryPaymentSerializer(data=form_data)
                if serializer.is_valid():
                    try:
                        record, transaction, created = record_staff_salary_payment(
                            staff, **serializer.validated_data
                        )
                    except ValidationError as error:
                        payment_errors_by_staff[str(staff.id)] = _normalize_errors(
                            getattr(error, "message_dict", {"paid_amount": error.messages})
                        )
                        messages.error(request, "Please correct the salary payment details and try again.")
                    else:
                        payment_kind = serializer.validated_data.get(
                            "payment_kind",
                            SalaryPaymentTransaction.PaymentKind.SALARY,
                        )
                        email_result = {"queued": False, "message": ""}
                        if payment_kind == SalaryPaymentTransaction.PaymentKind.SALARY:
                            email_result = queue_salary_payment_acknowledgement(record)
                        remaining_balance = max(
                            float(record.final_salary or 0) - float(record.paid_amount or 0),
                            0.0,
                        )
                        entry_label = (
                            "Advance recorded"
                            if payment_kind == SalaryPaymentTransaction.PaymentKind.ADVANCE
                            else "Salary recorded"
                        )
                        messages.success(
                            request,
                            f"{entry_label} for {staff.name}. "
                            f"Credited Rs. {float(transaction.amount):,.2f} for {record.period_start} to {record.period_end}. "
                            f"Remaining balance Rs. {remaining_balance:,.2f}.",
                        )
                        if email_result["queued"]:
                            messages.success(request, email_result["message"])
                        elif email_result["message"]:
                            messages.warning(request, email_result["message"])
                        return redirect("salary-page")
                else:
                    payment_errors_by_staff[str(staff.id)] = _normalize_errors(serializer.errors)
                    messages.error(request, "Please correct the salary payment details and try again.")

                payment_form_values_by_staff[str(staff.id)] = {
                    "paid_amount": request.POST.get("paid_amount", ""),
                    "payment_kind": request.POST.get("payment_kind", SalaryPaymentTransaction.PaymentKind.SALARY),
                    "payment_method": request.POST.get("payment_method", Salary.PaymentMethod.BANK_TRANSFER),
                    "payment_reference": request.POST.get("payment_reference", ""),
                    "payment_note": request.POST.get("payment_note", ""),
                }
        elif payment_action == "pay_referral_reward":
            reward_id = request.POST.get("reward_id", "").strip()
            reward = (
                ReferralReward.objects.select_related("referrer", "referred_staff")
                .filter(id=reward_id, is_paid=False)
                .first()
            )
            if not reward:
                messages.error(request, "Referral reward could not be found.")
            else:
                try:
                    record_referral_reward_payment(
                        reward,
                        payment_method=request.POST.get(
                            "payment_method",
                            Salary.PaymentMethod.BANK_TRANSFER,
                        ),
                        payment_reference=request.POST.get("payment_reference", ""),
                        payment_note=request.POST.get("payment_note", ""),
                    )
                except ValidationError as error:
                    messages.error(
                        request,
                        " ".join(getattr(error, "messages", ["Referral reward could not be recorded."])),
                    )
                else:
                    messages.success(
                        request,
                        f"Referral reward recorded for {reward.referrer.name}. "
                        f"Reward {reward.reward_amount} from {reward.referred_staff.name} has been marked paid.",
                    )
                    return redirect("salary-page")
        else:
            messages.error(request, "Salary action could not be processed.")

    payload = _safe_admin_payload(
        build_salary_page_payload,
        _fallback_salary_payload,
        label="salary-page",
        request=request,
    )
    for row in payload["pending_salary_rows"]:
        row["payment_errors"] = payment_errors_by_staff.get(row["id"], {})
        row["payment_form"] = {
            "paid_amount": row["due_balance_raw"],
            "payment_kind": SalaryPaymentTransaction.PaymentKind.SALARY,
            "payment_method": Salary.PaymentMethod.BANK_TRANSFER,
            "payment_reference": "",
            "payment_note": "",
        }
        row["payment_form"].update(payment_form_values_by_staff.get(row["id"], {}))

    context = _admin_web_context(
        request,
        current_user,
        active_page="salary",
        page_title="Salary Overview",
        page_heading="Salary Overview",
        page_subtitle="Review earned salary as pending balance, pay the remaining amount, and keep paid salary visible in one place.",
        extra_context=payload,
    )
    return render(request, "admin_salary.html", context)


@require_http_methods(["GET", "POST"])
def salary_detail_page(request, staff_id):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    try:
        staff = Staff.objects.get(id=staff_id, role=Staff.Role.STAFF)
    except Staff.DoesNotExist:
        messages.error(request, "Staff member not found.")
        return redirect("salary-page")

    payment_errors = {}

    if request.method == "POST":
        payment_action = request.POST.get("payment_action", "").strip()
        if payment_action == "delete_payment_transaction":
            transaction_id = request.POST.get("transaction_id", "").strip()
            transaction = (
                SalaryPaymentTransaction.objects.select_related("salary_record", "salary_record__staff")
                .filter(id=transaction_id, salary_record__staff=staff)
                .first()
            )
            if not transaction:
                messages.error(request, "Payment transaction not found.")
            else:
                delete_salary_payment_transaction(transaction)
                messages.success(request, "Payment transaction deleted successfully.")
                return redirect("salary-detail-page", staff_id=staff.id)
        elif payment_action == "pay_current_salary":
            form_data = {
                "payout_cycle": request.POST.get("payout_cycle"),
                "period_start": request.POST.get("period_start"),
                "period_end": request.POST.get("period_end"),
                "paid_amount": request.POST.get("paid_amount"),
                "payment_kind": request.POST.get(
                    "payment_kind",
                    SalaryPaymentTransaction.PaymentKind.SALARY,
                ),
                "payment_method": request.POST.get(
                    "payment_method",
                    Salary.PaymentMethod.BANK_TRANSFER,
                ),
                "payment_reference": request.POST.get("payment_reference", ""),
                "payment_note": request.POST.get("payment_note", ""),
            }
            serializer = SalaryPaymentSerializer(data=form_data)
            if serializer.is_valid():
                try:
                    record, transaction, created = record_staff_salary_payment(
                        staff, **serializer.validated_data
                    )
                except ValidationError as error:
                    payment_errors = _normalize_errors(getattr(error, "message_dict", {"paid_amount": error.messages}))
                    messages.error(request, "Please correct the salary payment details and try again.")
                else:
                    payment_kind = serializer.validated_data.get(
                        "payment_kind",
                        SalaryPaymentTransaction.PaymentKind.SALARY,
                    )
                    email_result = {"queued": False, "message": ""}
                    if payment_kind == SalaryPaymentTransaction.PaymentKind.SALARY:
                        email_result = queue_salary_payment_acknowledgement(record)
                    remaining_balance = max(
                        float(record.final_salary or 0) - float(record.paid_amount or 0),
                        0.0,
                    )
                    action_label = (
                        "Advance recorded"
                        if payment_kind == SalaryPaymentTransaction.PaymentKind.ADVANCE
                        else "Salary recorded"
                    )
                    messages.success(
                        request,
                        f"{action_label} for {staff.name}. "
                        f"Credited Rs. {float(transaction.amount):,.2f} for {record.period_start} to {record.period_end}. "
                        f"Remaining balance Rs. {remaining_balance:,.2f}.",
                    )
                    if email_result.get("queued"):
                        messages.success(request, email_result["message"])
                    elif email_result.get("message"):
                        messages.warning(request, email_result["message"])
                    return redirect("salary-detail-page", staff_id=staff.id)
            else:
                payment_errors = _normalize_errors(serializer.errors)
                messages.error(request, "Please correct the salary payment details and try again.")
        elif payment_action == "pay_referral_reward":
            reward_id = request.POST.get("reward_id", "").strip()
            reward = (
                ReferralReward.objects.select_related("referrer", "referred_staff")
                .filter(id=reward_id, referrer=staff)
                .first()
            )
            if not reward:
                messages.error(request, "Referral reward not found.")
            else:
                try:
                    record_referral_reward_payment(
                        reward,
                        payment_method=request.POST.get(
                            "payment_method",
                            Salary.PaymentMethod.BANK_TRANSFER,
                        ),
                        payment_reference=request.POST.get("payment_reference", ""),
                        payment_note=request.POST.get("payment_note", ""),
                    )
                except ValidationError as error:
                    messages.error(
                        request,
                        " ".join(
                            error.messages
                            if hasattr(error, "messages")
                            else getattr(error, "message_dict", {}).values()
                        ),
                    )
                else:
                    messages.success(
                        request,
                        f"Referral reward paid for {reward.referred_staff.name}.",
                    )
                    return redirect("salary-detail-page", staff_id=staff.id)
        else:
            form_data = {
                "payout_cycle": request.POST.get("payout_cycle", "custom"),
                "period_start": request.POST.get("period_start"),
                "period_end": request.POST.get("period_end"),
                "paid_amount": request.POST.get("paid_amount"),
                "payment_method": request.POST.get("payment_method", ""),
                "payment_reference": request.POST.get("payment_reference", ""),
                "payment_note": request.POST.get("payment_note", ""),
            }

            serializer = SalaryPaymentSerializer(data=form_data)
            if serializer.is_valid():
                try:
                    record, transaction, created = record_staff_salary_payment(
                        staff, **serializer.validated_data
                    )
                except ValidationError as error:
                    payment_errors = _normalize_errors(getattr(error, "message_dict", {"paid_amount": error.messages}))
                    messages.error(request, "Please correct the salary payment details and try again.")
                else:
                    email_result = queue_salary_payment_acknowledgement(record)
                    remaining_balance = max(
                        float(record.final_salary or 0) - float(record.paid_amount or 0),
                        0.0,
                    )
                    messages.success(
                        request,
                        f"Salary recorded for {staff.name}. "
                        f"Credited Rs. {float(transaction.amount):,.2f} for {record.period_start} to {record.period_end}. "
                        f"Remaining balance Rs. {remaining_balance:,.2f}.",
                    )
                    if email_result["queued"]:
                        messages.success(request, email_result["message"])
                    else:
                        messages.warning(request, email_result["message"])
                    return redirect("salary-detail-page", staff_id=staff.id)
            else:
                payment_errors = _normalize_errors(serializer.errors)
                messages.error(request, "Please correct the salary payment details and try again.")

    payload = build_salary_detail_payload(staff)
    payment_form_data = {
        "payment_kind": request.POST.get("payment_kind", SalaryPaymentTransaction.PaymentKind.SALARY),
        "payout_cycle": request.POST.get("payout_cycle", payload["due_snapshot"]["payout_cycle"]),
        "period_start": request.POST.get("period_start", payload["custom_defaults"]["period_start"]),
        "period_end": request.POST.get("period_end", payload["custom_defaults"]["period_end"]),
        "paid_amount": request.POST.get("paid_amount", payload["custom_defaults"]["paid_amount"]),
        "payment_method": request.POST.get("payment_method", Salary.PaymentMethod.BANK_TRANSFER),
        "payment_reference": request.POST.get("payment_reference", ""),
        "payment_note": request.POST.get("payment_note", ""),
    }
    context = _admin_web_context(
        request,
        current_user,
        active_page="salary",
        page_title=f"{staff.name} Salary",
        page_heading=f"{staff.name} Salary Details",
        page_subtitle="Review earnings, calculations, due balance, and recorded payments from one payout page.",
        extra_context={
            **payload,
            "payment_errors": payment_errors,
            "payment_form_data": payment_form_data,
        },
    )
    return render(request, "admin_salary_detail.html", context)


@require_http_methods(["GET", "POST"])
def salary_control_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        if request.POST.get("salary_control_action") == "update_referral_settings":
            company_profile = get_company_profile()
            serializer = CompanyProfileUpdateSerializer(
                company_profile,
                data={
                    "referral_program_enabled": request.POST.get("referral_program_enabled") == "on",
                    "referral_required_hours": request.POST.get("referral_required_hours", "0"),
                    "referral_reward_amount": request.POST.get("referral_reward_amount", "0"),
                },
                partial=True,
            )
            if serializer.is_valid():
                serializer.save()
                messages.success(request, "Referral reward settings updated successfully.")
                return redirect("salary-control-page")
            messages.error(
                request,
                "Please correct the referral settings and try again. "
                + " ".join(_normalize_errors(serializer.errors).values()),
            )
        elif request.POST.get("salary_control_action") == "update_call_bonus_settings":
            company_profile = get_company_profile()
            serializer = CompanyProfileUpdateSerializer(
                company_profile,
                data={
                    "hourly_call_bonus_enabled": request.POST.get("hourly_call_bonus_enabled") == "on",
                    "hourly_call_bonus_threshold": request.POST.get("hourly_call_bonus_threshold", "50"),
                    "hourly_call_bonus_rate": request.POST.get("hourly_call_bonus_rate", "0.50"),
                },
                partial=True,
            )
            if serializer.is_valid():
                serializer.save()
                messages.success(request, "Hourly call bonus settings updated successfully.")
                return redirect("salary-control-page")
            messages.error(
                request,
                "Please correct the hourly call bonus settings and try again. "
                + " ".join(_normalize_errors(serializer.errors).values()),
            )
        elif request.POST.get("salary_control_action") == "update_conversion_bonus_settings":
            raw_amount = (request.POST.get("conversion_bonus_amount", "") or "").strip()
            try:
                amount = Decimal(raw_amount)
            except (InvalidOperation, TypeError, ValueError):
                messages.error(request, "Please enter a valid successful lead reward amount.")
            else:
                if amount < Decimal("0.00"):
                    messages.error(request, "Successful lead reward amount cannot be negative.")
                else:
                    normalized_amount = amount.quantize(Decimal("0.01"))
                    updated_count = (
                        Staff.objects.filter(role=Staff.Role.STAFF)
                        .update(bonus_per_conversion=normalized_amount)
                    )
                    messages.success(
                        request,
                        f"Successful lead reward updated to Rs. {float(normalized_amount):,.2f} for {updated_count} staff account(s).",
                    )
                    return redirect("salary-control-page")

    context = _admin_web_context(
        request,
        current_user,
        active_page="salary-control",
        page_title="Salary Control Panel",
        page_heading="Salary Control Panel",
        page_subtitle="Configure weekly, monthly, and hourly salary settings for each staff member.",
        extra_context=build_salary_control_payload(request),
    )
    return render(request, "admin_salary_control.html", context)


@require_GET
def calls_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    date_value = request.GET.get("date", "").strip()
    context = _admin_web_context(
        request,
        current_user,
        active_page="calls",
        page_title="Call Details",
        page_heading="Call Details",
        page_subtitle="Review call history, outcomes, and duration after staff calling activity.",
        extra_context=build_call_detail_payload(date_value=date_value),
    )
    return render(request, "admin_calls.html", context)


@require_GET
def working_hours_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    date_value = request.GET.get("date", "").strip()
    context = _admin_web_context(
        request,
        current_user,
        active_page="hours",
        page_title="Working Hours",
        page_heading="Working Hours",
        page_subtitle="Track work sessions, active time, and the current state of each staff member.",
        extra_context=_safe_admin_payload(
            lambda: build_work_hours_payload(date_value=date_value),
            _fallback_work_hours_payload,
            label="working-hours-page",
            request=request,
        ),
    )
    return render(request, "admin_working_hours.html", context)


@require_GET
def pwa_manifest(request):
    return HttpResponse(read_root_file("heavenection-manifest.json"), content_type="application/manifest+json")


@require_GET
def pwa_service_worker(request):
    return HttpResponse(read_root_file("heavenection-sw.js"), content_type="application/javascript")


@require_GET
def offline_page(request):
    return render(request, "web_offline.html")


@api_view(["POST"])
@permission_classes([AllowAny])
def login_api(request):
    serializer = LoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    staff = authenticate_staff(
        serializer.validated_data["identifier"],
        serializer.validated_data["password"],
    )
    if not staff:
        return Response({"detail": "Invalid credentials."}, status=400)

    mark_staff_seen(staff)
    tokens = issue_tokens_for_user(staff)
    return Response(
        {
            "access": tokens["access"],
            "refresh": tokens["refresh"],
            "user": StaffSerializer(staff).data,
        }
    )


@api_view(["GET"])
def auth_me_api(request):
    return Response(StaffSerializer(request.user).data)


@api_view(["GET", "PATCH"])
@permission_classes([IsCallingStaff])
def staff_profile_api(request):
    if request.method == "GET":
        return Response(StaffProfileSerializer(request.user, context={"request": request}).data)

    serializer = StaffProfileUpdateSerializer(request.user, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    staff = serializer.save()
    return Response(StaffProfileSerializer(staff, context={"request": request}).data)


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_profile_document_api(request, document_type):
    return _document_response(_get_staff_document_file(request.user, document_type))


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_salary_details_api(request):
    return Response(build_staff_salary_details_payload(request.user))


@api_view(["GET", "POST"])
@permission_classes([IsCallingStaff])
def staff_referrals_api(request):
    if request.method == "GET":
        submissions = (
            request.user.referral_submissions.select_related("joined_staff")
            .order_by("-created_at")[:20]
        )
        return Response(StaffReferralSubmissionSerializer(submissions, many=True).data)

    serializer = CreateStaffReferralSubmissionSerializer(
        data=request.data,
        context={"request": request},
    )
    serializer.is_valid(raise_exception=True)
    submission = serializer.save()
    return Response(
        StaffReferralSubmissionSerializer(submission).data,
        status=201,
    )


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_app_update_api(request):
    raw_version_code = request.query_params.get("version_code", "0")
    try:
        current_version_code = int(raw_version_code)
    except (TypeError, ValueError):
        current_version_code = 0
    return Response(build_app_update_payload(request, current_version_code=current_version_code))

@api_view(["POST"])
def logout_api(request):
    if request.user.is_authenticated:
        rotate_auth_session(request.user)
    response = Response({"detail": "Logged out."})
    clear_auth_cookies(response)
    return response


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def dashboard_data_api(request):
    return Response(
        _safe_admin_payload(
            build_dashboard_payload,
            _fallback_dashboard_payload,
            label="dashboard-api",
        )
    )


@api_view(["GET", "PATCH"])
@permission_classes([IsAdminStaff])
def admin_profile_api(request):
    if request.method == "GET":
        return Response(AdminProfileSerializer(request.user).data)

    serializer = AdminProfileUpdateSerializer(request.user, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    return Response(AdminProfileSerializer(user).data)


@api_view(["GET", "PATCH"])
@permission_classes([IsAdminStaff])
def company_profile_api(request):
    company_profile = get_company_profile()
    if request.method == "GET":
        return Response(CompanyProfileSerializer(company_profile, context={"request": request}).data)

    serializer = CompanyProfileUpdateSerializer(company_profile, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    company_profile = serializer.save()
    return Response(CompanyProfileSerializer(company_profile, context={"request": request}).data)


@api_view(["GET", "POST"])
@permission_classes([IsAdminStaff])
def leads_api(request):
    queryset = Lead.objects.select_related("assigned_to").order_by("-updated_at")
    if request.method == "GET":
        status_value = request.query_params.get("status")
        if status_value and status_value != "all":
            queryset = queryset.filter(status=status_value)
        return Response(LeadSerializer(queryset[:100], many=True).data)

    serializer = CreateLeadSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    lead = serializer.save()
    explicit_assignment = "assigned_to" in request.data
    _refresh_queue_after_admin_lead_save(
        lead=lead,
        explicit_assignment=explicit_assignment,
    )
    return Response(LeadSerializer(lead).data, status=201)


@api_view(["POST"])
@permission_classes([IsAdminStaff])
def import_leads_api(request):
    payload = request.data.copy()
    if hasattr(request.data, "getlist"):
        payload.setlist("assigned_staff_ids", request.data.getlist("assigned_staff_ids"))
    serializer = LeadImportUploadSerializer(data=payload)
    serializer.is_valid(raise_exception=True)
    summary = import_leads_from_upload(
        serializer.validated_data["file"],
        assignment_mode=serializer.validated_data.get("assignment_mode", "auto"),
        assigned_staff=serializer.validated_data.get("assigned_staff_ids") or [],
    )
    return Response(summary, status=201)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAdminStaff])
def lead_detail_api(request, lead_id):
    try:
        lead = Lead.objects.select_related("assigned_to").get(id=lead_id)
    except Lead.DoesNotExist:
        return Response({"detail": "Lead not found."}, status=404)

    if request.method == "GET":
        return Response(LeadSerializer(lead).data)

    if request.method == "DELETE":
        deleted_was_active = lead.status in (
            Lead.Status.NEW,
            Lead.Status.CALL_BACK,
            Lead.Status.INTERESTED,
        )
        lead.delete()
        if deleted_was_active:
            auto_allocate_leads()
        return Response(status=204)

    previous_assigned_to_id = lead.assigned_to_id
    previous_status = lead.status
    serializer = UpdateLeadSerializer(lead, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    lead = serializer.save()
    if previous_status != Lead.Status.CONVERTED and lead.status == Lead.Status.CONVERTED:
        ensure_converted_call_credit(lead)
    explicit_assignment = "assigned_to" in request.data
    _refresh_queue_after_admin_lead_save(
        lead=lead,
        previous_assigned_to_id=previous_assigned_to_id,
        explicit_assignment=explicit_assignment,
    )
    return Response(LeadSerializer(lead).data)


@api_view(["GET", "POST"])
@permission_classes([IsAdminStaff])
def training_lessons_api(request):
    queryset = TrainingLesson.objects.order_by("sort_order", "-published_at", "title")
    if request.method == "GET":
        search_query = request.query_params.get("q", "").strip()
        if search_query:
            queryset = queryset.filter(
                Q(title__icontains=search_query)
                | Q(description__icontains=search_query)
                | Q(search_keywords__icontains=search_query)
            )

        active_staff_count = Staff.objects.filter(role=Staff.Role.STAFF, is_active=True).count()
        lessons = list(queryset.annotate(completed_staff_count=Count("completions", distinct=True))[:200])
        for lesson in lessons:
            lesson.pending_staff_count = max(active_staff_count - lesson.completed_staff_count, 0)
        return Response(TrainingLessonSerializer(lessons, many=True).data)

    serializer = CreateTrainingLessonSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    lesson = serializer.save()
    lesson.completed_staff_count = 0
    lesson.pending_staff_count = Staff.objects.filter(role=Staff.Role.STAFF, is_active=True).count()
    return Response(TrainingLessonSerializer(lesson).data, status=201)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAdminStaff])
def training_lesson_detail_api(request, lesson_id):
    try:
        lesson = TrainingLesson.objects.get(id=lesson_id)
    except TrainingLesson.DoesNotExist:
        return Response({"detail": "Training lesson not found."}, status=404)

    if request.method == "GET":
        lesson.completed_staff_count = lesson.completions.count()
        lesson.pending_staff_count = max(
            Staff.objects.filter(role=Staff.Role.STAFF, is_active=True).count() - lesson.completed_staff_count,
            0,
        )
        return Response(TrainingLessonSerializer(lesson).data)

    if request.method == "DELETE":
        lesson.delete()
        return Response(status=204)

    serializer = UpdateTrainingLessonSerializer(lesson, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    lesson = serializer.save()
    lesson.completed_staff_count = lesson.completions.count()
    lesson.pending_staff_count = max(
        Staff.objects.filter(role=Staff.Role.STAFF, is_active=True).count() - lesson.completed_staff_count,
        0,
    )
    return Response(TrainingLessonSerializer(lesson).data)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def calls_api(request):
    queryset = Call.objects.select_related("staff", "lead").order_by("-start_time")
    status_value = request.query_params.get("status")
    if status_value and status_value != "all":
        queryset = queryset.filter(status=status_value)
    staff_id = request.query_params.get("staff_id")
    if staff_id:
        queryset = queryset.filter(staff_id=staff_id)
    return Response(CallSerializer(queryset[:200], many=True).data)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def working_hours_api(request):
    payload = _safe_admin_payload(
        build_work_hours_payload,
        _fallback_work_hours_payload,
        label="working-hours-api",
    )
    return Response(payload)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def live_staff_api(request):
    payload = _safe_admin_payload(
        build_dashboard_payload,
        _fallback_dashboard_payload,
        label="live-staff-api",
    )
    return Response(payload["live_staff"])


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def live_monitoring_api(request):
    return Response(
        _safe_admin_payload(
            build_live_monitoring_payload,
            _fallback_live_monitoring_payload,
            label="live-monitoring-api",
        )
    )


@api_view(["GET", "POST"])
@permission_classes([IsAdminStaff])
def admin_alerts_api(request):
    return Response(
        _safe_admin_payload(
            build_cached_admin_web_alert_payload,
            _fallback_admin_alert_payload,
            label="admin-alerts-api",
            request=request,
        )
    )


@api_view(["GET", "POST"])
@permission_classes([IsAdminStaff])
def team_members_api(request):
    if request.method == "GET":
        queryset = Staff.objects.filter(role=Staff.Role.STAFF).order_by("name")
        return Response(StaffSerializer(queryset, many=True).data)

    serializer = CreateStaffSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    staff = serializer.save()
    if staff.is_active:
        auto_allocate_leads(target_staff=staff)
    return Response(StaffSerializer(staff).data, status=201)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAdminStaff])
def team_member_detail_api(request, staff_id):
    try:
        staff = Staff.objects.get(id=staff_id, role=Staff.Role.STAFF)
    except Staff.DoesNotExist:
        return Response({"detail": "Staff not found."}, status=404)

    if request.method == "GET":
        return Response(StaffSerializer(staff).data)

    if request.method == "DELETE":
        staff.delete()
        auto_allocate_leads()
        return Response(status=204)

    was_active = staff.is_active
    serializer = UpdateStaffSerializer(staff, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    staff = serializer.save()
    _apply_staff_post_save_actions(staff, was_active)
    return Response(StaffSerializer(staff).data)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def salary_summary_api(request):
    payload = _safe_admin_payload(
        build_salary_page_payload,
        _fallback_salary_payload,
        label="salary-summary-api",
    )
    return Response(payload["salary_rows"])


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def salary_control_api(request):
    queryset = Staff.objects.filter(role=Staff.Role.STAFF).order_by("name")
    return Response(SalarySettingsSerializer(queryset, many=True).data)


@api_view(["GET", "PATCH"])
@permission_classes([IsAdminStaff])
def salary_control_detail_api(request, staff_id):
    try:
        staff = Staff.objects.get(id=staff_id, role=Staff.Role.STAFF)
    except Staff.DoesNotExist:
        return Response({"detail": "Staff not found."}, status=404)

    if request.method == "GET":
        return Response(SalarySettingsSerializer(staff).data)

    serializer = UpdateStaffSerializer(staff, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    staff = serializer.save()
    return Response(SalarySettingsSerializer(staff).data)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def staff_actions_api(request):
    queryset = StaffAction.objects.select_related("staff", "lead", "session", "call").order_by("-created_at")
    staff_id = request.query_params.get("staff_id")
    if staff_id:
        queryset = queryset.filter(staff_id=staff_id)

    try:
        limit = min(max(int(request.query_params.get("limit", 100)), 1), 250)
    except ValueError:
        limit = 100

    return Response(StaffActionSerializer(queryset[:limit], many=True).data)


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_today_summary_api(request):
    return Response(build_staff_today_payload(request.user))


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_notifications_api(request):
    return Response(
        {
            "notifications": build_staff_active_notifications_payload(request.user),
        }
    )


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_followups_api(request):
    return Response(build_staff_followups_payload(request.user))


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def assigned_leads_api(request):
    queryset = get_assigned_leads(request.user)
    status_value = request.query_params.get("status")
    if status_value and status_value != "all":
        queryset = queryset.filter(status=status_value)
    return Response(LeadSerializer(queryset[:100], many=True).data)


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_customer_history_api(request):
    search_query = request.query_params.get("q", "").strip()
    queryset = search_staff_customer_history(request.user, query=search_query)
    return Response(LeadSerializer(queryset, many=True).data)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def recover_staff_lead_api(request, lead_id):
    serializer = StaffLeadRecoverySerializer(data=request.data or {})
    serializer.is_valid(raise_exception=True)

    try:
        lead = Lead.objects.select_related("assigned_to").get(id=lead_id)
    except Lead.DoesNotExist:
        return Response({"detail": "Lead not found."}, status=404)

    try:
        lead = recover_staff_customer_lead(
            request.user,
            lead,
            status=serializer.validated_data["status"],
            callback_window=serializer.validated_data.get("callback_window", ""),
            callback_date=serializer.validated_data.get("callback_date"),
            interested_detail=serializer.validated_data.get("interested_detail"),
        )
    except PermissionError as error:
        return Response({"detail": str(error)}, status=403)
    except ValueError as error:
        return Response({"detail": str(error)}, status=409)

    return Response(LeadSerializer(lead).data)


@api_view(["GET"])
@permission_classes([IsCallingStaff])
def staff_learning_api(request):
    return Response(build_staff_learning_payload(request.user))


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def complete_training_lesson_api(request, lesson_id):
    try:
        lesson = TrainingLesson.objects.get(id=lesson_id, is_active=True)
    except TrainingLesson.DoesNotExist:
        return Response({"detail": "Training lesson not found."}, status=404)

    complete_training_lesson(request.user, lesson)
    return Response(build_staff_learning_payload(request.user))


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def start_session_api(request):
    try:
        session, created = start_staff_session(request.user)
    except TrainingRequiredError as error:
        return Response(
            {
                "detail": "Complete mandatory training before starting work.",
                "code": "training_required",
                **error.payload,
            },
            status=409,
        )
    return Response(
        {
            "created": created,
            "session": SessionSerializer(session).data,
            "summary": build_staff_today_payload(request.user)["summary"],
            "notifications": build_staff_active_notifications_payload(request.user),
        }
    )


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def end_session_api(request):
    session = end_staff_session(request.user)
    if not session:
        return Response({"detail": "No active session found."}, status=404)
    return Response(
        {
            "session": SessionSerializer(session).data,
            "summary": build_staff_today_payload(request.user)["summary"],
            "notifications": build_staff_active_notifications_payload(request.user),
        }
    )


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def heartbeat_api(request):
    serializer = HeartbeatSerializer(data=request.data or {})
    serializer.is_valid(raise_exception=True)
    session = record_session_heartbeat(
        request.user,
        serializer.validated_data["state"],
        interaction=serializer.validated_data["interaction"],
        source=serializer.validated_data["source"],
    )
    if not session:
        return Response(
            {
                "detail": "No active session found.",
                "summary": build_staff_today_payload(request.user)["summary"],
                "notifications": build_staff_active_notifications_payload(request.user),
            },
            status=409,
        )
    return Response(
        {
            "session": SessionSerializer(session).data,
            "summary": build_staff_today_payload(request.user)["summary"],
            "notifications": build_staff_active_notifications_payload(request.user),
        }
    )


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def start_call_api(request):
    serializer = StartCallSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    pending_status_call = get_pending_status_call(request.user)
    if pending_status_call:
        return Response(
            {
                "detail": "Mark the previous call status before starting another call.",
                "code": "call_status_required",
                "call": CallSerializer(pending_status_call).data,
                "summary": build_staff_today_payload(request.user)["summary"],
            },
            status=409,
        )
    recoverable_call = get_recoverable_open_call(request.user)
    if recoverable_call:
        return Response(
            {
                "detail": "Finish syncing the recent customer call before starting another one.",
                "code": "call_recovery_required",
                "call": CallSerializer(recoverable_call).data,
                "summary": build_staff_today_payload(request.user)["summary"],
            },
            status=409,
        )
    try:
        lead = Lead.objects.get(id=serializer.validated_data["lead_id"], assigned_to=request.user)
    except Lead.DoesNotExist:
        return Response({"detail": "Lead not found."}, status=404)

    if (
        not serializer.validated_data.get("from_followup_menu", False)
        and not is_staff_lead_visible_now(lead)
    ):
        return Response(
            {
                "detail": "This scheduled follow up is only available on its requested date and time.",
                "code": "followup_not_due",
            },
            status=409,
        )

    if not serializer.validated_data.get("from_followup_menu", False) and lead.status == Lead.Status.NEW:
        sla_gate_status = build_staff_followup_sla_gate_status(request.user)
        if not sla_gate_status["normal_lead_calls_allowed"]:
            return Response(
                {
                    "detail": sla_gate_status["block_message"]
                    or "Complete at least one crossed-SLA follow-up call before calling a New lead.",
                    "code": "followup_sla_call_required",
                    "sla_gate_status": sla_gate_status,
                    "summary": build_staff_today_payload(request.user)["summary"],
                },
                status=409,
            )

    try:
        call = start_staff_call(request.user, lead)
    except TrainingRequiredError as error:
        return Response(
            {
                "detail": str(error),
                "code": "training_required",
                "learning": error.payload,
                "summary": build_staff_today_payload(request.user)["summary"],
            },
            status=409,
        )
    return Response(CallSerializer(call).data, status=201)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def end_call_api(request, call_id):
    serializer = EndCallSerializer(data=request.data or {})
    serializer.is_valid(raise_exception=True)
    try:
        call = request.user.calls.select_related("lead", "staff").get(id=call_id)
    except request.user.calls.model.DoesNotExist:
        return Response({"detail": "Call not found."}, status=404)

    try:
        call = end_staff_call(
            call,
            serializer.validated_data.get("status"),
            duration_seconds=serializer.validated_data.get("duration_seconds"),
            ended_at=serializer.validated_data.get("ended_at"),
            source=serializer.validated_data.get("source", "app"),
            callback_window=serializer.validated_data.get("callback_window", ""),
            callback_date=serializer.validated_data.get("callback_date"),
        )
    except ValueError as error:
        return Response({"detail": str(error)}, status=400)
    return Response(CallSerializer(call).data)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def retry_call_api(request, call_id):
    try:
        call = request.user.calls.select_related("lead", "staff").get(id=call_id)
    except request.user.calls.model.DoesNotExist:
        return Response({"detail": "Call not found."}, status=404)

    if call.end_time is None or call.status != Call.Status.STARTED:
        return Response(
            {
                "detail": "Only a pending call result can be retried.",
                "code": "retry_not_allowed",
            },
            status=409,
        )

    latest_pending = get_pending_status_call(request.user)
    if not latest_pending or latest_pending.id != call.id:
        return Response(
            {
                "detail": "Retry the latest pending call before moving forward.",
                "code": "retry_not_allowed",
            },
            status=409,
        )

    call = retry_pending_staff_call(call)
    return Response(CallSerializer(call).data)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def update_call_status_api(request, call_id):
    serializer = CallStatusSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    try:
        call = request.user.calls.select_related("lead", "staff").get(id=call_id)
    except request.user.calls.model.DoesNotExist:
        return Response({"detail": "Call not found."}, status=404)

    try:
        call = update_staff_call_status(
            call,
            serializer.validated_data["status"],
            serializer.validated_data.get("callback_window", ""),
            serializer.validated_data.get("callback_date"),
        )
    except ValueError as error:
        return Response({"detail": str(error)}, status=400)
    return Response(CallSerializer(call).data)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def interested_lead_capture_api(request, call_id):
    serializer = InterestedLeadCaptureSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    try:
        call = request.user.calls.select_related("lead", "staff").get(id=call_id)
    except request.user.calls.model.DoesNotExist:
        return Response({"detail": "Call not found."}, status=404)

    try:
        detail = save_interested_lead_detail(call, **serializer.validated_data)
    except ValueError as error:
        return Response({"detail": str(error)}, status=400)

    return Response(
        InterestedLeadDetailSerializer(detail).data,
        status=201,
    )














    delete_recovery_leads_by_ids,
    delete_recovery_leads_filtered,
