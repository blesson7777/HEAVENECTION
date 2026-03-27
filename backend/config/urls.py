from django.conf import settings
from django.conf.urls.static import static
from django.urls import include, path

from backend.apps.telecalling import views


urlpatterns = [
    path("login/", views.web_login_page, name="web-login"),
    path("logout/", views.web_logout, name="web-logout"),
    path("", views.dashboard_page, name="dashboard"),
    path("settings/", views.settings_page, name="settings-page"),
    path("staff/", views.staff_page, name="staff-page"),
    path("leads/", views.leads_page, name="leads-page"),
    path("calls/", views.calls_page, name="calls-page"),
    path("working-hours/", views.working_hours_page, name="working-hours-page"),
    path("manifest.webmanifest", views.pwa_manifest, name="pwa-manifest"),
    path("service-worker.js", views.pwa_service_worker, name="pwa-service-worker"),
    path("api/", include("backend.apps.telecalling.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
