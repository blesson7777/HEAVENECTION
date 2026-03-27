from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from backend.apps.telecalling import views


urlpatterns = [
    path("auth/login/", views.login_api, name="api-login"),
    path("auth/me/", views.auth_me_api, name="api-me"),
    path("auth/logout/", views.logout_api, name="api-logout"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="api-refresh"),
    path("dashboard/", views.dashboard_data_api, name="api-dashboard"),
    path("leads/", views.leads_api, name="api-leads"),
    path("staff/live/", views.live_staff_api, name="api-live-staff"),
    path("staff/manage/", views.team_members_api, name="api-team-members"),
    path("staff/actions/", views.staff_actions_api, name="api-staff-actions"),
    path("salary/summary/", views.salary_summary_api, name="api-salary-summary"),
    path("staff/today-summary/", views.staff_today_summary_api, name="api-staff-today-summary"),
    path("staff/leads/", views.assigned_leads_api, name="api-staff-leads"),
    path("staff/session/start/", views.start_session_api, name="api-session-start"),
    path("staff/session/end/", views.end_session_api, name="api-session-end"),
    path("staff/heartbeat/", views.heartbeat_api, name="api-heartbeat"),
    path("staff/calls/start/", views.start_call_api, name="api-call-start"),
    path("staff/calls/<uuid:call_id>/end/", views.end_call_api, name="api-call-end"),
    path("staff/calls/<uuid:call_id>/status/", views.update_call_status_api, name="api-call-status"),
]
