from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from backend.apps.telecalling import views


urlpatterns = [
    path("auth/login/", views.login_api, name="api-login"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="api-refresh"),
    path("dashboard/", views.dashboard_data_api, name="api-dashboard"),
    path("leads/", views.leads_api, name="api-leads"),
    path("staff/live/", views.live_staff_api, name="api-live-staff"),
    path("salary/summary/", views.salary_summary_api, name="api-salary-summary"),
]
