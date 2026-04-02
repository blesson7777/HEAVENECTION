import csv
import io
import logging
import re
from collections import Counter, defaultdict
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.db.models import Case, Count, IntegerField, Max, Q, Sum, Value, When
from django.template.loader import render_to_string
from django.db.models.functions import Coalesce, TruncDate
from django.urls import reverse
from django.utils import timezone

from backend.apps.telecalling.models import (
    AppRelease,
    Call,
    CompanyProfile,
    Lead,
    Salary,
    Session,
    Staff,
    StaffAction,
    TrainingCompletion,
    TrainingLesson,
)

try:
    from openpyxl import load_workbook
except ImportError:  # pragma: no cover - dependency installed in runtime
    load_workbook = None


ONLINE_WINDOW_SECONDS = 90
SHORT_CALL_SECONDS = 5
BACKGROUND_TIMEOUT_SECONDS = 5 * 60
IDLE_WARNING_AFTER_SECONDS = 5 * 60
IDLE_WARNING_GRACE_SECONDS = 5 * 60
IDLE_OFFLINE_AFTER_SECONDS = IDLE_WARNING_AFTER_SECONDS + IDLE_WARNING_GRACE_SECONDS
LIVE_CALL_STALE_SECONDS = 3 * 60 * 60
VERIFIED_CALL_ACTIVITY_TIMEOUT_SECONDS = 5 * 60
VERIFIED_CALL_TIME_SKEW_SECONDS = 2 * 60
VERIFIED_CALL_SOURCES = {
    "call_log",
    "call_log_short_resolution",
    "call_log_short_recall",
}
QUALITY_SCORE_LOOKBACK_DAYS = 30
MISSED_CALLBACK_AFTER_HOURS = 24
TWOPLACES = Decimal("0.01")
DEFAULT_LEAD_QUEUE_LIMIT = 1
CALLBACK_NOON_HOURS = range(12, 16)
logger = logging.getLogger(__name__)
CALLBACK_EVENING_HOURS = range(16, 20)
CALLBACK_NIGHT_HOURS = range(20, 24)
ACTIVE_QUEUE_STATUSES = (
    Lead.Status.NEW,
    Lead.Status.CALL_BACK,
    Lead.Status.INTERESTED,
)
FOLLOW_UP_STATUSES = (
    Lead.Status.INTERESTED,
    Lead.Status.CALL_BACK,
)
RECOVERY_LEAD_STATUSES = (
    Lead.Status.NOT_INTERESTED,
    Lead.Status.NO_ANSWER,
)
TERMINAL_QUEUE_STATUSES = (
    Lead.Status.NOT_INTERESTED,
    Lead.Status.NO_ANSWER,
    Lead.Status.CONVERTED,
)
NAME_COLUMN_ALIASES = {
    "name",
    "leadname",
    "lead name",
    "customername",
    "customer name",
    "customer",
    "fullname",
    "full name",
    "clientname",
    "client name",
    "client",
}
PHONE_COLUMN_ALIASES = {
    "phone",
    "phone no",
    "phone no.",
    "phonenumber",
    "phone number",
    "mobile",
    "mobile no",
    "mobile no.",
    "mobilenumber",
    "mobile number",
    "contact",
    "contact no",
    "contact no.",
    "contactnumber",
    "contact number",
    "number",
    "whatsapp",
    "whatsapp number",
}
LEAD_ID_COLUMN_ALIASES = {
    "id",
    "lead id",
    "leadid",
}
STATUS_COLUMN_ALIASES = {
    "status",
    "lead status",
    "call status",
    "result",
    "followup status",
    "follow up status",
}
CALLBACK_WINDOW_COLUMN_ALIASES = {
    "callback window",
    "callback slot",
    "call back slot",
    "time slot",
    "schedule",
    "callback time",
}
NOTES_COLUMN_ALIASES = {
    "notes",
    "remarks",
    "comment",
    "comments",
}
ASSIGNED_STAFF_PHONE_COLUMN_ALIASES = {
    "assigned to phone",
    "assigned staff phone",
    "staff phone",
    "assignee phone",
}
ASSIGNED_STAFF_NAME_COLUMN_ALIASES = {
    "assigned to",
    "assigned staff",
    "staff",
    "staff name",
    "assignee",
}


class TrainingRequiredError(Exception):
    def __init__(self, payload):
        super().__init__("Complete mandatory training before starting work.")
        self.payload = payload


def get_company_profile():
    profile, _ = CompanyProfile.objects.get_or_create(
        id=1,
        defaults={
            "company_name": "Heavenection",
            "country": "India",
        },
    )
    return profile


def get_lead_queue_limit():
    profile = get_company_profile()
    return max(1, int(profile.lead_queue_target_per_staff or DEFAULT_LEAD_QUEUE_LIMIT))


def _today_range():
    today = timezone.localdate()
    start = timezone.make_aware(timezone.datetime.combine(today, timezone.datetime.min.time()))
    end = timezone.make_aware(timezone.datetime.combine(today, timezone.datetime.max.time()))
    return today, start, end


def _format_currency(value):
    rounded = round(float(value or 0), 2)
    return f"Rs. {rounded:,.2f}"


def _format_hours(total_seconds):
    return f"{round((total_seconds or 0) / 3600, 1)}h"


def _format_duration(total_seconds):
    total_seconds = int(total_seconds or 0)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def _format_datetime(value, fallback="--"):
    if not value:
        return fallback
    return timezone.localtime(value).strftime("%d %b %Y, %I:%M %p")


def _week_range(now=None):
    now = now or timezone.now()
    local_now = timezone.localtime(now)
    start_date = local_now.date() - timedelta(days=local_now.weekday())
    start = timezone.make_aware(timezone.datetime.combine(start_date, timezone.datetime.min.time()))
    return start, now


def _month_range(now=None):
    now = now or timezone.now()
    local_now = timezone.localtime(now)
    start_date = local_now.date().replace(day=1)
    start = timezone.make_aware(timezone.datetime.combine(start_date, timezone.datetime.min.time()))
    return start, now


def _decimal_hours(total_seconds):
    return Decimal(str(total_seconds or 0)) / Decimal("3600")


def _decimal_minutes(total_seconds):
    return Decimal(str(total_seconds or 0)) / Decimal("60")


def _money(value):
    return Decimal(value or 0).quantize(TWOPLACES)


def _staff_period_totals(start, end):
    session_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Session.objects.filter(login_time__range=(start, end))
        .values("staff_id")
        .annotate(total=Sum("active_seconds"))
    }
    call_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Call.objects.filter(start_time__range=(start, end), is_qualifying=True)
        .values("staff_id")
        .annotate(total=Sum("duration_seconds"))
    }
    converted_counts = Counter(
        Call.objects.filter(start_time__range=(start, end), status=Call.Status.CONVERTED, is_qualifying=True)
        .values_list("staff_id", flat=True)
    )
    return session_totals, call_totals, converted_counts


def _calculate_base_pay(staff, active_hours):
    active_hours = Decimal(active_hours or 0)
    return _money(active_hours * staff.hourly_rate)


def calculate_staff_payout(staff, *, active_seconds=0, call_seconds=0, converted_leads=0):
    active_hours = _decimal_hours(active_seconds)
    call_minutes = _decimal_minutes(call_seconds)
    call_earnings = _money(call_minutes * staff.call_rate)
    bonus_earnings = _money(Decimal(str(converted_leads or 0)) * staff.bonus_per_conversion)
    base_pay = _calculate_base_pay(staff, active_hours)
    total_pay = _money(base_pay + call_earnings + bonus_earnings)
    return {
        "active_hours": active_hours,
        "call_minutes": call_minutes,
        "converted_leads": int(converted_leads or 0),
        "base_pay": base_pay,
        "call_earnings": call_earnings,
        "bonus_earnings": bonus_earnings,
        "total_pay": total_pay,
    }


def _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown):
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return weekly_breakdown["total_pay"], "Weekly Payout"
    if staff.compensation_type == Staff.CompensationType.MONTHLY:
        return monthly_breakdown["total_pay"], "Monthly Payout"
    return monthly_breakdown["total_pay"], "Hourly Running Total"


def _quantized_decimal(value):
    return Decimal(value or 0).quantize(TWOPLACES)


def _date_range_bounds(period_start, period_end):
    start_at = timezone.make_aware(timezone.datetime.combine(period_start, timezone.datetime.min.time()))
    end_at = timezone.make_aware(timezone.datetime.combine(period_end, timezone.datetime.max.time()))
    return start_at, end_at


def calculate_staff_payout_for_dates(staff, period_start, period_end):
    start_at, end_at = _date_range_bounds(period_start, period_end)
    active_seconds = (
        Session.objects.filter(staff=staff, login_time__range=(start_at, end_at)).aggregate(total=Sum("active_seconds")).get("total")
        or 0
    )
    call_seconds = (
        Call.objects.filter(staff=staff, start_time__range=(start_at, end_at), is_qualifying=True)
        .aggregate(total=Sum("duration_seconds"))
        .get("total")
        or 0
    )
    converted_leads = Call.objects.filter(
        staff=staff,
        start_time__range=(start_at, end_at),
        status=Call.Status.CONVERTED,
        is_qualifying=True,
    ).count()
    breakdown = calculate_staff_payout(
        staff,
        active_seconds=active_seconds,
        call_seconds=call_seconds,
        converted_leads=converted_leads,
    )
    breakdown["period_start"] = period_start
    breakdown["period_end"] = period_end
    return breakdown


def _salary_history_row(record):
    return {
        "id": str(record.id),
        "period_start": record.period_start,
        "period_end": record.period_end,
        "period_label": f"{record.period_start.strftime('%d %b %Y')} to {record.period_end.strftime('%d %b %Y')}",
        "payout_cycle": record.payout_cycle,
        "payout_cycle_label": record.get_payout_cycle_display(),
        "total_hours": float(record.total_hours or 0),
        "total_hours_label": f"{round(float(record.total_hours or 0), 1)}h",
        "final_salary": _format_currency(record.final_salary),
        "paid_amount": _format_currency(record.paid_amount),
        "is_paid": record.is_paid,
        "paid_at": _format_datetime(record.paid_at),
        "payment_method": record.payment_method,
        "payment_method_label": record.get_payment_method_display() if record.payment_method else "Manual",
        "payment_reference": record.payment_reference or "--",
        "payment_note": record.payment_note or "--",
    }


def build_staff_salary_history_rows(staff, limit=20):
    records = Salary.objects.filter(staff=staff, is_paid=True).order_by("-paid_at", "-period_end")[:limit]
    return [_salary_history_row(record) for record in records]


def _payroll_email_is_ready():
    if not settings.PAYROLL_NOTIFY_EMAILS:
        return False, "Payroll email notifications are disabled."
    if not settings.EMAIL_HOST:
        return False, "SMTP is not configured yet."
    if settings.EMAIL_BACKEND == "django.core.mail.backends.console.EmailBackend":
        return False, "SMTP email backend is not configured yet."
    return True, ""


def send_salary_payment_acknowledgement(salary_record):
    staff = salary_record.staff
    if not staff.email:
        return {"sent": False, "message": f"{staff.name} does not have an email address saved."}

    email_ready, reason = _payroll_email_is_ready()
    if not email_ready:
        return {"sent": False, "message": reason}

    company_profile = get_company_profile()
    period_label = f"{salary_record.period_start.strftime('%d %b %Y')} to {salary_record.period_end.strftime('%d %b %Y')}"
    paid_at = timezone.localtime(salary_record.paid_at) if salary_record.paid_at else timezone.localtime(timezone.now())
    context = {
        "company_name": company_profile.company_name or "Heavenection",
        "company_support_email": company_profile.company_email or settings.DEFAULT_FROM_EMAIL,
        "company_phone": company_profile.company_phone or company_profile.support_phone or "",
        "staff_name": staff.name,
        "paid_amount": _format_currency(salary_record.paid_amount),
        "final_salary": _format_currency(salary_record.final_salary),
        "base_pay": _format_currency(salary_record.base_pay),
        "call_earnings": _format_currency(salary_record.call_earnings),
        "bonus_earnings": _format_currency(salary_record.bonus_earnings),
        "payment_method": salary_record.get_payment_method_display() if salary_record.payment_method else "Recorded Payment",
        "payment_reference": salary_record.payment_reference or "--",
        "payment_note": salary_record.payment_note or "",
        "payout_cycle": salary_record.get_payout_cycle_display(),
        "period_label": period_label,
        "paid_at": paid_at.strftime("%d %b %Y, %I:%M %p"),
        "total_hours": f"{round(float(salary_record.total_hours or 0), 2)}",
    }
    subject = f"{context['company_name']} Salary Credited - {context['period_label']}"
    from_email = settings.DEFAULT_FROM_EMAIL
    if company_profile.company_name and settings.DEFAULT_FROM_EMAIL:
        from_email = f"{company_profile.company_name} <{settings.DEFAULT_FROM_EMAIL}>"

    text_body = render_to_string("emails/salary_paid_notification.txt", context).strip()
    html_body = render_to_string("emails/salary_paid_notification.html", context)
    reply_to = [company_profile.company_email] if company_profile.company_email else None

    try:
        message = EmailMultiAlternatives(
            subject=subject,
            body=text_body,
            from_email=from_email,
            to=[staff.email],
            reply_to=reply_to,
        )
        message.attach_alternative(html_body, "text/html")
        message.send(fail_silently=False)
    except Exception as error:  # pragma: no cover - depends on SMTP runtime
        logger.exception("Salary payment acknowledgement email failed for staff %s", staff.id)
        return {
            "sent": False,
            "message": f"Salary was marked paid, but the email could not be sent: {error}",
        }

    return {
        "sent": True,
        "message": f"Salary acknowledgement email sent to {staff.email}.",
    }


