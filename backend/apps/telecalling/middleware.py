from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.tokens import RefreshToken

from backend.apps.telecalling.auth import (
    ACCESS_COOKIE_NAME,
    REFRESH_COOKIE_NAME,
    get_staff_from_request,
    issue_tokens_for_user,
    set_auth_cookies,
)
from backend.apps.telecalling.models import Staff


class RefreshAuthCookiesMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        self._maybe_refresh_request_auth(request)
        response = self.get_response(request)

        refreshed_tokens = getattr(request, "_heavenection_refreshed_tokens", None)
        if refreshed_tokens:
            set_auth_cookies(response, refreshed_tokens["refresh_token"])
        return response

    def _maybe_refresh_request_auth(self, request):
        if get_staff_from_request(request) is not None:
            return

        refresh_cookie = request.COOKIES.get(REFRESH_COOKIE_NAME, "").strip()
        if not refresh_cookie:
            return

        try:
            refresh = RefreshToken(refresh_cookie)
            user_id = refresh.get(api_settings.USER_ID_CLAIM)
            token_session_key = str(refresh.get("session_key", "")).strip()
            if not user_id or not token_session_key:
                return
            user = Staff.objects.filter(pk=user_id, is_active=True).first()
            if not user or str(user.auth_session_key) != token_session_key:
                return
            refreshed_tokens = issue_tokens_for_user(user, rotate_session=False)
            request._heavenection_authenticated_user = user
            request._heavenection_refreshed_tokens = refreshed_tokens
            request.COOKIES[ACCESS_COOKIE_NAME] = refreshed_tokens["access"]
            request.COOKIES[REFRESH_COOKIE_NAME] = refreshed_tokens["refresh"]
        except (InvalidToken, TokenError):
            return
