from datetime import timedelta

from django.conf import settings
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError


ACCESS_COOKIE_NAME = "heavenection_access"
REFRESH_COOKIE_NAME = "heavenection_refresh"


class CookieJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        header = self.get_header(request)
        if header is not None:
            return super().authenticate(request)

        raw_token = request.COOKIES.get(ACCESS_COOKIE_NAME)
        if not raw_token:
            return None

        validated_token = self.get_validated_token(raw_token)
        return self.get_user(validated_token), validated_token


def issue_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {
        "access": str(refresh.access_token),
        "refresh": str(refresh),
        "refresh_token": refresh,
    }


def set_auth_cookies(response, refresh_token):
    access_token = str(refresh_token.access_token)
    access_lifetime = settings.SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"]
    refresh_lifetime = settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"]
    secure_cookie = not settings.DEBUG

    response.set_cookie(
        ACCESS_COOKIE_NAME,
        access_token,
        max_age=int(access_lifetime.total_seconds()),
        httponly=True,
        secure=secure_cookie,
        samesite="Lax",
    )
    response.set_cookie(
        REFRESH_COOKIE_NAME,
        str(refresh_token),
        max_age=int(refresh_lifetime.total_seconds()),
        httponly=True,
        secure=secure_cookie,
        samesite="Lax",
    )


def clear_auth_cookies(response):
    response.delete_cookie(ACCESS_COOKIE_NAME)
    response.delete_cookie(REFRESH_COOKIE_NAME)


def get_staff_from_request(request):
    raw_token = request.COOKIES.get(ACCESS_COOKIE_NAME)
    if not raw_token:
        return None

    auth = CookieJWTAuthentication()
    try:
        validated_token = auth.get_validated_token(raw_token)
        return auth.get_user(validated_token)
    except (InvalidToken, TokenError):
        return None