def record_staff_salary_payment(
    staff,
    *,
    payout_cycle,
    period_start,
    period_end,
    paid_amount,
    payment_method="",
    payment_reference="",
    payment_note="",
):
    breakdown = calculate_staff_payout_for_dates(staff, period_start, period_end)
    recommended_amount = _money(breakdown["total_pay"])
    paid_amount_value = _money(paid_amount if paid_amount is not None else recommended_amount)
    salary_record, created = Salary.objects.update_or_create(
        staff=staff,
        period_start=period_start,
        period_end=period_end,
        defaults={
            "payout_cycle": payout_cycle,
            "total_hours": _quantized_decimal(breakdown["active_hours"]),
            "total_call_minutes": _quantized_decimal(breakdown["call_minutes"]),
            "converted_leads": int(breakdown["converted_leads"]),
            "base_pay": _money(breakdown["base_pay"]),
            "call_earnings": _money(breakdown["call_earnings"]),
            "bonus_earnings": _money(breakdown["bonus_earnings"]),
            "incentives": _money(breakdown["call_earnings"] + breakdown["bonus_earnings"]),
            "final_salary": recommended_amount,
            "paid_amount": paid_amount_value,
            "is_paid": True,
            "paid_at": timezone.now(),
            "payment_method": payment_method,
            "payment_reference": payment_reference.strip(),
            "payment_note": payment_note.strip(),
        },
    )
    return salary_record, created


def _salary_setting_target_label(staff):
    hourly_label = f"Rs. {float(staff.hourly_rate):,.2f} / hour"
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return f"{hourly_label} | Paid Weekly"
    if staff.compensation_type == Staff.CompensationType.MONTHLY:
        return f"{hourly_label} | Paid Monthly"
    return f"{hourly_label} | Running Hourly"


def _payout_cycle_label(staff):
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return "Weekly"
    if staff.compensation_type == Staff.CompensationType.MONTHLY:
        return "Monthly"
    return "Hourly"


def _bounded_elapsed_seconds(previous, current, max_seconds=ONLINE_WINDOW_SECONDS):
    if not previous or not current:
        return 0
    return max(0, min(int((current - previous).total_seconds()), max_seconds))


def _dedupe_fields(field_names):
    return list(dict.fromkeys(field_names + ["updated_at"]))


def _log_staff_action(
    staff,
    action_type,
    *,
    session=None,
    call=None,
    lead=None,
    app_state=None,
    metadata=None,
):
    return StaffAction.objects.create(
        staff=staff,
        session=session,
        call=call,
        lead=lead,
        action_type=action_type,
        app_state=app_state,
        metadata=metadata or {},
    )


def _session_has_recent_verified_activity(session, now):
    if not session or not session.last_verified_call_at:
        return False
    return (now - session.last_verified_call_at).total_seconds() < VERIFIED_CALL_ACTIVITY_TIMEOUT_SECONDS


def _active_elapsed_until(session, now, *, has_live_customer_call=False):
    if session.last_known_state != Session.AppState.FOREGROUND:
        return 0

    if not has_live_customer_call and not _session_has_recent_verified_activity(session, now):
        return 0

    active_until = now
    if not has_live_customer_call and session.last_verified_call_at:
        verified_cutoff = session.last_verified_call_at + timedelta(
            seconds=VERIFIED_CALL_ACTIVITY_TIMEOUT_SECONDS
        )
        if verified_cutoff < active_until:
            active_until = verified_cutoff

    return _bounded_elapsed_seconds(session.last_heartbeat_at, active_until)


def _mark_session_foreground(session, now, *, metadata=None):
    previous_state = session.last_known_state
    session.last_interaction_at = now
    session.last_heartbeat_at = now

    update_fields = ["last_interaction_at", "last_heartbeat_at"]
    if previous_state != Session.AppState.FOREGROUND:
        session.last_known_state = Session.AppState.FOREGROUND
        session.state_changed_at = now
        session.warning_started_at = None
        update_fields.extend(["last_known_state", "state_changed_at", "warning_started_at"])

    session.save(update_fields=_dedupe_fields(update_fields))

    if previous_state == Session.AppState.WARNING:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.IDLE_WARNING_ACKNOWLEDGED,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )
    elif previous_state == Session.AppState.OFFLINE:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.RETURNED_ONLINE,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )
    elif previous_state == Session.AppState.BACKGROUND:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.APP_FOREGROUNDED,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )

    mark_staff_seen(session.staff, now)
    return session


def _credit_call_duration_to_session(
    session,
    call_end_time,
    call_duration_seconds,
    *,
    metadata=None,
    mark_verified=False,
):
    if not session or not session.is_open:
        return session

    session = _mark_session_foreground(session, call_end_time, metadata=metadata)
    update_fields = []
    if call_duration_seconds:
        session.active_seconds += max(0, int(call_duration_seconds))
        update_fields.append("active_seconds")
    if mark_verified and session.last_verified_call_at != call_end_time:
        session.last_verified_call_at = call_end_time
        update_fields.append("last_verified_call_at")
    if update_fields:
        session.save(update_fields=_dedupe_fields(update_fields))
    return session


def _resolve_requested_state(session, requested_state, now, interaction, *, has_live_customer_call=False):
    if requested_state == Session.AppState.BACKGROUND:
        return Session.AppState.BACKGROUND
    if requested_state == Session.AppState.WARNING:
        return Session.AppState.WARNING
    if requested_state == Session.AppState.OFFLINE:
        return Session.AppState.OFFLINE

    if has_live_customer_call:
        return Session.AppState.FOREGROUND
    if not _session_has_recent_verified_activity(session, now):
        return Session.AppState.OFFLINE

    last_interaction_at = now if interaction else (session.last_interaction_at or now)
    idle_seconds = max(0, int((now - last_interaction_at).total_seconds()))

    if session.last_known_state in {Session.AppState.WARNING, Session.AppState.OFFLINE} and not interaction:
        return session.last_known_state
    if idle_seconds >= IDLE_OFFLINE_AFTER_SECONDS:
        return Session.AppState.OFFLINE
    if idle_seconds >= IDLE_WARNING_AFTER_SECONDS:
        return Session.AppState.WARNING
    return Session.AppState.FOREGROUND


def _close_session(session, now, *, close_reason, auto_generated=False):
    if not session or not session.is_open:
        return session

    session.active_seconds += _active_elapsed_until(session, now)
    session.logout_time = now
    session.is_open = False
    session.last_heartbeat_at = now
    session.close_reason = close_reason
    session.save(
        update_fields=_dedupe_fields(
            [
                "active_seconds",
                "logout_time",
                "is_open",
                "last_heartbeat_at",
                "close_reason",
            ]
        )
    )
    mark_staff_seen(session.staff, now)
    _log_staff_action(
        session.staff,
        StaffAction.ActionType.SESSION_AUTO_ENDED if auto_generated else StaffAction.ActionType.SESSION_ENDED,
        session=session,
        app_state=session.last_known_state,
        metadata={"close_reason": close_reason},
    )
    return session


def reconcile_session(session, now=None):
    if not session or not session.is_open:
        return session

    now = now or timezone.now()
    state_anchor = session.state_changed_at or session.last_heartbeat_at or session.login_time
    warning_anchor = session.warning_started_at or state_anchor
    has_live_customer_call = session.staff_id in _reconcile_open_calls(staff=session.staff, now=now)

    if (
        session.last_known_state == Session.AppState.FOREGROUND
        and not has_live_customer_call
        and not _session_has_recent_verified_activity(session, now)
    ):
        session.last_known_state = Session.AppState.OFFLINE
        session.state_changed_at = now
        session.warning_started_at = None
        session.save(
            update_fields=_dedupe_fields(
                ["last_known_state", "state_changed_at", "warning_started_at"]
            )
        )
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.MARKED_OFFLINE,
            session=session,
            app_state=Session.AppState.OFFLINE,
            metadata={"reason": "verified_call_timeout"},
        )
        return session

    if (
        session.last_known_state == Session.AppState.BACKGROUND
        and state_anchor
        and (now - state_anchor).total_seconds() >= BACKGROUND_TIMEOUT_SECONDS
    ):
        session.last_known_state = Session.AppState.OFFLINE
        session.state_changed_at = now
        session.warning_started_at = None
        session.save(
            update_fields=_dedupe_fields(
                ["last_known_state", "state_changed_at", "warning_started_at"]
            )
        )
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.MARKED_OFFLINE,
            session=session,
            app_state=Session.AppState.OFFLINE,
            metadata={"reason": "background_timeout"},
        )
        return session

    if (
        session.last_known_state == Session.AppState.WARNING
        and warning_anchor
        and (now - warning_anchor).total_seconds() >= IDLE_WARNING_GRACE_SECONDS
    ):
        session.last_known_state = Session.AppState.OFFLINE
        session.state_changed_at = now
        session.save(update_fields=_dedupe_fields(["last_known_state", "state_changed_at"]))
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.MARKED_OFFLINE,
            session=session,
            app_state=Session.AppState.OFFLINE,
            metadata={"reason": "warning_timeout"},
        )

    return session


def authenticate_staff(identifier, password, required_role=None):
    identifier = identifier.strip()
    queryset = Staff.objects.filter(is_active=True).filter(
        Q(phone=identifier) | Q(email__iexact=identifier)
    )
    if required_role:
        queryset = queryset.filter(role=required_role)

    staff = queryset.first()
    if not staff or not staff.check_password(password):
        return None
    return staff


def mark_staff_seen(staff, seen_at=None):
    staff.last_seen_at = seen_at or timezone.now()
    staff.save(update_fields=["last_seen_at", "updated_at"])


def get_open_session(staff, reconcile=False):
    session = Session.objects.filter(staff=staff, is_open=True).order_by("-login_time").first()
    if reconcile and session:
        session = reconcile_session(session)
        if session and not session.is_open:
            return None
    return session


def _touch_session_interaction(session, now, *, metadata=None):
    if not session or not session.is_open:
        return session

    has_live_customer_call = session.staff_id in _reconcile_open_calls(staff=session.staff, now=now)
    session.active_seconds += _active_elapsed_until(
        session,
        now,
        has_live_customer_call=has_live_customer_call,
    )
    session.save(update_fields=_dedupe_fields(["active_seconds"]))
    return _mark_session_foreground(session, now, metadata=metadata)


def _session_status_label(open_session, latest_session=None):
    if open_session:
        if open_session.last_known_state == Session.AppState.OFFLINE and not open_session.last_verified_call_at:
            return "Call a customer to begin time tracking"
        return {
            Session.AppState.FOREGROUND: "Working",
            Session.AppState.BACKGROUND: "Away from app",
            Session.AppState.WARNING: "Warning shown",
            Session.AppState.OFFLINE: "Offline",
        }.get(open_session.last_known_state, "Working")

    if latest_session and latest_session.close_reason == "background_timeout":
        return "Stopped after background timeout"
    return "Stopped"


def _staff_online_label(session, active_cutoff, *, is_in_customer_call=False):
    if not session:
        return "On Call" if is_in_customer_call else "Offline"
    if is_in_customer_call:
        return "On Call"
    if session.last_known_state == Session.AppState.FOREGROUND and session.last_heartbeat_at and session.last_heartbeat_at >= active_cutoff:
        return "Online"
    if session.last_known_state == Session.AppState.WARNING:
        return "Warning"
    if session.last_known_state == Session.AppState.BACKGROUND:
        return "Away"
    return "Offline"


def _close_unresolved_call(call, *, reason):
    if not call or call.end_time is not None:
        return call

    session = get_open_session(call.staff, reconcile=True)
    call.end_time = call.start_time
    call.duration_seconds = 0
    call.is_qualifying = False
    call.is_verified = False
    call.status = Call.Status.INVALID_SHORT
    call.callback_window = ""
    call.verification_source = ""
    call.save(
        update_fields=[
            "end_time",
            "duration_seconds",
            "is_qualifying",
            "is_verified",
            "status",
            "callback_window",
            "verification_source",
            "updated_at",
        ]
    )

    call.lead.last_contacted_at = call.start_time
    call.lead.save(update_fields=["last_contacted_at", "updated_at"])

    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_ENDED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={
            "duration_seconds": 0,
            "is_qualifying": False,
            "status": call.status,
            "source": reason,
            "ended_at": call.end_time.isoformat(),
        },
    )
    return call


def _reconcile_open_calls(*, staff=None, now=None):
    now = now or timezone.now()
    queryset = Call.objects.filter(end_time__isnull=True).select_related("staff", "lead")
    if staff is not None:
        queryset = queryset.filter(staff=staff)

    open_calls = queryset.order_by("staff_id", "-start_time", "-created_at")
    live_staff_ids = set()
    seen_staff_ids = set()

    for call in open_calls:
        if call.staff_id in seen_staff_ids:
            _close_unresolved_call(call, reason="superseded_open_call")
            continue

        seen_staff_ids.add(call.staff_id)
        call_age_seconds = max(0, int((now - call.start_time).total_seconds()))
        if call_age_seconds >= LIVE_CALL_STALE_SECONDS:
            _close_unresolved_call(call, reason="stale_open_call")
            continue

        live_staff_ids.add(call.staff_id)

    return live_staff_ids


def _staff_queryset():
    return Staff.objects.filter(role=Staff.Role.STAFF).order_by("name")


def _normalize_phone(phone_value):
    return re.sub(r"\D+", "", str(phone_value or "")).strip()


def _normalize_column_name(value):
    text = re.sub(r"[^a-z0-9]+", " ", str(value or "").strip().lower())
    return " ".join(text.split())


def _lead_queue_queryset():
    return Lead.objects.filter(status__in=ACTIVE_QUEUE_STATUSES)


def _is_active_queue_status(status):
    return status in ACTIVE_QUEUE_STATUSES


def _follow_up_queryset():
    return Lead.objects.filter(status__in=FOLLOW_UP_STATUSES)


def _recovery_lead_queryset():
    return Lead.objects.filter(status__in=RECOVERY_LEAD_STATUSES)


def _normalize_status_value(value):
    normalized = _normalize_column_name(value)
    status_map = {
        "new": Lead.Status.NEW,
        "follow up": Lead.Status.INTERESTED,
        "followup": Lead.Status.INTERESTED,
        "interested": Lead.Status.INTERESTED,
        "rejected": Lead.Status.NOT_INTERESTED,
        "not interested": Lead.Status.NOT_INTERESTED,
        "no response": Lead.Status.NO_ANSWER,
        "no answer": Lead.Status.NO_ANSWER,
        "callback": Lead.Status.CALL_BACK,
        "call back": Lead.Status.CALL_BACK,
        "converted": Lead.Status.CONVERTED,
    }
    return status_map.get(normalized, "")


