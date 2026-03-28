from django.db.models import Count, Q
from django.http import HttpResponse
from django.contrib import messages
from django.shortcuts import redirect, render
from django.views.decorators.http import require_GET, require_http_methods
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from backend.apps.telecalling.auth import clear_auth_cookies, get_staff_from_request, issue_tokens_for_user, set_auth_cookies
from backend.apps.telecalling.models import AppRelease, Call, Lead, Salary, Staff, StaffAction, TrainingLesson
from backend.apps.telecalling.permissions import IsAdminStaff, IsCallingStaff
from backend.apps.telecalling.serializers import (
    AdminProfileSerializer,
    AdminProfileUpdateSerializer,
    CallSerializer,
    CompanyProfileSerializer,
    CompanyProfileUpdateSerializer,
    CallStatusSerializer,
    CreateAppReleaseSerializer,
    CreateLeadSerializer,
    CreateStaffSerializer,
    CreateTrainingLessonSerializer,
    EndCallSerializer,
    FollowupUpdateUploadSerializer,
    HeartbeatSerializer,
    LeadSerializer,
    LeadImportUploadSerializer,
    LoginSerializer,
    SalaryPaymentSerializer,
    SalarySettingsSerializer,
    SessionSerializer,
    StaffActionSerializer,
    StaffLeadRecoverySerializer,
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
    auto_allocate_leads,
    authenticate_staff,
    build_app_update_payload,
    build_call_detail_payload,
    build_dashboard_payload,
    build_developer_release_payload,
    build_followup_csv_response,
    build_followup_payload,
    build_learning_management_payload,
    build_lead_management_payload,
    build_recovery_lead_payload,
    build_salary_control_payload,
    build_salary_detail_payload,
    build_salary_page_payload,
    build_settings_payload,
    build_staff_profile_payload,
    build_staff_learning_payload,
    build_staff_today_payload,
    build_team_management_payload,
    build_work_hours_payload,
    complete_training_lesson,
    end_staff_call,
    end_staff_session,
    get_assigned_leads,
    get_pending_status_call,
    get_company_profile,
    publish_app_release,
    import_leads_from_upload,
    mark_staff_seen,
    read_root_file,
    record_staff_salary_payment,
    record_session_heartbeat,
    release_staff_queue,
    reactivate_oldest_recovery_leads,
    set_active_app_release,
    retry_pending_staff_call,
    send_salary_payment_acknowledgement,
    search_staff_customer_history,
    start_staff_call,
    start_staff_session,
    TrainingRequiredError,
    update_staff_call_status,
    update_followups_from_upload,
    recover_staff_customer_lead,
)


def _admin_web_context(request, current_user, *, active_page, page_title, page_heading, page_subtitle, extra_context=None):
    mark_staff_seen(current_user)
    company_profile = get_company_profile()
    context = {
        "admin_user": current_user,
        "company_profile": company_profile,
        "active_page": active_page,
        "page_title": page_title,
        "page_heading": page_heading,
        "page_subtitle": page_subtitle,
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


def _apply_staff_post_save_actions(staff, was_active):
    released_count = 0
    if was_active and not staff.is_active:
        end_staff_session(staff, close_reason="admin_disabled")
        released_count = release_staff_queue(staff)
        auto_allocate_leads()
    elif staff.is_active:
        auto_allocate_leads(target_staff=staff)
    return released_count


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
            {"submitted_phone": request.POST.get("phone", "").strip(), "company_profile": get_company_profile()},
            status=400,
        )

    staff = authenticate_staff(
        serializer.validated_data["phone"],
        serializer.validated_data["password"],
        required_role=Staff.Role.ADMIN,
    )
    if not staff:
        messages.error(request, "Invalid admin credentials.")
        return render(
            request,
            "admin_login.html",
            {"submitted_phone": serializer.validated_data["phone"], "company_profile": get_company_profile()},
            status=400,
        )

    mark_staff_seen(staff)
    tokens = issue_tokens_for_user(staff)
    response = redirect("dashboard")
    set_auth_cookies(response, tokens["refresh_token"])
    return response


@require_http_methods(["POST"])
def web_logout(request):
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
            {"submitted_phone": request.POST.get("phone", "").strip(), "company_profile": get_company_profile()},
            status=400,
        )

    staff = authenticate_staff(
        serializer.validated_data["phone"],
        serializer.validated_data["password"],
    )
    if not staff or staff.role not in {Staff.Role.ADMIN, Staff.Role.DEVELOPER}:
        messages.error(request, "Invalid developer credentials.")
        return render(
            request,
            "developer_login.html",
            {"submitted_phone": serializer.validated_data["phone"], "company_profile": get_company_profile()},
            status=400,
        )

    mark_staff_seen(staff)
    tokens = issue_tokens_for_user(staff)
    response = redirect("developer-releases-page")
    set_auth_cookies(response, tokens["refresh_token"])
    return response


