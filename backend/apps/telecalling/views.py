import json

from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from backend.apps.telecalling.models import Lead, Salary, Staff
from backend.apps.telecalling.serializers import LeadSerializer, SalarySerializer, StaffSerializer
from backend.apps.telecalling.services import build_dashboard_payload, read_root_file


@require_GET
def dashboard_page(request):
    payload = build_dashboard_payload()
    context = {
        "dashboard": payload["dashboard"],
        "live_staff": payload["live_staff"],
        "lead_rows": payload["lead_rows"],
        "salary_records": payload["salary_records"],
        "chart_payload": payload["chart_payload"],
    }
    return render(request, "heavenection_calltrack_web.html", context)


@require_GET
def pwa_manifest(request):
    return HttpResponse(read_root_file("heavenection-manifest.json"), content_type="application/manifest+json")


@require_GET
def pwa_service_worker(request):
    return HttpResponse(read_root_file("heavenection-sw.js"), content_type="application/javascript")


@api_view(["POST"])
@permission_classes([AllowAny])
def login_api(request):
    phone = request.data.get("phone", "").strip()
    password = request.data.get("password", "")
    try:
        staff = Staff.objects.get(phone=phone, is_active=True)
    except Staff.DoesNotExist:
        return Response({"detail": "Invalid credentials."}, status=400)

    if not staff.check_password(password):
        return Response({"detail": "Invalid credentials."}, status=400)

    refresh = RefreshToken.for_user(staff)
    return Response(
        {
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": StaffSerializer(staff).data,
        }
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def dashboard_data_api(request):
    return Response(build_dashboard_payload())


@api_view(["GET"])
@permission_classes([AllowAny])
def leads_api(request):
    queryset = Lead.objects.select_related("assigned_to").order_by("-updated_at")
    status_value = request.query_params.get("status")
    if status_value and status_value != "all":
        queryset = queryset.filter(status=status_value)
    return Response(LeadSerializer(queryset[:100], many=True).data)


@api_view(["GET"])
@permission_classes([AllowAny])
def live_staff_api(request):
    payload = build_dashboard_payload()
    return Response(payload["live_staff"])


@api_view(["GET"])
@permission_classes([AllowAny])
def salary_summary_api(request):
    queryset = Salary.objects.select_related("staff").order_by("-period_end", "staff__name")
    if queryset.exists():
        return Response(SalarySerializer(queryset[:50], many=True).data)
    return Response(build_dashboard_payload()["salary_records"])