def _normalize_callback_window_value(value):
    normalized = _normalize_column_name(value)
    callback_map = {
        "": "",
        "noon": Lead.CallbackWindow.NOON,
        "afternoon": Lead.CallbackWindow.NOON,
        "evening": Lead.CallbackWindow.EVENING,
        "night": Lead.CallbackWindow.NIGHT,
    }
    return callback_map.get(normalized, "")


def _current_callback_window(now=None):
    local_now = timezone.localtime(now or timezone.now())
    hour = local_now.hour
    if hour in CALLBACK_NOON_HOURS:
        return Lead.CallbackWindow.NOON
    if hour in CALLBACK_EVENING_HOURS:
        return Lead.CallbackWindow.EVENING
    if hour in CALLBACK_NIGHT_HOURS:
        return Lead.CallbackWindow.NIGHT
    return ""


def _quality_tone(score):
    if score >= 85:
        return "success"
    if score >= 70:
        return "primary"
    if score >= 55:
        return "warning"
    return "muted"


def _quality_label(score, *, has_activity):
    if not has_activity:
        return "No Recent Activity"
    if score >= 85:
        return "Excellent"
    if score >= 70:
        return "Strong"
    if score >= 55:
        return "Needs Attention"
    return "Review Needed"


def _build_quality_note(*, followup_started_count, followup_closed_count, missed_callback_count):
    if followup_started_count and followup_closed_count:
        return f"{followup_closed_count} of {followup_started_count} follow-up leads completed."
    if followup_started_count:
        return f"{followup_started_count} follow-up leads still in progress."
    if missed_callback_count:
        return f"{missed_callback_count} callback lead(s) need review."
    return "Build more recent call activity for a fuller review."


def _build_staff_quality_metrics(staff_ids, *, now=None):
    if not staff_ids:
        return {}

    current_time = timezone.localtime(now or timezone.now())
    lookback_start = current_time - timedelta(days=QUALITY_SCORE_LOOKBACK_DAYS)
    missed_callback_cutoff = current_time - timedelta(hours=MISSED_CALLBACK_AFTER_HOURS)

    recent_calls = Call.objects.filter(
        staff_id__in=staff_ids,
        start_time__gte=lookback_start,
    ).values("staff_id", "lead_id", "status", "is_verified")

    callback_rows = Lead.objects.filter(
        assigned_to_id__in=staff_ids,
        status=Lead.Status.CALL_BACK,
    ).values("assigned_to_id", "last_contacted_at")

    metrics = {
        staff_id: {
            "total_completed_calls": 0,
            "invalid_short_calls": 0,
            "verified_resolved_calls": 0,
            "followup_started_leads": set(),
            "followup_closed_leads": set(),
            "callback_total": 0,
            "missed_callbacks": 0,
        }
        for staff_id in staff_ids
    }

    for row in recent_calls:
        staff_id = row["staff_id"]
        if staff_id not in metrics:
            continue
        status = row["status"]
        if status != Call.Status.STARTED:
            metrics[staff_id]["total_completed_calls"] += 1
        if status == Call.Status.INVALID_SHORT:
            metrics[staff_id]["invalid_short_calls"] += 1
        elif status != Call.Status.STARTED and row["is_verified"]:
            metrics[staff_id]["verified_resolved_calls"] += 1
        if status in {Call.Status.INTERESTED, Call.Status.CALL_BACK}:
            metrics[staff_id]["followup_started_leads"].add(str(row["lead_id"]))
        if status in {Call.Status.CONVERTED, Call.Status.NOT_INTERESTED}:
            metrics[staff_id]["followup_closed_leads"].add(str(row["lead_id"]))

    for row in callback_rows:
        staff_id = row["assigned_to_id"]
        if staff_id not in metrics:
            continue
        metrics[staff_id]["callback_total"] += 1
        last_contacted_at = row["last_contacted_at"]
        if not last_contacted_at or timezone.localtime(last_contacted_at) <= missed_callback_cutoff:
            metrics[staff_id]["missed_callbacks"] += 1

    quality_payload = {}
    for staff_id, staff_metrics in metrics.items():
        total_completed_calls = staff_metrics["total_completed_calls"]
        invalid_short_calls = staff_metrics["invalid_short_calls"]
        resolved_calls = max(total_completed_calls - invalid_short_calls, 0)
        verified_resolved_calls = min(staff_metrics["verified_resolved_calls"], resolved_calls)
        followup_started_count = len(staff_metrics["followup_started_leads"])
        followup_closed_count = len(
            staff_metrics["followup_started_leads"] & staff_metrics["followup_closed_leads"]
        )
        callback_total = staff_metrics["callback_total"]
        missed_callback_count = staff_metrics["missed_callbacks"]

        weighted_total = Decimal("0")
        total_weight = Decimal("0")

        outcome_score = None
        if total_completed_calls > 0:
            resolved_ratio = Decimal(resolved_calls) / Decimal(total_completed_calls)
            verified_ratio = (
                Decimal(verified_resolved_calls) / Decimal(resolved_calls)
                if resolved_calls
                else Decimal("0")
            )
            outcome_score = ((resolved_ratio * Decimal("0.6")) + (verified_ratio * Decimal("0.4"))) * Decimal("100")
            weighted_total += outcome_score * Decimal("0.45")
            total_weight += Decimal("0.45")

        followup_score = None
        if followup_started_count > 0:
            followup_score = (Decimal(followup_closed_count) / Decimal(followup_started_count)) * Decimal("100")
            weighted_total += followup_score * Decimal("0.35")
            total_weight += Decimal("0.35")

        callback_score = None
        if callback_total > 0:
            callback_score = max(
                Decimal("0"),
                (Decimal(callback_total - missed_callback_count) / Decimal(callback_total)) * Decimal("100"),
            )
            weighted_total += callback_score * Decimal("0.20")
            total_weight += Decimal("0.20")

        has_activity = total_completed_calls > 0 or followup_started_count > 0 or callback_total > 0
        overall_score = int((weighted_total / total_weight).quantize(Decimal("1"))) if total_weight > 0 else 0

        outcome_value = int(outcome_score.quantize(Decimal("1"))) if outcome_score is not None else None
        followup_value = int(followup_score.quantize(Decimal("1"))) if followup_score is not None else None
        callback_value = int(callback_score.quantize(Decimal("1"))) if callback_score is not None else None

        quality_payload[staff_id] = {
            "score": overall_score,
            "label": _quality_label(overall_score, has_activity=has_activity),
            "tone": _quality_tone(overall_score) if has_activity else "muted",
            "note": _build_quality_note(
                followup_started_count=followup_started_count,
                followup_closed_count=followup_closed_count,
                missed_callback_count=missed_callback_count,
            ),
            "has_activity": has_activity,
            "outcome_consistency": outcome_value,
            "outcome_consistency_label": f"{outcome_value}%" if outcome_value is not None else "--",
            "followup_completion": followup_value,
            "followup_completion_label": f"{followup_value}%" if followup_value is not None else "--",
            "callback_discipline": callback_value,
            "callback_discipline_label": f"{callback_value}%" if callback_value is not None else "--",
            "followup_started_count": followup_started_count,
            "followup_closed_count": followup_closed_count,
            "callback_total": callback_total,
            "missed_callbacks": missed_callback_count,
            "lookback_days": QUALITY_SCORE_LOOKBACK_DAYS,
        }

    return quality_payload


def _with_lead_priority(queryset, *, now=None, prioritized_lead_ids=None):
    current_slot = _current_callback_window(now)
    if current_slot:
        queue_priority = Case(
            When(status=Lead.Status.CALL_BACK, callback_window=current_slot, then=Value(0)),
            When(status=Lead.Status.INTERESTED, then=Value(1)),
            When(status=Lead.Status.CALL_BACK, then=Value(2)),
            When(status=Lead.Status.NEW, then=Value(3)),
            default=Value(4),
            output_field=IntegerField(),
        )
    else:
        queue_priority = Case(
            When(status=Lead.Status.INTERESTED, then=Value(0)),
            When(status=Lead.Status.CALL_BACK, then=Value(1)),
            When(status=Lead.Status.NEW, then=Value(2)),
            default=Value(3),
            output_field=IntegerField(),
        )
    ordered_queryset = queryset.annotate(queue_priority=queue_priority)
    if prioritized_lead_ids:
        ordered_queryset = ordered_queryset.annotate(
            manual_priority=Case(
                When(id__in=list(prioritized_lead_ids), then=Value(0)),
                default=Value(1),
                output_field=IntegerField(),
            )
        )
    return ordered_queryset


def _ordered_lead_queryset(queryset, *, now=None, include_assignee=False, prioritized_lead_ids=None):
    ordered_queryset = _with_lead_priority(
        queryset,
        now=now,
        prioritized_lead_ids=prioritized_lead_ids,
    ).annotate(lead_sequence_anchor=Coalesce("last_contacted_at", "created_at"))
    order_fields = []
    if include_assignee:
        order_fields.append("assigned_to_id")
    if prioritized_lead_ids:
        order_fields.append("manual_priority")
    order_fields.extend(["queue_priority", "lead_sequence_anchor", "created_at", "id"])
    return ordered_queryset.order_by(*order_fields)


def _visible_staff_lead_queryset(queryset, *, now=None):
    current_slot = _current_callback_window(now)
    if current_slot:
        return queryset.filter(
            Q(status__in=(Lead.Status.NEW, Lead.Status.INTERESTED))
            | Q(status=Lead.Status.CALL_BACK, callback_window=current_slot)
        )
    return queryset.exclude(status=Lead.Status.CALL_BACK)


def is_staff_lead_visible_now(lead, *, now=None):
    if lead.status != Lead.Status.CALL_BACK:
        return True
    return bool(lead.callback_window and lead.callback_window == _current_callback_window(now))


def _daily_completed_call_counts():
    _, start, end = _today_range()
    qualifying_statuses = [
        Call.Status.INTERESTED,
        Call.Status.NOT_INTERESTED,
        Call.Status.NO_ANSWER,
        Call.Status.CALL_BACK,
        Call.Status.CONVERTED,
    ]
    return {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end), status__in=qualifying_statuses)
        .values("staff_id")
        .annotate(count=Count("id"))
    }


def release_staff_queue(staff):
    if not staff:
        return 0
    released = Lead.objects.filter(
        assigned_to=staff,
        status__in=ACTIVE_QUEUE_STATUSES,
    ).update(assigned_to=None, updated_at=timezone.now())
    return released


def _normalize_active_queue_assignments(*, target_staff=None):
    now = timezone.now()
    queue_limit = get_lead_queue_limit()
    queue_queryset = _lead_queue_queryset().select_related("assigned_to").exclude(assigned_to=None)
    if target_staff is not None:
        queue_queryset = queue_queryset.filter(assigned_to=target_staff)

    release_ids = []
    kept_counts = defaultdict(int)
    for lead in _ordered_lead_queryset(queue_queryset, now=now, include_assignee=True):
        assigned_staff = lead.assigned_to
        if not assigned_staff or assigned_staff.role != Staff.Role.STAFF or not assigned_staff.is_active:
            release_ids.append(lead.id)
            continue

        kept_counts[assigned_staff.id] += 1
        if kept_counts[assigned_staff.id] > queue_limit:
            release_ids.append(lead.id)

    if not release_ids:
        return 0

    return Lead.objects.filter(id__in=release_ids).update(
        assigned_to=None,
        updated_at=timezone.now(),
    )


def auto_allocate_leads(*, target_staff=None, prioritized_lead_ids=None):
    now = timezone.now()
    queue_limit = get_lead_queue_limit()
    active_staff_ids = _currently_active_staff_ids(now=now)
    _release_due_callback_leads_from_inactive_staff(now=now, active_staff_ids=active_staff_ids)
    _normalize_active_queue_assignments(target_staff=target_staff)
    staff_queryset = _staff_queryset().filter(is_active=True)
    if target_staff is not None:
        staff_queryset = staff_queryset.filter(id=target_staff.id)

    staff_members = list(staff_queryset)
    if not staff_members:
        return {"assigned_count": 0, "remaining_unassigned_count": _lead_queue_queryset().filter(assigned_to=None).count()}

    active_counts = {
        row["assigned_to"]: row["count"]
        for row in _lead_queue_queryset()
        .exclude(assigned_to=None)
        .values("assigned_to")
        .annotate(count=Count("id"))
    }
    completed_today_counts = _daily_completed_call_counts()
    open_leads = list(
        _ordered_lead_queryset(
            _lead_queue_queryset().filter(assigned_to=None),
            now=now,
            prioritized_lead_ids=prioritized_lead_ids,
        ).values("id", "status", "callback_window")
    )
    if not open_leads:
        return {"assigned_count": 0, "remaining_unassigned_count": 0}

    staff_slots = [
        {
            "staff_id": staff.id,
            "name": staff.name.lower(),
            "active_count": active_counts.get(staff.id, 0),
            "completed_today": completed_today_counts.get(staff.id, 0),
            "is_online": staff.id in active_staff_ids,
        }
        for staff in staff_members
    ]

    assigned_by_staff = defaultdict(list)
    unassigned_lead_ids = []
    current_slot = _current_callback_window(now)
    for lead in open_leads:
        eligible_slots = staff_slots
        if (
            current_slot
            and lead["status"] == Lead.Status.CALL_BACK
            and lead["callback_window"] == current_slot
        ):
            online_slots = [slot for slot in staff_slots if slot["is_online"]]
            if online_slots:
                eligible_slots = online_slots

        eligible_slots.sort(
            key=lambda item: (
                item["active_count"],
                -item["completed_today"],
                item["name"],
            )
        )
        chosen_slot = next(
            (slot for slot in eligible_slots if slot["active_count"] < queue_limit),
            None,
        )
        if not chosen_slot:
            unassigned_lead_ids.append(lead["id"])
            continue
        assigned_by_staff[chosen_slot["staff_id"]].append(lead["id"])
        chosen_slot["active_count"] += 1

    assigned_count = 0
    assigned_at = timezone.now()
    for staff_id, lead_ids in assigned_by_staff.items():
        assigned_count += len(lead_ids)
        Lead.objects.filter(id__in=lead_ids).update(
            assigned_to_id=staff_id,
            updated_at=assigned_at,
        )

    return {
        "assigned_count": assigned_count,
        "remaining_unassigned_count": len(unassigned_lead_ids),
    }