@require_http_methods(["POST"])
def developer_logout(request):
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
        "published_at": "",
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
            serializer = CreateAppReleaseSerializer(
                data={
                    **release_form_data,
                    "apk_file": request.FILES.get("apk_file"),
                }
            )
            if serializer.is_valid():
                release = publish_app_release(created_by=current_user, validated_data=serializer.validated_data)
                messages.success(request, f"App release {release.version_name} published successfully.")
                return redirect("developer-releases-page")

            release_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the app release details and upload the APK again.")

    context = {
        "developer_user": current_user,
        "company_profile": get_company_profile(),
        "page_title": "Developer Releases",
        "release_form_data": release_form_data,
        "release_errors": release_errors,
        **build_developer_release_payload(),
    }
    return render(request, "developer_releases.html", context)

@require_GET
def dashboard_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    payload = build_dashboard_payload()
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

    payload = build_team_management_payload()
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
                    messages.success(request, f"{staff.name} is now enabled and can receive leads again.")
                else:
                    messages.success(
                        request,
                        f"{staff.name} is now disabled. {released_count} active leads were unassigned.",
                    )
                return redirect("staff-profile-page", staff_id=staff.id)

            staff_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Unable to change the staff account status.")
        else:
            password_value = request.POST.get("password", "")
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
                else:
                    messages.success(request, f"{staff.name}'s profile updated successfully.")
                return redirect("staff-profile-page", staff_id=staff.id)

            staff_errors = _normalize_errors(serializer.errors)
            messages.error(request, "Please correct the staff profile details and try again.")

    payload = build_staff_profile_payload(staff)
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


