from django.http import HttpResponse
from django.contrib import messages
from django.shortcuts import redirect, render
from django.views.decorators.http import require_GET, require_http_methods
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from backend.apps.telecalling.auth import clear_auth_cookies, get_staff_from_request, issue_tokens_for_user, set_auth_cookies
from backend.apps.telecalling.models import Call, Lead, Salary, Staff, StaffAction
from backend.apps.telecalling.permissions import IsAdminStaff, IsCallingStaff
from backend.apps.telecalling.serializers import (
    CallSerializer,
    CallStatusSerializer,
    CreateLeadSerializer,
    CreateStaffSerializer,
    EndCallSerializer,
    HeartbeatSerializer,
    LeadSerializer,
    LoginSerializer,
    SalarySerializer,
    SessionSerializer,
    StaffActionSerializer,
    StaffSerializer,
    StartCallSerializer,
    UpdateLeadSerializer,
    UpdateStaffSerializer,
)
from backend.apps.telecalling.services import (
    authenticate_staff,
    build_call_detail_payload,
    build_dashboard_payload,
    build_lead_management_payload,
    build_staff_today_payload,
    build_team_management_payload,
    build_work_hours_payload,
    end_staff_call,
    end_staff_session,
    get_assigned_leads,
    mark_staff_seen,
    read_root_file,
    record_session_heartbeat,
    start_staff_call,
    start_staff_session,
    update_staff_call_status,
)


def _admin_web_context(request, current_user, *, active_page, page_title, page_heading, page_subtitle, extra_context=None):
    mark_staff_seen(current_user)
    context = {
        "admin_user": current_user,
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


@require_http_methods(["GET", "POST"])
def web_login_page(request):
    current_user = get_staff_from_request(request)
    if current_user and current_user.role == Staff.Role.ADMIN:
        return redirect("dashboard")

    if request.method == "GET":
        return render(request, "admin_login.html")

    serializer = LoginSerializer(data=request.POST)
    if not serializer.is_valid():
        return render(
            request,
            "admin_login.html",
            {"submitted_phone": request.POST.get("phone", "").strip()},
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
            {"submitted_phone": serializer.validated_data["phone"]},
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


@require_GET
def leads_page(request):
    current_user = _get_admin_user_or_redirect(request)
    if not current_user:
        return redirect("web-login")

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


@api_view(["POST"])
def logout_api(request):
    response = Response({"detail": "Logged out."})
    clear_auth_cookies(response)
    return response


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def dashboard_data_api(request):
    return Response(build_dashboard_payload())


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
    return Response(LeadSerializer(lead).data, status=201)


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
        lead.delete()
        return Response(status=204)

    serializer = UpdateLeadSerializer(lead, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    lead = serializer.save()
    return Response(LeadSerializer(lead).data)


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
        return Response(status=204)

    serializer = UpdateStaffSerializer(staff, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    staff = serializer.save()
    return Response(StaffSerializer(staff).data)


@api_view(["GET"])
@permission_classes([IsAdminStaff])
def salary_summary_api(request):
    queryset = Salary.objects.select_related("staff").order_by("-period_end", "staff__name")
    if queryset.exists():
        return Response(SalarySerializer(queryset[:50], many=True).data)
    return Response(build_dashboard_payload()["salary_records"])


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


@api_view(["POST"])
@permission_classes([IsCallingStaff])
def start_session_api(request):
    session, created = start_staff_session(request.user)
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
    try:
        lead = Lead.objects.get(id=serializer.validated_data["lead_id"], assigned_to=request.user)
    except Lead.DoesNotExist:
        return Response({"detail": "Lead not found."}, status=404)

    call = start_staff_call(request.user, lead)
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
    )
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

    call = update_staff_call_status(call, serializer.validated_data["status"])
    return Response(CallSerializer(call).data)