def _decode_csv_bytes(file_bytes):
    for encoding in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return file_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue
    return file_bytes.decode("utf-8", errors="ignore")


def _read_lead_rows_from_upload(uploaded_file):
    file_name = str(getattr(uploaded_file, "name", "")).lower()
    uploaded_file.seek(0)

    if file_name.endswith(".csv"):
        content = _decode_csv_bytes(uploaded_file.read())
        return [row for row in csv.reader(io.StringIO(content)) if any(str(cell or "").strip() for cell in row)]

    if file_name.endswith(".xlsx") or file_name.endswith(".xlsm"):
        if load_workbook is None:
            raise ValueError("Excel import support is not available right now.")
        workbook = load_workbook(uploaded_file, read_only=True, data_only=True)
        worksheet = workbook.active
        rows = []
        for row in worksheet.iter_rows(values_only=True):
            normalized_row = ["" if cell is None else str(cell).strip() for cell in row]
            if any(normalized_row):
                rows.append(normalized_row)
        return rows

    raise ValueError("Upload a CSV or XLSX file.")


def _detect_lead_column_indexes(rows):
    if not rows:
        raise ValueError("The uploaded file is empty.")

    header = rows[0]
    normalized_header = [_normalize_column_name(cell) for cell in header]
    name_index = None
    phone_index = None

    for index, value in enumerate(normalized_header):
        if name_index is None and value in NAME_COLUMN_ALIASES:
            name_index = index
        if phone_index is None and value in PHONE_COLUMN_ALIASES:
            phone_index = index

    has_header_match = name_index is not None or phone_index is not None
    if not has_header_match:
        if len(header) < 2:
            raise ValueError("The file must contain name and phone columns.")
        return 0, 1, rows

    if name_index is None or phone_index is None:
        raise ValueError("The file must include both name and phone columns.")

    return name_index, phone_index, rows[1:]


def import_leads_from_upload(uploaded_file):
    rows = _read_lead_rows_from_upload(uploaded_file)
    name_index, phone_index, data_rows = _detect_lead_column_indexes(rows)

    existing_numbers = {
        _normalize_phone(phone)
        for phone in Lead.objects.values_list("phone", flat=True)
    }
    created_leads = []
    batch_numbers = set()
    skipped_rows = 0

    for row in data_rows:
        row_values = list(row)
        if max(name_index, phone_index) >= len(row_values):
            skipped_rows += 1
            continue

        name = str(row_values[name_index] or "").strip()
        phone = _normalize_phone(row_values[phone_index])
        if not name or len(phone) < 7:
            skipped_rows += 1
            continue
        if phone in existing_numbers or phone in batch_numbers:
            skipped_rows += 1
            continue

        batch_numbers.add(phone)
        created_leads.append(
            Lead(
                name=name[:150],
                phone=phone,
                status=Lead.Status.NEW,
            )
        )

    if created_leads:
        Lead.objects.bulk_create(created_leads)

    allocation = auto_allocate_leads()
    return {
        "created_count": len(created_leads),
        "skipped_count": skipped_rows,
        "assigned_count": allocation["assigned_count"],
        "remaining_unassigned_count": allocation["remaining_unassigned_count"],
        "queue_limit": get_lead_queue_limit(),
    }


def _detect_followup_update_column_indexes(rows):
    if not rows:
        raise ValueError("The uploaded file is empty.")

    header = [_normalize_column_name(cell) for cell in rows[0]]
    indexes = {
        "lead_id": None,
        "phone": None,
        "status": None,
        "callback_window": None,
        "notes": None,
        "assigned_staff_phone": None,
        "assigned_staff_name": None,
    }

    for index, value in enumerate(header):
        if indexes["lead_id"] is None and value in LEAD_ID_COLUMN_ALIASES:
            indexes["lead_id"] = index
        if indexes["phone"] is None and value in PHONE_COLUMN_ALIASES:
            indexes["phone"] = index
        if indexes["status"] is None and value in STATUS_COLUMN_ALIASES:
            indexes["status"] = index
        if indexes["callback_window"] is None and value in CALLBACK_WINDOW_COLUMN_ALIASES:
            indexes["callback_window"] = index
        if indexes["notes"] is None and value in NOTES_COLUMN_ALIASES:
            indexes["notes"] = index
        if indexes["assigned_staff_phone"] is None and value in ASSIGNED_STAFF_PHONE_COLUMN_ALIASES:
            indexes["assigned_staff_phone"] = index
        if indexes["assigned_staff_name"] is None and value in ASSIGNED_STAFF_NAME_COLUMN_ALIASES:
            indexes["assigned_staff_name"] = index

    if indexes["lead_id"] is None and indexes["phone"] is None:
        raise ValueError("The update file must include either lead id or phone number.")

    editable_columns = (
        indexes["status"],
        indexes["callback_window"],
        indexes["notes"],
        indexes["assigned_staff_phone"],
        indexes["assigned_staff_name"],
    )
    if all(index is None for index in editable_columns):
        raise ValueError(
            "Include at least one update column: status, callback window, notes, or assigned staff."
        )

    return indexes, rows[1:]


def _cell_value(row_values, index):
    if index is None or index >= len(row_values):
        return ""
    return str(row_values[index] or "").strip()


def update_followups_from_upload(uploaded_file):
    rows = _read_lead_rows_from_upload(uploaded_file)
    indexes, data_rows = _detect_followup_update_column_indexes(rows)

    staff_by_phone = {
        _normalize_phone(staff.phone): staff
        for staff in _staff_queryset().filter(is_active=True)
    }
    staff_by_name = {
        _normalize_column_name(staff.name): staff
        for staff in _staff_queryset().filter(is_active=True)
    }

    updated_count = 0
    skipped_count = 0
    missing_count = 0
    error_messages = []

    for row_number, row in enumerate(data_rows, start=2):
        row_values = list(row)
        lead_id = _cell_value(row_values, indexes["lead_id"])
        phone = _normalize_phone(_cell_value(row_values, indexes["phone"]))
        if not lead_id and not phone:
            skipped_count += 1
            continue

        lead = None
        if lead_id:
            lead = Lead.objects.filter(id=lead_id).first()
        if lead is None and phone:
            lead = Lead.objects.filter(phone=phone).order_by("-updated_at").first()

        if lead is None:
            missing_count += 1
            continue

        payload = {}
        status_value = _cell_value(row_values, indexes["status"])
        if status_value:
            normalized_status = _normalize_status_value(status_value)
            if not normalized_status:
                error_messages.append(f"Row {row_number}: unknown status '{status_value}'.")
                continue
            payload["status"] = normalized_status

        callback_value = _cell_value(row_values, indexes["callback_window"])
        if indexes["callback_window"] is not None:
            normalized_callback = _normalize_callback_window_value(callback_value)
            if callback_value and not normalized_callback:
                error_messages.append(
                    f"Row {row_number}: callback slot must be Noon, Evening, or Night."
                )
                continue
            payload["callback_window"] = normalized_callback

        if indexes["notes"] is not None:
            payload["notes"] = _cell_value(row_values, indexes["notes"])

        assigned_staff_phone = _normalize_phone(
            _cell_value(row_values, indexes["assigned_staff_phone"])
        )
        assigned_staff_name = _normalize_column_name(
            _cell_value(row_values, indexes["assigned_staff_name"])
        )
        if indexes["assigned_staff_phone"] is not None or indexes["assigned_staff_name"] is not None:
            if assigned_staff_phone:
                assigned_staff = staff_by_phone.get(assigned_staff_phone)
                if not assigned_staff:
                    error_messages.append(
                        f"Row {row_number}: no active staff found for phone '{assigned_staff_phone}'."
                    )
                    continue
                payload["assigned_to"] = assigned_staff.id
            elif assigned_staff_name:
                assigned_staff = staff_by_name.get(assigned_staff_name)
                if not assigned_staff:
                    error_messages.append(
                        f"Row {row_number}: no active staff found for '{assigned_staff_name}'."
                    )
                    continue
                payload["assigned_to"] = assigned_staff.id
            else:
                payload["assigned_to"] = None

        if not payload:
            skipped_count += 1
            continue

        from backend.apps.telecalling.serializers import UpdateLeadSerializer

        serializer = UpdateLeadSerializer(lead, data=payload, partial=True)
        if not serializer.is_valid():
            error_messages.append(
                f"Row {row_number}: {' '.join(str(value[0]) if isinstance(value, list) else str(value) for value in serializer.errors.values())}"
            )
            continue

        serializer.save()
        updated_count += 1

    auto_allocate_leads()
    return {
        "updated_count": updated_count,
        "skipped_count": skipped_count,
        "missing_count": missing_count,
        "error_messages": error_messages[:10],
    }


def _training_lessons_queryset():
    return TrainingLesson.objects.order_by("sort_order", "-published_at", "title")


def _active_training_lessons_queryset():
    return _training_lessons_queryset().filter(is_active=True)


def _completion_map_for_staff(staff):
    return {
        completion.lesson_id: completion
        for completion in TrainingCompletion.objects.filter(staff=staff).select_related("lesson")
    }


def get_pending_mandatory_lessons(staff):
    completed_lesson_ids = TrainingCompletion.objects.filter(staff=staff).values_list("lesson_id", flat=True)
    return _active_training_lessons_queryset().filter(is_mandatory=True).exclude(id__in=completed_lesson_ids)


def build_staff_learning_payload(staff):
    lessons = list(_active_training_lessons_queryset())
    completion_map = _completion_map_for_staff(staff)
    pending_mandatory_count = 0
    next_required_title = ""
    completed_count = 0
    lesson_rows = []

    for lesson in lessons:
        completion = completion_map.get(lesson.id)
        is_completed = completion is not None
        if is_completed:
            completed_count += 1
        if lesson.is_mandatory and not is_completed:
            pending_mandatory_count += 1
            if not next_required_title:
                next_required_title = lesson.title

        lesson_rows.append(
            {
                "id": str(lesson.id),
                "title": lesson.title,
                "description": lesson.description,
                "video_url": lesson.video_url,
                "search_keywords": lesson.search_keywords,
                "is_active": lesson.is_active,
                "is_mandatory": lesson.is_mandatory,
                "is_completed": is_completed,
                "completed_at": completion.completed_at.isoformat() if completion else None,
                "published_at": lesson.published_at.isoformat() if lesson.published_at else None,
                "published_at_label": _format_datetime(lesson.published_at),
            }
        )

    return {
        "summary": {
            "total_lessons": len(lesson_rows),
            "completed_count": completed_count,
            "pending_mandatory_count": pending_mandatory_count,
            "has_pending_mandatory": pending_mandatory_count > 0,
            "next_required_title": next_required_title,
        },
        "lessons": lesson_rows,
    }


def build_learning_management_payload():
    today = timezone.localdate()
    active_staff_count = _staff_queryset().filter(is_active=True).count()
    completion_counts = {
        row["lesson_id"]: row["count"]
        for row in TrainingCompletion.objects.values("lesson_id").annotate(count=Count("id"))
    }
    lesson_rows = []
    active_count = 0
    mandatory_count = 0
    total_completions = TrainingCompletion.objects.count()

    for lesson in _training_lessons_queryset():
        completed_staff_count = completion_counts.get(lesson.id, 0)
        pending_staff_count = max(active_staff_count - completed_staff_count, 0)
        if lesson.is_active:
            active_count += 1
        if lesson.is_active and lesson.is_mandatory:
            mandatory_count += 1

        if not lesson.is_active:
            status_filter = "inactive"
            status_label = "Inactive"
        elif lesson.is_mandatory:
            status_filter = "mandatory"
            status_label = "Required"
        else:
            status_filter = "optional"
            status_label = "Optional"

        lesson_rows.append(
            {
                "id": str(lesson.id),
                "title": lesson.title,
                "description": lesson.description,
                "video_url": lesson.video_url,
                "search_keywords": lesson.search_keywords,
                "is_active": lesson.is_active,
                "is_mandatory": lesson.is_mandatory,
                "sort_order": lesson.sort_order,
                "published_at": lesson.published_at,
                "published_at_label": _format_datetime(lesson.published_at),
                "completed_staff_count": completed_staff_count,
                "pending_staff_count": pending_staff_count,
                "status_filter": status_filter,
                "status_label": status_label,
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "summary": {
            "active_count": active_count,
            "mandatory_count": mandatory_count,
            "active_staff_count": active_staff_count,
            "total_completions": total_completions,
        },
        "lesson_rows": lesson_rows,
    }


def complete_training_lesson(staff, lesson):
    now = timezone.now()
    completion, created = TrainingCompletion.objects.get_or_create(
        staff=staff,
        lesson=lesson,
        defaults={"completed_at": now},
    )
    if not created and not completion.completed_at:
        completion.completed_at = now
        completion.save(update_fields=["completed_at"])

    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.TRAINING_COMPLETED,
        metadata={
            "lesson_id": str(lesson.id),
            "lesson_title": lesson.title,
            "created": created,
        },
    )
    return completion


def _open_sessions_by_staff():
    open_sessions = {}
    for session in Session.objects.select_related("staff").filter(is_open=True).order_by("-login_time"):
        session = reconcile_session(session)
        if session and session.is_open and session.staff_id not in open_sessions:
            open_sessions[session.staff_id] = session
    return open_sessions


def _currently_active_staff_ids(now=None):
    now = now or timezone.now()
    active_cutoff = now - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    active_staff_ids = {
        staff_id
        for staff_id, session in _open_sessions_by_staff().items()
        if session.last_known_state == Session.AppState.FOREGROUND
        and session.last_heartbeat_at
        and session.last_heartbeat_at >= active_cutoff
    }
    active_staff_ids.update(_live_call_staff_ids())
    return active_staff_ids