@require_http_methods(["GET", "POST"])
def leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        lead_action = request.POST.get("lead_action")
        if lead_action == "import":
            serializer = LeadImportUploadSerializer(data={"file": request.FILES.get("file")})
            if serializer.is_valid():
                try:
                    summary = import_leads_from_upload(serializer.validated_data["file"])
                except ValueError as error:
                    messages.error(request, str(error))
                else:
                    messages.success(
                        request,
                        "Lead import completed. "
                        f"Imported {summary['created_count']}, skipped {summary['skipped_count']}, "
                        f"assigned {summary['assigned_count']}, waiting {summary['remaining_unassigned_count']}.",
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

        messages.error(request, "Lead request could not be processed.")
        return redirect("leads-page")

    payload = build_lead_management_payload()
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

    context = _admin_web_context(
        request,
        current_user,
        active_page="followups",
        page_title="Follow-Up Queue",
        page_heading="Follow-Up Queue",
        page_subtitle="Review leads that need another touch and update them in bulk with CSV.",
        extra_context=build_followup_payload(),
    )
    return render(request, "admin_followups.html", context)


@require_http_methods(["GET", "POST"])
def recovery_leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    if request.method == "POST":
        recovery_action = request.POST.get("recovery_action")
        if recovery_action == "reactivate_oldest":
            raw_count = request.POST.get("readd_count", "").strip()
            scope = request.POST.get("readd_scope", "all").strip() or "all"
            try:
                readd_count = int(raw_count)
            except (TypeError, ValueError):
                messages.error(request, "Enter a valid number of leads to re-add.")
                return redirect("recovery-leads-page")

            if readd_count < 1:
                messages.error(request, "Re-add count must be at least 1.")
                return redirect("recovery-leads-page")

            summary = reactivate_oldest_recovery_leads(readd_count, scope=scope)
            if summary["reactivated_count"] == 0:
                messages.warning(request, "No rejected or no response leads were available for re-allocation.")
            else:
                messages.success(
                    request,
                    "Recovery leads re-added. "
                    f"Moved {summary['reactivated_count']} oldest leads back to the active queue, "
                    f"assigned {summary['assigned_count']}, waiting {summary['remaining_unassigned_count']}.",
                )
            return redirect("recovery-leads-page")

        messages.error(request, "Recovery lead request could not be processed.")
        return redirect("recovery-leads-page")

    context = _admin_web_context(
        request,
        current_user,
        active_page="recovery",
        page_title="Rejected & No Response",
        page_heading="Rejected & No Response",
        page_subtitle="Review closed leads oldest first and move the oldest rows back into the active queue when needed.",
        extra_context=build_recovery_lead_payload(),
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


@require_GET
def salary_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    context = _admin_web_context(
        request,
        current_user,
        active_page="salary",
        page_title="Salary Overview",
        page_heading="Salary Overview",
        page_subtitle="Review weekly and monthly payouts based on tracked working hours, calls, and bonuses.",
        extra_context=build_salary_page_payload(),
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
        if payment_action == "mark_weekly_paid":
            form_data = {
                "payout_cycle": "weekly",
                "period_start": request.POST.get("period_start"),
                "period_end": request.POST.get("period_end"),
                "paid_amount": request.POST.get("paid_amount"),
                "payment_method": Salary.PaymentMethod.BANK_TRANSFER,
                "payment_reference": request.POST.get("payment_reference", ""),
                "payment_note": request.POST.get("payment_note", ""),
            }
        elif payment_action == "mark_monthly_paid":
            form_data = {
                "payout_cycle": "monthly",
                "period_start": request.POST.get("period_start"),
                "period_end": request.POST.get("period_end"),
                "paid_amount": request.POST.get("paid_amount"),
                "payment_method": Salary.PaymentMethod.BANK_TRANSFER,
                "payment_reference": request.POST.get("payment_reference", ""),
                "payment_note": request.POST.get("payment_note", ""),
            }
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
            record, created = record_staff_salary_payment(staff, **serializer.validated_data)
            email_result = send_salary_payment_acknowledgement(record)
            messages.success(
                request,
                f"Salary marked as paid for {staff.name}. "
                f"Credited Rs. {float(record.paid_amount):,.2f} for {record.period_start} to {record.period_end}.",
            )
            if email_result["sent"]:
                messages.success(request, email_result["message"])
            else:
                messages.warning(request, email_result["message"])
            return redirect("salary-detail-page", staff_id=staff.id)

        payment_errors = _normalize_errors(serializer.errors)
        messages.error(request, "Please correct the salary payment details and try again.")

    payload = build_salary_detail_payload(staff)
    custom_form_data = {
        "payout_cycle": request.POST.get("payout_cycle", "custom"),
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
        page_subtitle="Review hourly payroll breakdowns, credit salary, and keep payment history in one place.",
        extra_context={
            **payload,
            "custom_payment_errors": payment_errors,
            "custom_form_data": custom_form_data,
        },
    )
    return render(request, "admin_salary_detail.html", context)


@require_GET
def salary_control_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    context = _admin_web_context(
        request,
        current_user,
        active_page="salary-control",
        page_title="Salary Control Panel",
        page_heading="Salary Control Panel",
        page_subtitle="Configure weekly, monthly, and hourly salary settings for each staff member.",
        extra_context=build_salary_control_payload(),
    )
    return render(request, "admin_salary_control.html", context)


@require_GET
def calls_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    context = _admin_web_context(
        request,
        current_user,
        active_page="calls",
        page_title="Call Details",
        page_heading="Call Details",
        page_subtitle="Review call history, outcomes, and duration after staff calling activity.",
        extra_context=build_call_detail_payload(),
    )
    return render(request, "admin_calls.html", context)


@require_GET
def working_hours_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

    context = _admin_web_context(
        request,
        current_user,
        active_page="hours",
        page_title="Working Hours",
        page_heading="Working Hours",
        page_subtitle="Track work sessions, active time, and the current state of each staff member.",
        extra_context=build_work_hours_payload(),
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
        serializer.validated_data["phone"],
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
def staff_app_update_api(request):
    raw_version_code = request.query_params.get("version_code", "0")
    try:
        current_version_code = int(raw_version_code)
    except (TypeError, ValueError):
        current_version_code = 0
    return Response(build_app_update_payload(request, current_version_code=current_version_code))

@api_view(["POST"])
def logout_api(request):
    response = Response({"detail": "Logged out."})
    clear_auth_cookies(response)
    return response


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def dashboard_data_api(request):
    return Response(build_dashboard_payload())


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
    if lead.assigned_to_id is None and lead.status in (
        Lead.Status.NEW,
        Lead.Status.CALL_BACK,
        Lead.Status.INTERESTED,
    ):
        auto_allocate_leads()
    return Response(LeadSerializer(lead).data, status=201)


@api_view(["POST"])
@permission_classes([IsAdminStaff])
def import_leads_api(request):
    serializer = LeadImportUploadSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    summary = import_leads_from_upload(serializer.validated_data["file"])
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

    serializer = UpdateLeadSerializer(lead, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    lead = serializer.save()
    auto_allocate_leads()
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
    payload = build_work_hours_payload()
    return Response(payload)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def live_staff_api(request):
    payload = build_dashboard_payload()
    return Response(payload["live_staff"])


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
    return Response(build_salary_page_payload()["salary_rows"])


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
            },
            status=409,
        )
    return Response(
        {
            "session": SessionSerializer(session).data,
            "summary": build_staff_today_payload(request.user)["summary"],
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
    try:
        lead = Lead.objects.get(id=serializer.validated_data["lead_id"], assigned_to=request.user)
    except Lead.DoesNotExist:
        return Response({"detail": "Lead not found."}, status=404)

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

    call = end_staff_call(
        call,
        serializer.validated_data.get("status"),
        duration_seconds=serializer.validated_data.get("duration_seconds"),
        ended_at=serializer.validated_data.get("ended_at"),
        source=serializer.validated_data.get("source", "app"),
        callback_window=serializer.validated_data.get("callback_window", ""),
    )
    return Response(CallSerializer(call).data)


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def retry_call_api(request, call_id):
    try:
        call = request.user.calls.select_related("lead", "staff").get(id=call_id)
    except request.user.calls.model.DoesNotExist:
        return Response({"detail": "Call not found."}, status=404)

    if call.status != Call.Status.STARTED or call.end_time is None:
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

    call = update_staff_call_status(
        call,
        serializer.validated_data["status"],
        serializer.validated_data.get("callback_window", ""),
    )
    return Response(CallSerializer(call).data)