def _live_call_staff_ids():
    return _reconcile_open_calls()


def _release_due_callback_leads_from_inactive_staff(*, now=None, active_staff_ids=None):
    current_slot = _current_callback_window(now)
    if not current_slot:
        return 0

    active_staff_ids = active_staff_ids if active_staff_ids is not None else _currently_active_staff_ids(now=now)
    if not active_staff_ids:
        return 0

    return Lead.objects.filter(
        status=Lead.Status.CALL_BACK,
        callback_window=current_slot,
        assigned_to__isnull=False,
    ).exclude(assigned_to_id__in=active_staff_ids).update(
        assigned_to=None,
        updated_at=timezone.now(),
    )


def build_dashboard_payload():
    today, start, end = _today_range()
    staff_queryset = Staff.objects.filter(is_active=True, role=Staff.Role.STAFF)
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    week_start, week_end = _week_range()
    month_start, month_end = _month_range()

    open_sessions = _open_sessions_by_staff()
    live_call_staff_ids = _live_call_staff_ids()

    active_staff = sum(
        1
        for staff in staff_queryset
        if _staff_online_label(
            open_sessions.get(staff.id),
            active_cutoff,
            is_in_customer_call=staff.id in live_call_staff_ids,
        )
        in {"Online", "On Call"}
    )
    total_staff = staff_queryset.count()

    leads = Lead.objects.select_related("assigned_to")
    calls_today = Call.objects.filter(start_time__range=(start, end))
    qualifying_calls_today = calls_today.filter(is_qualifying=True)
    sessions_today = Session.objects.filter(login_time__range=(start, end))

    total_leads = leads.count()
    follow_up_count = leads.filter(status=Lead.Status.INTERESTED).count()
    converted_count = leads.filter(status=Lead.Status.CONVERTED).count()
    no_response_count = leads.filter(status=Lead.Status.NO_ANSWER).count()
    callbacks_count = leads.filter(status=Lead.Status.CALL_BACK).count()

    calls_today_count = qualifying_calls_today.count()
    converted_calls_today = qualifying_calls_today.filter(status=Call.Status.CONVERTED).count()
    conversion_rate = round((converted_calls_today / calls_today_count) * 100, 1) if calls_today_count else 0
    work_coverage_pct = round((active_staff / total_staff) * 100) if total_staff else 0
    short_calls_blocked = calls_today.filter(status=Call.Status.INVALID_SHORT).count()

    active_seconds_today = sessions_today.aggregate(total=Sum("active_seconds")).get("total") or 0
    salary_ready = sessions_today.values("staff_id").distinct().count()

    converted_counter = Counter(
        calls_today.filter(status=Call.Status.CONVERTED).values_list("staff_id", flat=True)
    )
    session_totals = {
        row["staff_id"]: row["total"] or 0
        for row in sessions_today.values("staff_id").annotate(total=Sum("active_seconds"))
    }
    call_totals = {
        row["staff_id"]: row["total"] or 0
        for row in qualifying_calls_today.values("staff_id").annotate(total=Sum("duration_seconds"))
    }
    month_session_totals, month_call_totals, month_converted = _staff_period_totals(month_start, month_end)
    week_session_totals, week_call_totals, week_converted = _staff_period_totals(week_start, week_end)
    salary_estimate = Decimal("0.00")
    for staff in staff_queryset:
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, _ = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)
        salary_estimate += current_payable

    trend_rows = (
        Call.objects.filter(start_time__date__gte=today - timedelta(days=6), start_time__date__lte=today)
        .annotate(day=TruncDate("start_time"))
        .values("day")
        .annotate(
            call_count=Count("id", filter=Q(is_qualifying=True)),
            conversion_count=Count("id", filter=Q(status=Call.Status.CONVERTED, is_qualifying=True)),
        )
        .order_by("day")
    )
    trend_map = {row["day"]: row for row in trend_rows}
    trend_labels = []
    trend_calls = []
    trend_conversions = []
    for offset in range(6, -1, -1):
        day = today - timedelta(days=offset)
        trend_labels.append(day.strftime("%a"))
        trend_calls.append(trend_map.get(day, {}).get("call_count", 0))
        trend_conversions.append(trend_map.get(day, {}).get("conversion_count", 0))

    lead_pipeline = {
        "labels": ["New", "Follow Up", "Call Back", "No Response", "Converted"],
        "values": [
            leads.filter(status=Lead.Status.NEW).count(),
            follow_up_count,
            callbacks_count,
            no_response_count,
            converted_count,
        ],
    }

    top_staff = []
    for staff in staff_queryset.order_by("name")[:5]:
        top_staff.append(
            {
                "label": staff.name.split()[0],
                "active_hours": round((session_totals.get(staff.id, 0) or 0) / 3600, 1),
                "call_minutes": round((call_totals.get(staff.id, 0) or 0) / 60),
            }
        )

    live_staff = []
    for staff in staff_queryset.order_by("name")[:8]:
        session = open_sessions.get(staff.id)
        is_in_customer_call = staff.id in live_call_staff_ids
        if session:
            status_label = "On customer call" if is_in_customer_call else _session_status_label(session)
            session_hours = round((session.active_seconds or 0) / 3600, 1)
            status_text = f"{status_label} - {session_hours}h active"
        else:
            status_text = "On customer call" if is_in_customer_call else "Offline - No active session"

        live_staff.append(
            {
                "name": staff.name,
                "status_text": status_text,
                "is_online": _staff_online_label(
                    session,
                    active_cutoff,
                    is_in_customer_call=is_in_customer_call,
                )
                in {"Online", "On Call"},
            }
        )

    lead_rows = []
    for lead in leads.order_by("-updated_at")[:20]:
        lead_rows.append(
            {
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "last_call": timezone.localtime(lead.last_contacted_at).strftime("%I:%M %p") if lead.last_contacted_at else "Not called yet",
                "next_action": {
                    Lead.Status.NEW: "Assign and dial",
                    Lead.Status.CALL_BACK: "Follow up on schedule",
                    Lead.Status.INTERESTED: "Complete the follow-up",
                    Lead.Status.CONVERTED: "Move to onboarding",
                    Lead.Status.NO_ANSWER: "Retry if needed",
                    Lead.Status.NOT_INTERESTED: "Keep for reporting",
                }.get(lead.status, "Review"),
            }
        )

    salary_records = []
    for staff in staff_queryset.order_by("name")[:6]:
        staff_hours = round((session_totals.get(staff.id, 0) or 0) / 3600, 1)
        staff_call_minutes = round((call_totals.get(staff.id, 0) or 0) / 60)
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, cycle_label = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)
        salary_records.append(
            {
                "name": staff.name,
                "hours": f"{staff_hours}h",
                "call_time": f"{staff_call_minutes}m",
                "bonus": _format_currency(monthly_breakdown["bonus_earnings"]),
                "final_salary": _format_currency(current_payable),
                "cycle_label": cycle_label,
            }
        )

    team_directory = []
    for staff in staff_queryset.order_by("name"):
        session = open_sessions.get(staff.id)
        team_directory.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "is_active": staff.is_active,
                "online_label": _staff_online_label(
                    session,
                    active_cutoff,
                    is_in_customer_call=staff.id in live_call_staff_ids,
                ),
            }
        )

    dashboard = {
        "today_label": today.strftime("%A, %d %b %Y"),
        "staff_active": active_staff,
        "calls_today": calls_today_count,
        "conversion_rate": f"{conversion_rate:.1f}%",
        "callbacks": callbacks_count,
        "work_coverage": work_coverage_pct,
        "short_calls_blocked": short_calls_blocked,
        "salary_ready": salary_ready,
        "total_leads": total_leads,
        "no_answer": no_response_count,
        "interested": follow_up_count,
        "converted": converted_count,
        "salary_estimate": _format_currency(salary_estimate),
        "active_hours": _format_hours(active_seconds_today),
    }

    chart_payload = {
        "callVolume": {
            "labels": trend_labels,
            "calls": trend_calls,
            "conversions": trend_conversions,
        },
        "leadPipeline": lead_pipeline,
        "activityBalance": {
            "labels": [item["label"] for item in top_staff],
            "activeHours": [item["active_hours"] for item in top_staff],
            "callMinutes": [item["call_minutes"] for item in top_staff],
        },
    }

    return {
        "dashboard": dashboard,
        "chart_payload": chart_payload,
        "live_staff": live_staff,
        "lead_rows": lead_rows,
        "salary_records": salary_records,
        "team_directory": team_directory,
    }


def build_team_management_payload():
    today, start, end = _today_range()
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    staff_queryset = _staff_queryset()
    staff_ids = [staff.id for staff in staff_queryset]
    open_sessions = _open_sessions_by_staff()
    live_call_staff_ids = _live_call_staff_ids()
    quality_by_staff = _build_staff_quality_metrics(staff_ids)

    call_totals = {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end))
        .values("staff_id")
        .annotate(count=Count("id"))
    }
    converted_totals = {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end), status=Call.Status.CONVERTED)
        .values("staff_id")
        .annotate(count=Count("id"))
    }
    active_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Session.objects.filter(login_time__range=(start, end))
        .values("staff_id")
        .annotate(total=Sum("active_seconds"))
    }
    assigned_totals = {
        row["assigned_to"]: row["count"]
        for row in _lead_queue_queryset().exclude(assigned_to=None)
        .values("assigned_to")
        .annotate(count=Count("id"))
    }

    team_rows = []
    total_assigned = 0
    total_calls_today = 0
    total_converted_today = 0
    active_accounts = 0
    online_now = 0
    attention_needed = 0
    for staff in staff_queryset:
        session = open_sessions.get(staff.id)
        online_label = _staff_online_label(
            session,
            active_cutoff,
            is_in_customer_call=staff.id in live_call_staff_ids,
        )
        calls_today = call_totals.get(staff.id, 0)
        converted_today = converted_totals.get(staff.id, 0)
        assigned_leads = assigned_totals.get(staff.id, 0)
        quality = quality_by_staff.get(staff.id, {})
        is_available = staff.is_active and online_label in {"Online", "On Call"}
        status_filter = "inactive"
        status_tone = "muted"
        if staff.is_active:
            active_accounts += 1
            if online_label in {"Online", "On Call"}:
                online_now += 1
                status_filter = "online"
                status_tone = "success"
            elif online_label in {"Away", "Warning"}:
                attention_needed += 1
                status_filter = "attention"
                status_tone = "warning"
            else:
                attention_needed += 1
                status_filter = "offline"
                status_tone = "muted"

        total_assigned += assigned_leads
        total_calls_today += calls_today
        total_converted_today += converted_today
        team_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "is_active": staff.is_active,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "online_label": online_label,
                "status_filter": status_filter,
                "status_tone": status_tone,
                "session_state": session.last_known_state if session else "stopped",
                "active_hours_today": _format_hours(active_totals.get(staff.id, 0)),
                "active_seconds_today": active_totals.get(staff.id, 0),
                "calls_today": calls_today,
                "converted_today": converted_today,
                "assigned_leads": assigned_leads,
                "last_seen": _format_datetime(staff.last_seen_at),
                "is_available": is_available,
                "quality_score": quality.get("score", 0),
                "quality_label": quality.get("label", "No Recent Activity"),
                "quality_tone": quality.get("tone", "muted"),
                "quality_note": quality.get("note", "Build more recent call activity for a fuller review."),
                "outcome_consistency_label": quality.get("outcome_consistency_label", "--"),
                "followup_completion_label": quality.get("followup_completion_label", "--"),
                "missed_callbacks": quality.get("missed_callbacks", 0),
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "team_summary": {
            "total_staff": len(team_rows),
            "active_accounts": active_accounts,
            "online_now": online_now,
            "attention_needed": attention_needed,
            "total_assigned": total_assigned,
            "total_calls_today": total_calls_today,
            "total_converted_today": total_converted_today,
        },
        "team_rows": team_rows,
    }


def build_staff_profile_payload(request, staff):
    today, start, end = _today_range()
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    open_session = get_open_session(staff, reconcile=True)
    live_call_staff_ids = _live_call_staff_ids()
    latest_session = Session.objects.filter(staff=staff).order_by("-login_time").first()
    sessions_today = Session.objects.filter(staff=staff, login_time__range=(start, end))
    recent_sessions = Session.objects.filter(staff=staff).order_by("-login_time")[:12]
    calls_today = Call.objects.filter(staff=staff, start_time__range=(start, end))
    qualifying_calls_today = calls_today.filter(is_qualifying=True)
    recent_calls = Call.objects.filter(staff=staff).select_related("lead").order_by("-start_time")[:20]
    assigned_leads = _ordered_lead_queryset(
        Lead.objects.filter(assigned_to=staff, status__in=ACTIVE_QUEUE_STATUSES).select_related("assigned_to"),
        now=timezone.now(),
    )
    quality = _build_staff_quality_metrics([staff.id]).get(staff.id, {})

    active_seconds_today = sessions_today.aggregate(total=Sum("active_seconds")).get("total") or 0
    converted_today = qualifying_calls_today.filter(status=Call.Status.CONVERTED).count()
    no_answer_today = qualifying_calls_today.filter(status=Call.Status.NO_ANSWER).count()

    assigned_lead_rows = [
        {
            "id": str(lead.id),
            "name": lead.name,
            "phone": lead.phone,
            "status": lead.status,
            "status_label": lead.get_status_display(),
            "callback_window_label": lead.get_callback_window_display() if lead.callback_window else "",
            "last_contacted": _format_datetime(lead.last_contacted_at, fallback="Not called yet"),
            "updated_at": _format_datetime(lead.updated_at),
        }
        for lead in assigned_leads
    ]
    recent_call_rows = [
        {
            "id": str(call.id),
            "lead_name": call.lead.name,
            "lead_phone": call.lead.phone,
            "start_time": _format_datetime(call.start_time),
            "end_time": _format_datetime(call.end_time),
            "duration_label": _format_duration(call.duration_seconds),
            "status": call.status,
            "status_label": call.get_status_display(),
            "callback_window_label": call.get_callback_window_display() if call.callback_window else "",
            "is_qualifying": call.is_qualifying,
        }
        for call in recent_calls
    ]
    recent_session_rows = [
        {
            "id": str(session.id),
            "login_time": _format_datetime(session.login_time),
            "logout_time": _format_datetime(session.logout_time),
            "active_label": _format_duration(session.active_seconds),
            "state_label": _session_status_label(session if session.is_open else None, latest_session=session),
            "close_reason": session.close_reason or "Manual",
        }
        for session in recent_sessions
    ]

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "staff_member": staff,
        "summary": {
            "online_label": _staff_online_label(
                open_session,
                active_cutoff,
                is_in_customer_call=staff.id in live_call_staff_ids,
            ),
            "status_label": _session_status_label(open_session, latest_session=latest_session),
            "last_seen": _format_datetime(staff.last_seen_at),
            "assigned_leads": assigned_leads.count(),
            "calls_today": qualifying_calls_today.count(),
            "converted_today": converted_today,
            "no_answer_today": no_answer_today,
            "active_hours_today": _format_hours(active_seconds_today),
            "hourly_rate": _format_currency(staff.hourly_rate),
            "call_rate": _format_currency(staff.call_rate),
            "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
            "compensation_type_label": staff.get_compensation_type_display(),
            "queue_target": get_lead_queue_limit(),
            "quality_score": quality.get("score", 0),
            "quality_label": quality.get("label", "No Recent Activity"),
            "quality_tone": quality.get("tone", "muted"),
            "quality_note": quality.get("note", "Build more recent call activity for a fuller review."),
            "quality_lookback_days": quality.get("lookback_days", QUALITY_SCORE_LOOKBACK_DAYS),
            "outcome_consistency_label": quality.get("outcome_consistency_label", "--"),
            "followup_completion_label": quality.get("followup_completion_label", "--"),
            "callback_discipline_label": quality.get("callback_discipline_label", "--"),
            "followup_started_count": quality.get("followup_started_count", 0),
            "followup_closed_count": quality.get("followup_closed_count", 0),
            "callback_total": quality.get("callback_total", 0),
            "missed_callbacks": quality.get("missed_callbacks", 0),
        },
        "identity_details": {
            "email": staff.email or "--",
            "bank_account_name": staff.bank_account_name or "--",
            "bank_name": staff.bank_name or "--",
            "bank_account_number": staff.bank_account_number or "--",
            "bank_ifsc_code": staff.bank_ifsc_code or "--",
            "aadhar_number": staff.aadhar_number or "--",
            "aadhar_photo_url": request.build_absolute_uri(
                reverse("staff-document-page", args=[staff.id, "aadhar"])
            )
            if staff.aadhar_photo
            else "",
            "passbook_photo_url": request.build_absolute_uri(
                reverse("staff-document-page", args=[staff.id, "passbook"])
            )
            if staff.passbook_photo
            else "",
        },
        "assigned_lead_rows": assigned_lead_rows,
        "recent_call_rows": recent_call_rows,
        "recent_session_rows": recent_session_rows,
    }


def build_salary_control_payload(request):
    hourly_tracking_count = 0
    weekly_count = 0
    monthly_count = 0
    salary_rows = []
    for staff in _staff_queryset():
        hourly_tracking_count += 1
        if staff.compensation_type == Staff.CompensationType.WEEKLY:
            weekly_count += 1
        elif staff.compensation_type == Staff.CompensationType.MONTHLY:
            monthly_count += 1

        salary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "email": staff.email or "--",
                "is_active": staff.is_active,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": _payout_cycle_label(staff),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "hourly_rate_raw": str(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "weekly_salary_raw": str(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "monthly_salary_raw": str(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "call_rate_raw": str(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "bonus_per_conversion_raw": str(staff.bonus_per_conversion),
                "target_label": _salary_setting_target_label(staff),
                "bank_account_name": staff.bank_account_name or "--",
                "bank_name": staff.bank_name or "--",
                "bank_account_number": staff.bank_account_number or "--",
                "bank_ifsc_code": staff.bank_ifsc_code or "--",
                "has_passbook_photo": bool(staff.passbook_photo),
                "passbook_photo_url": request.build_absolute_uri(
                    reverse("staff-document-page", args=[staff.id, "passbook"])
                )
                if staff.passbook_photo
                else "",
                "profile_url": reverse("staff-profile-page", args=[staff.id]),
            }
        )

    return {
        "summary": {
            "hourly_tracking_count": hourly_tracking_count,
            "weekly_count": weekly_count,
            "monthly_count": monthly_count,
        },
        "salary_rows": salary_rows,
    }


def build_salary_page_payload():
    today = timezone.localdate()
    week_start, week_end = _week_range()
    month_start, month_end = _month_range()
    week_session_totals, week_call_totals, week_converted = _staff_period_totals(week_start, week_end)
    month_session_totals, month_call_totals, month_converted = _staff_period_totals(month_start, month_end)
    paid_totals_by_staff = {
        row["staff_id"]: row["paid_total"] or Decimal("0.00")
        for row in Salary.objects.filter(is_paid=True).values("staff_id").annotate(paid_total=Sum("paid_amount"))
    }
    paid_meta_by_staff = {
        row["staff_id"]: row["last_paid_at"]
        for row in Salary.objects.filter(is_paid=True).values("staff_id").annotate(last_paid_at=Max("paid_at"))
    }

    weekly_total = Decimal("0.00")
    monthly_total = Decimal("0.00")
    current_cycle_total = Decimal("0.00")
    weekly_hours_total = Decimal("0.00")
    monthly_hours_total = Decimal("0.00")
    hourly_tracking_count = 0
    weekly_cycle_count = 0
    monthly_cycle_count = 0
    salary_rows = []

    for staff in _staff_queryset():
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, cycle_label = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)

        weekly_total += weekly_breakdown["total_pay"]
        monthly_total += monthly_breakdown["total_pay"]
        current_cycle_total += current_payable
        weekly_hours_total += weekly_breakdown["active_hours"]
        monthly_hours_total += monthly_breakdown["active_hours"]
        hourly_tracking_count += 1
        if staff.compensation_type == Staff.CompensationType.WEEKLY:
            weekly_cycle_count += 1
        elif staff.compensation_type == Staff.CompensationType.MONTHLY:
            monthly_cycle_count += 1

        salary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": _payout_cycle_label(staff),
                "target_label": _salary_setting_target_label(staff),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "weekly_hours": round(float(weekly_breakdown["active_hours"]), 2),
                "monthly_hours": round(float(monthly_breakdown["active_hours"]), 2),
                "weekly_hours_label": f"{round(float(weekly_breakdown['active_hours']), 1)}h",
                "monthly_hours_label": f"{round(float(monthly_breakdown['active_hours']), 1)}h",
                "weekly_base": _format_currency(weekly_breakdown["base_pay"]),
                "weekly_call": _format_currency(weekly_breakdown["call_earnings"]),
                "weekly_bonus": _format_currency(weekly_breakdown["bonus_earnings"]),
                "weekly_total": _format_currency(weekly_breakdown["total_pay"]),
                "monthly_base": _format_currency(monthly_breakdown["base_pay"]),
                "monthly_call": _format_currency(monthly_breakdown["call_earnings"]),
                "monthly_bonus": _format_currency(monthly_breakdown["bonus_earnings"]),
                "monthly_total": _format_currency(monthly_breakdown["total_pay"]),
                "current_cycle_label": cycle_label,
                "current_payable_raw": current_payable,
                "current_payable": _format_currency(current_payable),
                "credited_total": _format_currency(paid_totals_by_staff.get(staff.id, Decimal("0.00"))),
                "last_paid_at": _format_datetime(paid_meta_by_staff.get(staff.id)),
            }
        )

    top_row = max(
        salary_rows,
        key=lambda row: row["current_payable_raw"],
        default=None,
    )
    for row in salary_rows:
        row.pop("current_payable_raw", None)

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "week_label": f"Week of {timezone.localtime(week_start).strftime('%d %b %Y')}",
        "month_label": today.strftime("%B %Y"),
        "summary": {
            "weekly_total": _format_currency(weekly_total),
            "monthly_total": _format_currency(monthly_total),
            "current_cycle_total": _format_currency(current_cycle_total),
            "weekly_hours_total": f"{round(float(weekly_hours_total), 1)}h",
            "monthly_hours_total": f"{round(float(monthly_hours_total), 1)}h",
            "hourly_tracking_count": hourly_tracking_count,
            "weekly_cycle_count": weekly_cycle_count,
            "monthly_cycle_count": monthly_cycle_count,
            "top_payout_name": top_row["name"] if top_row else "No staff data",
            "top_payout_value": top_row["current_payable"] if top_row else _format_currency(0),
        },
        "salary_rows": salary_rows,
    }


def build_salary_detail_payload(staff):
    today = timezone.localdate()
    week_start_at, _ = _week_range()
    month_start_at, _ = _month_range()
    week_start = timezone.localtime(week_start_at).date()
    month_start = timezone.localtime(month_start_at).date()

    weekly_breakdown = calculate_staff_payout_for_dates(staff, week_start, today)
    monthly_breakdown = calculate_staff_payout_for_dates(staff, month_start, today)
    salary_history = build_staff_salary_history_rows(staff, limit=40)
    total_paid = Salary.objects.filter(staff=staff, is_paid=True).aggregate(total=Sum("paid_amount")).get("total") or Decimal("0.00")
    latest_paid = Salary.objects.filter(staff=staff, is_paid=True).order_by("-paid_at", "-period_end").first()

    return {
        "staff_member": staff,
        "summary": {
            "weekly_payable": _format_currency(weekly_breakdown["total_pay"]),
            "monthly_payable": _format_currency(monthly_breakdown["total_pay"]),
            "weekly_hours": f"{round(float(weekly_breakdown['active_hours']), 1)}h",
            "monthly_hours": f"{round(float(monthly_breakdown['active_hours']), 1)}h",
            "total_paid": _format_currency(total_paid),
            "last_paid_at": _format_datetime(latest_paid.paid_at) if latest_paid else "--",
            "last_paid_amount": _format_currency(latest_paid.paid_amount) if latest_paid else _format_currency(0),
        },
        "weekly_breakdown": {
            "period_label": f"{week_start.strftime('%d %b %Y')} to {today.strftime('%d %b %Y')}",
            "period_start": week_start.isoformat(),
            "period_end": today.isoformat(),
            "hours": f"{round(float(weekly_breakdown['active_hours']), 1)}h",
            "base_pay": _format_currency(weekly_breakdown["base_pay"]),
            "call_earnings": _format_currency(weekly_breakdown["call_earnings"]),
            "bonus_earnings": _format_currency(weekly_breakdown["bonus_earnings"]),
            "recommended_amount": _format_currency(weekly_breakdown["total_pay"]),
            "recommended_amount_raw": f"{_money(weekly_breakdown['total_pay']):.2f}",
        },
        "monthly_breakdown": {
            "period_label": f"{month_start.strftime('%d %b %Y')} to {today.strftime('%d %b %Y')}",
            "period_start": month_start.isoformat(),
            "period_end": today.isoformat(),
            "hours": f"{round(float(monthly_breakdown['active_hours']), 1)}h",
            "base_pay": _format_currency(monthly_breakdown["base_pay"]),
            "call_earnings": _format_currency(monthly_breakdown["call_earnings"]),
            "bonus_earnings": _format_currency(monthly_breakdown["bonus_earnings"]),
            "recommended_amount": _format_currency(monthly_breakdown["total_pay"]),
            "recommended_amount_raw": f"{_money(monthly_breakdown['total_pay']):.2f}",
        },
        "custom_defaults": {
            "period_start": month_start.isoformat(),
            "period_end": today.isoformat(),
            "paid_amount": f"{_money(monthly_breakdown['total_pay']):.2f}",
        },
        "payment_method_options": [
            {"value": value, "label": label}
            for value, label in Salary.PaymentMethod.choices
        ],
        "salary_history_rows": salary_history,
    }


def get_latest_app_release():
    return (
        AppRelease.objects.filter(is_active=True, published_at__lte=timezone.now())
        .select_related("created_by")
        .order_by("-version_code", "-published_at")
        .first()
    )


def publish_app_release(*, created_by, validated_data):
    is_active = validated_data.get("is_active", True)
    app_release = AppRelease.objects.create(created_by=created_by, **validated_data)
    if is_active:
        AppRelease.objects.exclude(id=app_release.id).update(is_active=False)
    return app_release


def set_active_app_release(app_release):
    AppRelease.objects.exclude(id=app_release.id).update(is_active=False)
    if not app_release.is_active:
        app_release.is_active = True
        app_release.save(update_fields=["is_active", "updated_at"])
    return app_release


def build_developer_release_payload():
    releases = AppRelease.objects.select_related("created_by").order_by("-version_code", "-published_at")
    latest_release = get_latest_app_release()
    total_uploaded_bytes = sum(int(release.file_size_bytes or 0) for release in releases)
    max_release_bytes = max((int(release.file_size_bytes or 0) for release in releases), default=0)
    release_rows = [
        {
            "id": str(release.id),
            "version_name": release.version_name,
            "version_code": release.version_code,
            "minimum_supported_version_code": release.minimum_supported_version_code,
            "release_notes": release.release_notes or "No release notes added.",
            "is_mandatory": release.is_mandatory,
            "is_active": release.is_active,
            "published_at": _format_datetime(release.published_at),
            "created_by": release.created_by.name if release.created_by else "Release Desk",
            "download_url": reverse("app-release-download", args=[release.id]) if release.apk_file else "",
            "file_size_label": f"{round((release.file_size_bytes or 0) / (1024 * 1024), 2)} MB",
        }
        for release in releases
    ]
    upload_graph_rows = [
        {
            "label": f"{release.version_name} ({release.version_code})",
            "file_size_label": f"{round((release.file_size_bytes or 0) / (1024 * 1024), 2)} MB",
            "relative_percent": round(
                ((int(release.file_size_bytes or 0) / max_release_bytes) * 100) if max_release_bytes else 0,
                2,
            ),
            "is_active": release.is_active,
        }
        for release in reversed(list(releases[:8]))
    ]
    return {
        "latest_release": latest_release,
        "latest_release_download_url": reverse("app-release-download", args=[latest_release.id])
        if latest_release and latest_release.apk_file
        else "",
        "release_summary": {
            "release_count": len(release_rows),
            "total_uploaded_label": f"{round(total_uploaded_bytes / (1024 * 1024), 2)} MB",
            "largest_release_label": f"{round(max_release_bytes / (1024 * 1024), 2)} MB"
            if max_release_bytes
            else "0 MB",
        },
        "upload_graph_rows": upload_graph_rows,
        "release_rows": release_rows,
    }


def build_app_update_payload(request, *, current_version_code=0):
    latest_release = get_latest_app_release()
    if not latest_release or not latest_release.apk_file:
        return {"update_available": False}

    current_version_code = int(current_version_code or 0)
    download_url = request.build_absolute_uri(reverse("app-release-download", args=[latest_release.id]))
    effective_mandatory = bool(
        latest_release.is_mandatory
        or (
            latest_release.minimum_supported_version_code
            and current_version_code < latest_release.minimum_supported_version_code
        )
    )
    return {
        "update_available": latest_release.version_code > current_version_code,
        "version_name": latest_release.version_name,
        "version_code": latest_release.version_code,
        "minimum_supported_version_code": latest_release.minimum_supported_version_code,
        "release_notes": latest_release.release_notes,
        "is_mandatory": effective_mandatory,
        "download_url": download_url,
        "file_name": latest_release.apk_file.name.rsplit("/", 1)[-1],
        "published_at": latest_release.published_at.isoformat(),
        "file_size_bytes": latest_release.file_size_bytes,
    }

def build_settings_payload(current_user):
    company_profile = get_company_profile()
    company_details = [
        ("Company Email", company_profile.company_email or "Not added yet"),
        ("Company Phone", company_profile.company_phone or "Not added yet"),
        ("Support Phone", company_profile.support_phone or "Not added yet"),
        ("Website", company_profile.website or "Not added yet"),
        ("Tax ID", company_profile.tax_identifier or "Not added yet"),
        ("Country", company_profile.country or "Not added yet"),
        ("Lead Target / Staff", str(get_lead_queue_limit())),
    ]
    address_parts = [
        company_profile.address_line_1,
        company_profile.address_line_2,
        company_profile.city,
        company_profile.state,
        company_profile.postal_code,
        company_profile.country,
    ]
    formatted_address = ", ".join(part for part in address_parts if part) or "Not added yet"

    return {
        "company_profile": company_profile,
        "profile_summary": {
            "name": current_user.name,
            "phone": current_user.phone,
            "role_label": current_user.get_role_display(),
            "last_seen": _format_datetime(current_user.last_seen_at),
            "status_label": "Active" if current_user.is_active else "Inactive",
        },
        "company_summary": {
            "address": formatted_address,
            "description": company_profile.description or "Add company details, address, and support information here.",
            "details": company_details,
        },
    }


def build_lead_management_payload():
    auto_allocate_leads()
    leads = Lead.objects.select_related("assigned_to").order_by("-updated_at")
    active_queue = _lead_queue_queryset()
    queue_limit = get_lead_queue_limit()
    staff_options = [
        {"id": str(staff.id), "name": staff.name}
        for staff in _staff_queryset().filter(is_active=True)
    ]

    lead_rows = []
    for lead in leads:
        lead_rows.append(
            {
                "id": str(lead.id),
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "callback_window": lead.callback_window,
                "callback_window_label": lead.get_callback_window_display() if lead.callback_window else "",
                "assigned_to_id": str(lead.assigned_to_id) if lead.assigned_to_id else "",
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "notes": lead.notes,
                "last_contacted": _format_datetime(lead.last_contacted_at, fallback="Not called yet"),
                "updated_at": _format_datetime(lead.updated_at),
            }
        )

    return {
        "lead_rows": lead_rows,
        "staff_options": staff_options,
        "queue_summary": {
            "active_queue_total": active_queue.count(),
            "unassigned_total": active_queue.filter(assigned_to=None).count(),
            "staff_active_count": _staff_queryset().filter(is_active=True).count(),
            "queue_limit": queue_limit,
        },
    }


def build_followup_payload():
    current_slot = _current_callback_window()
    followups = (
        _follow_up_queryset()
        .select_related("assigned_to")
        .annotate(
            callback_priority=Case(
                When(status=Lead.Status.CALL_BACK, callback_window=current_slot, then=Value(0)),
                When(status=Lead.Status.CALL_BACK, then=Value(1)),
                default=Value(2),
                output_field=IntegerField(),
            )
        )
        .order_by("callback_priority", "-last_contacted_at", "-updated_at")
    )

    followup_rows = []
    for lead in followups:
        followup_rows.append(
            {
                "id": str(lead.id),
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "callback_window": lead.callback_window,
                "callback_window_label": lead.get_callback_window_display() if lead.callback_window else "",
                "assigned_to_id": str(lead.assigned_to_id) if lead.assigned_to_id else "",
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "assigned_to_phone": lead.assigned_to.phone if lead.assigned_to else "",
                "notes": lead.notes,
                "last_contacted": _format_datetime(lead.last_contacted_at, fallback="Not called yet"),
                "updated_at": _format_datetime(lead.updated_at),
                "is_due_now": lead.status == Lead.Status.CALL_BACK and lead.callback_window == current_slot,
            }
        )

    return {
        "followup_rows": followup_rows,
        "staff_options": [
            {"id": str(staff.id), "name": staff.name}
            for staff in _staff_queryset().filter(is_active=True)
        ],
        "followup_summary": {
            "total_followups": len(followup_rows),
            "follow_up_count": sum(1 for row in followup_rows if row["status"] == Lead.Status.INTERESTED),
            "callback_count": sum(1 for row in followup_rows if row["status"] == Lead.Status.CALL_BACK),
            "due_now_count": sum(1 for row in followup_rows if row["is_due_now"]),
            "unassigned_count": sum(1 for row in followup_rows if not row["assigned_to_id"]),
            "current_slot_label": dict(Lead.CallbackWindow.choices).get(current_slot, "No slot"),
        },
    }


def build_followup_csv_response():
    response = io.StringIO()
    writer = csv.writer(response)
    writer.writerow(
        [
            "Lead ID",
            "Name",
            "Phone",
            "Status",
            "Callback Window",
            "Assigned Staff",
            "Assigned Staff Phone",
            "Notes",
            "Last Contacted",
            "Updated At",
        ]
    )

    for row in build_followup_payload()["followup_rows"]:
        writer.writerow(
            [
                row["id"],
                row["name"],
                row["phone"],
                row["status_label"],
                row["callback_window_label"],
                row["assigned_to"],
                row["assigned_to_phone"],
                row["notes"],
                row["last_contacted"],
                row["updated_at"],
            ]
        )

    return response.getvalue()


def _recovery_status_scope(scope):
    if scope == "rejected":
        return (Lead.Status.NOT_INTERESTED,)
    if scope == "no_response":
        return (Lead.Status.NO_ANSWER,)
    return RECOVERY_LEAD_STATUSES


def build_recovery_lead_payload():
    recovery_leads = (
        _recovery_lead_queryset()
        .select_related("assigned_to")
        .order_by("updated_at", "last_contacted_at", "created_at", "id")
    )

    recovery_rows = []
    for lead in recovery_leads:
        recovery_rows.append(
            {
                "id": str(lead.id),
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "notes": lead.notes,
                "last_contacted": _format_datetime(lead.last_contacted_at, fallback="Not called yet"),
                "updated_at": _format_datetime(lead.updated_at),
                "created_at": _format_datetime(lead.created_at),
            }
        )

    rejected_count = sum(1 for row in recovery_rows if row["status"] == Lead.Status.NOT_INTERESTED)
    no_response_count = sum(1 for row in recovery_rows if row["status"] == Lead.Status.NO_ANSWER)
    oldest_row = recovery_rows[0] if recovery_rows else None
    return {
        "recovery_rows": recovery_rows,
        "recovery_summary": {
            "total_count": len(recovery_rows),
            "rejected_count": rejected_count,
            "no_response_count": no_response_count,
            "queue_limit": get_lead_queue_limit(),
            "oldest_lead_name": oldest_row["name"] if oldest_row else "No leads in this list",
            "oldest_lead_updated_at": oldest_row["updated_at"] if oldest_row else "No waiting recovery leads",
        },
    }


def reactivate_oldest_recovery_leads(count, *, scope="all"):
    count = max(1, int(count))
    recovery_statuses = _recovery_status_scope(scope)
    selected_leads = list(
        Lead.objects.filter(status__in=recovery_statuses)
        .order_by("updated_at", "last_contacted_at", "created_at", "id")[:count]
    )

    if not selected_leads:
        return {
            "reactivated_count": 0,
            "assigned_count": 0,
            "remaining_unassigned_count": _lead_queue_queryset().filter(assigned_to=None).count(),
            "scope_label": scope,
        }

    now = timezone.now()
    selected_ids = [lead.id for lead in selected_leads]
    Lead.objects.filter(id__in=selected_ids).update(
        status=Lead.Status.NEW,
        callback_window="",
        assigned_to=None,
        updated_at=now,
    )
    allocation = auto_allocate_leads(prioritized_lead_ids=selected_ids)
    return {
        "reactivated_count": len(selected_ids),
        "assigned_count": allocation["assigned_count"],
        "remaining_unassigned_count": allocation["remaining_unassigned_count"],
        "scope_label": scope,
    }


def build_call_detail_payload(limit=200):
    calls = Call.objects.select_related("staff", "lead").order_by("-start_time")[:limit]
    call_rows = []
    for call in calls:
        call_rows.append(
            {
                "id": str(call.id),
                "staff_name": call.staff.name,
                "lead_name": call.lead.name,
                "lead_phone": call.lead.phone,
                "start_time": _format_datetime(call.start_time),
                "end_time": _format_datetime(call.end_time),
                "duration_seconds": call.duration_seconds,
                "duration_label": _format_duration(call.duration_seconds),
                "status": call.status,
                "status_label": call.get_status_display(),
                "callback_window": call.callback_window,
                "callback_window_label": call.get_callback_window_display() if call.callback_window else "",
                "is_qualifying": call.is_qualifying,
            }
        )

    return {"call_rows": call_rows}


def build_work_hours_payload():
    today, start, end = _today_range()
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    open_sessions = _open_sessions_by_staff()
    live_call_staff_ids = _live_call_staff_ids()

    sessions_today = Session.objects.filter(login_time__range=(start, end)).select_related("staff").order_by("-login_time")
    totals = {
        row["staff_id"]: row["total"] or 0
        for row in sessions_today.values("staff_id").annotate(total=Sum("active_seconds"))
    }
    session_counts = {
        row["staff_id"]: row["count"]
        for row in sessions_today.values("staff_id").annotate(count=Count("id"))
    }
    first_login_map = {}
    last_logout_map = {}
    for session in sessions_today:
        first_login_map[session.staff_id] = min(
            session.login_time,
            first_login_map.get(session.staff_id, session.login_time),
        )
        if session.logout_time:
            last_logout_map[session.staff_id] = max(
                session.logout_time,
                last_logout_map.get(session.staff_id, session.logout_time),
            )

    summary_rows = []
    for staff in _staff_queryset():
        session = open_sessions.get(staff.id)
        summary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "active_hours_today": _format_hours(totals.get(staff.id, 0)),
                "active_seconds_today": totals.get(staff.id, 0),
                "session_count_today": session_counts.get(staff.id, 0),
                "first_login": _format_datetime(first_login_map.get(staff.id)),
                "last_logout": _format_datetime(last_logout_map.get(staff.id)),
                "state_label": _session_status_label(session),
                "online_label": _staff_online_label(
                    session,
                    active_cutoff,
                    is_in_customer_call=staff.id in live_call_staff_ids,
                ),
            }
        )

    session_rows = []
    for session in sessions_today[:200]:
        session_rows.append(
            {
                "id": str(session.id),
                "staff_name": session.staff.name,
                "login_time": _format_datetime(session.login_time),
                "logout_time": _format_datetime(session.logout_time),
                "active_seconds": session.active_seconds,
                "active_label": _format_duration(session.active_seconds),
                "last_known_state": session.last_known_state,
                "close_reason": session.close_reason or "Manual",
                "is_open": session.is_open,
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "summary_rows": summary_rows,
        "session_rows": session_rows,
    }


def start_staff_session(staff, *, source="manual_start"):
    now = timezone.now()
    session = get_open_session(staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": source, "reused": True})
        return session, False

    pending_lessons = list(get_pending_mandatory_lessons(staff)[:20])
    if pending_lessons:
        pending_payload = build_staff_learning_payload(staff)
        _log_staff_action(
            staff,
            StaffAction.ActionType.TRAINING_REQUIRED_BLOCKED,
            metadata={
                "pending_mandatory_count": pending_payload["summary"]["pending_mandatory_count"],
                "next_required_title": pending_payload["summary"]["next_required_title"],
            },
        )
        raise TrainingRequiredError(pending_payload)

    auto_allocate_leads(target_staff=staff)
    session = Session.objects.create(
        staff=staff,
        login_time=now,
        last_heartbeat_at=now,
        last_interaction_at=now,
        state_changed_at=now,
        last_known_state=Session.AppState.OFFLINE,
        is_open=True,
    )
    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.SESSION_STARTED,
        session=session,
        app_state=Session.AppState.OFFLINE,
        metadata={"source": source},
    )
    return session, True


def record_session_heartbeat(staff, state, *, interaction=False, source="timer"):
    session = get_open_session(staff)
    if not session:
        return None

    now = timezone.now()
    session = reconcile_session(session, now=now)
    if not session or not session.is_open:
        return None

    has_live_customer_call = staff.id in _reconcile_open_calls(staff=staff, now=now)
    previous_state = session.last_known_state
    session.active_seconds += _active_elapsed_until(
        session,
        now,
        has_live_customer_call=has_live_customer_call,
    )
    session.last_heartbeat_at = now
    session.heartbeat_count += 1

    if interaction:
        session.last_interaction_at = now

    requested_state = _resolve_requested_state(
        session,
        state,
        now,
        interaction,
        has_live_customer_call=has_live_customer_call,
    )
    update_fields = ["active_seconds", "last_heartbeat_at", "heartbeat_count"]

    if interaction:
        update_fields.append("last_interaction_at")

    if requested_state != previous_state:
        session.last_known_state = requested_state
        session.state_changed_at = now
        update_fields.extend(["last_known_state", "state_changed_at"])

    if requested_state == Session.AppState.WARNING:
        if previous_state != Session.AppState.WARNING or session.warning_started_at is None:
            session.warning_started_at = now
            update_fields.append("warning_started_at")
    elif session.warning_started_at is not None:
        session.warning_started_at = None
        update_fields.append("warning_started_at")

    session.save(update_fields=_dedupe_fields(update_fields))
    mark_staff_seen(staff, now)

    action_type = None
    if requested_state == Session.AppState.BACKGROUND and previous_state != Session.AppState.BACKGROUND:
        action_type = StaffAction.ActionType.APP_BACKGROUNDED
    elif requested_state == Session.AppState.WARNING and previous_state != Session.AppState.WARNING:
        action_type = StaffAction.ActionType.IDLE_WARNING
    elif requested_state == Session.AppState.OFFLINE and previous_state != Session.AppState.OFFLINE:
        action_type = StaffAction.ActionType.MARKED_OFFLINE
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.WARNING:
        action_type = StaffAction.ActionType.IDLE_WARNING_ACKNOWLEDGED if interaction else None
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.OFFLINE and interaction:
        action_type = StaffAction.ActionType.RETURNED_ONLINE
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.BACKGROUND:
        action_type = StaffAction.ActionType.APP_FOREGROUNDED

    if action_type:
        _log_staff_action(
            staff,
            action_type,
            session=session,
            app_state=requested_state,
            metadata={"source": source, "interaction": interaction},
        )

    return session


def end_staff_session(staff, *, close_reason="manual"):
    session = get_open_session(staff)
    if not session:
        return None

    now = timezone.now()
    session = reconcile_session(session, now=now)
    if not session or not session.is_open:
        return None

    return _close_session(
        session,
        now,
        close_reason=close_reason,
        auto_generated=close_reason != "manual",
    )


def get_pending_status_call(staff):
    return (
        Call.objects.filter(
            staff=staff,
            status=Call.Status.STARTED,
            end_time__isnull=False,
        )
        .select_related("lead")
        .order_by("-end_time", "-start_time")
        .first()
    )


def build_staff_today_payload(staff):
    today, start, end = _today_range()
    now = timezone.now()
    sessions_today = Session.objects.filter(staff=staff, login_time__range=(start, end))
    calls_today = Call.objects.filter(staff=staff, start_time__range=(start, end))
    qualifying_calls = calls_today.filter(is_qualifying=True)
    assigned_leads = _visible_staff_lead_queryset(
        Lead.objects.filter(assigned_to=staff, status__in=ACTIVE_QUEUE_STATUSES),
        now=now,
    )
    open_session = get_open_session(staff, reconcile=True)
    latest_session = sessions_today.order_by("-login_time").first()
    learning_payload = build_staff_learning_payload(staff)
    pending_status_call = get_pending_status_call(staff)

    active_seconds = sessions_today.aggregate(total=Sum("active_seconds")).get("total") or 0
    calls_count = qualifying_calls.count()
    follow_up_count = assigned_leads.filter(status=Lead.Status.INTERESTED).count()
    callback_count = assigned_leads.filter(status=Lead.Status.CALL_BACK).count()
    converted_count = assigned_leads.filter(status=Lead.Status.CONVERTED).count()

    return {
        "today": today.isoformat(),
        "summary": {
            "active_seconds": active_seconds,
            "active_label": _format_hours(active_seconds),
            "calls_count": calls_count,
            "interested_count": follow_up_count,
            "converted_count": converted_count,
            "result_label": f"{follow_up_count} follow up / {callback_count} call back",
            "working_now": bool(open_session),
            "current_state": open_session.last_known_state if open_session else "stopped",
            "status_label": _session_status_label(open_session, latest_session=latest_session),
            "close_reason": latest_session.close_reason if latest_session else "",
            "pending_training_count": learning_payload["summary"]["pending_mandatory_count"],
            "training_required": learning_payload["summary"]["has_pending_mandatory"],
            "next_training_title": learning_payload["summary"]["next_required_title"],
            "pending_call_status_required": bool(pending_status_call),
            "pending_call_id": str(pending_status_call.id) if pending_status_call else "",
            "pending_call_lead_id": str(pending_status_call.lead_id) if pending_status_call else "",
            "pending_call_lead_name": pending_status_call.lead.name if pending_status_call else "",
            "pending_call_lead_phone": pending_status_call.lead.phone if pending_status_call else "",
        },
        "session": {
            "id": str(open_session.id),
            "is_open": open_session.is_open,
            "last_known_state": open_session.last_known_state,
            "active_seconds": open_session.active_seconds,
            "last_interaction_at": open_session.last_interaction_at.isoformat() if open_session.last_interaction_at else None,
            "warning_started_at": open_session.warning_started_at.isoformat() if open_session.warning_started_at else None,
            "close_reason": open_session.close_reason,
        }
        if open_session
        else None,
    }


def get_assigned_leads(staff):
    now = timezone.now()
    auto_allocate_leads(target_staff=staff)
    return _ordered_lead_queryset(
        _visible_staff_lead_queryset(
            Lead.objects.filter(assigned_to=staff, status__in=ACTIVE_QUEUE_STATUSES).select_related("assigned_to"),
            now=now,
        ),
        now=now,
    )


def search_staff_customer_history(staff, *, query="", limit=25):
    called_lead_ids = Call.objects.filter(staff=staff).values_list("lead_id", flat=True)
    queryset = Lead.objects.filter(Q(assigned_to=staff) | Q(id__in=called_lead_ids)).select_related("assigned_to")

    trimmed_query = (query or "").strip()
    if trimmed_query:
        normalized_phone = re.sub(r"\D+", "", trimmed_query)
        filters = Q(name__icontains=trimmed_query) | Q(phone__icontains=trimmed_query)
        if normalized_phone and normalized_phone != trimmed_query:
            filters |= Q(phone__icontains=normalized_phone)
        queryset = queryset.filter(filters).annotate(
            exact_match_priority=Case(
                When(phone__iexact=trimmed_query, then=Value(0)),
                When(name__iexact=trimmed_query, then=Value(0)),
                default=Value(1),
                output_field=IntegerField(),
            )
        ).order_by("exact_match_priority", "-last_contacted_at", "-updated_at", "-created_at")
    else:
        queryset = queryset.order_by("-last_contacted_at", "-updated_at", "-created_at")

    return queryset.distinct()[:limit]


def recover_staff_customer_lead(staff, lead, *, status, callback_window=""):
    has_staff_history = lead.assigned_to_id == staff.id or Call.objects.filter(staff=staff, lead=lead).exists()
    if not has_staff_history:
        raise PermissionError("This customer is not in your calling history.")

    if lead.status == Lead.Status.CONVERTED:
        raise ValueError("This customer is already marked as converted.")

    if lead.assigned_to_id and lead.assigned_to_id != staff.id and _is_active_queue_status(lead.status):
        raise ValueError("This customer is already active in another staff queue.")

    now = timezone.now()
    session = get_open_session(staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "customer_recovery"})

    resolved_callback_window = callback_window if status == Lead.Status.CALL_BACK else ""
    previous_owner = lead.assigned_to.name if lead.assigned_to and lead.assigned_to_id != staff.id else ""

    lead.assigned_to = staff
    lead.status = status
    lead.callback_window = resolved_callback_window
    lead.last_contacted_at = now
    lead.save(update_fields=["assigned_to", "status", "callback_window", "last_contacted_at", "updated_at"])

    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.CALL_STATUS_UPDATED,
        session=session,
        lead=lead,
        app_state=session.last_known_state if session else None,
        metadata={
            "source": "customer_recovery",
            "status": status,
            "callback_window": resolved_callback_window,
            "previous_owner": previous_owner,
        },
    )

    auto_allocate_leads(target_staff=staff, prioritized_lead_ids=[lead.id])
    return lead


def start_staff_call(staff, lead):
    now = timezone.now()
    _reconcile_open_calls(staff=staff, now=now)
    for lingering_call in (
        Call.objects.filter(staff=staff, end_time__isnull=True)
        .select_related("staff", "lead")
        .order_by("-start_time", "-created_at")
    ):
        _close_unresolved_call(lingering_call, reason="replaced_by_new_call")

    session = get_open_session(staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_start"})
    else:
        session, _ = start_staff_session(staff, source="auto_call_start")

    call = Call.objects.create(
        staff=staff,
        lead=lead,
        start_time=now,
        status=Call.Status.STARTED,
    )
    lead.last_contacted_at = now
    lead.save(update_fields=["last_contacted_at", "updated_at"])
    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.CALL_STARTED,
        session=session,
        call=call,
        lead=lead,
        app_state=session.last_known_state if session else None,
        metadata={"lead_name": lead.name},
    )
    return call


def retry_pending_staff_call(call):
    if call.end_time is None or call.status != Call.Status.STARTED:
        return call

    now = timezone.now()
    session = get_open_session(call.staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_retry"})
    else:
        session, _ = start_staff_session(call.staff, source="auto_call_retry")

    call.start_time = now
    call.end_time = None
    call.duration_seconds = 0
    call.is_qualifying = False
    call.callback_window = ""
    call.is_verified = False
    call.verification_source = ""
    call.save(
        update_fields=[
            "start_time",
            "end_time",
            "duration_seconds",
            "is_qualifying",
            "callback_window",
            "is_verified",
            "verification_source",
            "updated_at",
        ]
    )

    call.lead.last_contacted_at = now
    call.lead.save(update_fields=["last_contacted_at", "updated_at"])
    mark_staff_seen(call.staff, now)
    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_STARTED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={"lead_name": call.lead.name, "source": "retry_pending"},
    )
    return call


def end_staff_call(call, status=None, *, duration_seconds=None, ended_at=None, source="app", callback_window=""):
    if call.end_time:
        return call

    now = timezone.now()
    session = get_open_session(call.staff, reconcile=True)
    is_verified = (
        duration_seconds is not None
        and ended_at is not None
        and source in VERIFIED_CALL_SOURCES
    )

    if is_verified:
        resolved_end_time = min(ended_at, now + timedelta(seconds=VERIFIED_CALL_TIME_SKEW_SECONDS))
        if resolved_end_time < call.start_time:
            resolved_end_time = call.start_time
        max_verified_duration = max(
            0,
            int((resolved_end_time - call.start_time).total_seconds()) + VERIFIED_CALL_TIME_SKEW_SECONDS,
        )
        resolved_duration = min(max(0, int(duration_seconds)), max_verified_duration)
        call.start_time = resolved_end_time - timedelta(seconds=resolved_duration)
    else:
        resolved_end_time = ended_at or now
        if resolved_end_time < call.start_time:
            resolved_end_time = call.start_time
        resolved_duration = 0

    requested_status = status
    call.end_time = resolved_end_time
    call.duration_seconds = resolved_duration
    call.is_qualifying = call.duration_seconds >= SHORT_CALL_SECONDS
    call.is_verified = is_verified
    call.verification_source = source if is_verified else ""
    if session:
        _credit_call_duration_to_session(
            session,
            resolved_end_time,
            resolved_duration,
            metadata={
                "source": "call_end",
                "duration_seconds": resolved_duration,
            },
            mark_verified=is_verified,
        )
    if not call.is_qualifying and requested_status in {
        Call.Status.NO_ANSWER,
        Call.Status.NOT_INTERESTED,
    }:
        call.status = Call.Status.NO_ANSWER
        if requested_status == Call.Status.NOT_INTERESTED:
            call.status = Call.Status.NOT_INTERESTED
    else:
        call.status = Call.Status.INVALID_SHORT if not call.is_qualifying else call.status
    call.save(
        update_fields=[
            "start_time",
            "end_time",
            "duration_seconds",
            "is_qualifying",
            "is_verified",
            "verification_source",
            "status",
            "updated_at",
        ]
    )

    call.lead.last_contacted_at = call.end_time
    call.lead.save(update_fields=["last_contacted_at", "updated_at"])

    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_ENDED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={
            "duration_seconds": call.duration_seconds,
            "is_qualifying": call.is_qualifying,
            "is_verified": call.is_verified,
            "status": call.status,
            "source": source,
            "ended_at": call.end_time.isoformat(),
        },
    )

    if requested_status and (
        call.is_qualifying
        or requested_status in {Call.Status.NO_ANSWER, Call.Status.NOT_INTERESTED}
    ):
        update_staff_call_status(call, requested_status, callback_window)
    return call


def update_staff_call_status(call, status, callback_window=""):
    if call.status == Call.Status.INVALID_SHORT:
        return call

    now = timezone.now()
    session = get_open_session(call.staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_status"})

    resolved_callback_window = callback_window if status == Call.Status.CALL_BACK else ""
    call.status = status
    call.callback_window = resolved_callback_window
    call.save(update_fields=["status", "callback_window", "updated_at"])
    call.lead.status = status
    call.lead.callback_window = resolved_callback_window
    call.lead.last_contacted_at = call.end_time or now
    call.lead.save(update_fields=["status", "callback_window", "last_contacted_at", "updated_at"])

    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_STATUS_UPDATED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={"status": status, "callback_window": resolved_callback_window},
    )
    if status == Call.Status.CALL_BACK:
        auto_allocate_leads()
    elif status in TERMINAL_QUEUE_STATUSES:
        auto_allocate_leads(target_staff=call.staff)
    return call


def read_root_file(filename):
    return (settings.BASE_DIR / filename).read_text(encoding="utf-8")

