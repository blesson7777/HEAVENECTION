from datetime import timedelta
import uuid

from django.conf import settings
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

from backend.apps.telecalling.models import Staff


ACCESS_COOKIE_NAME = "heavenection_access"
REFRESH_COOKIE_NAME = "heavenection_refresh"


class CookieJWTAuthentication(JWTAuthentication):
    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        token_session_key = str(validated_token.get("session_key", "")).strip()
        if token_session_key and str(user.auth_session_key) != token_session_key:
            raise InvalidToken("This sign-in is no longer active.")
        return user

    def authenticate(self, request):
        header = self.get_header(request)
        if header is not None:
            return super().authenticate(request)

        raw_token = request.COOKIES.get(ACCESS_COOKIE_NAME)
        if not raw_token:
            return None

        validated_token = self.get_validated_token(raw_token)
        return self.get_user(validated_token), validated_token


def rotate_auth_session(user):
    user.auth_session_key = uuid.uuid4()
    user.save(update_fields=["auth_session_key"])
    return user.auth_session_key


def issue_tokens_for_user(user, *, rotate_session=True):
    if rotate_session:
        rotate_auth_session(user)
    refresh = RefreshToken.for_user(user)
    refresh["session_key"] = str(user.auth_session_key)
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


class SessionAwareTokenRefreshSerializer(TokenRefreshSerializer):
    default_error_messages = {
        "no_active_account": "This sign-in is no longer active.",
    }

    def validate(self, attrs):
        refresh = RefreshToken(attrs["refresh"])
        user_id = refresh.get(api_settings.USER_ID_CLAIM)
        token_session_key = str(refresh.get("session_key", "")).strip()
        if not user_id or not token_session_key:
            raise InvalidToken(self.error_messages["no_active_account"])

        try:
            user = Staff.objects.get(pk=user_id, is_active=True)
        except Staff.DoesNotExist as error:
            raise InvalidToken(self.error_messages["no_active_account"]) from error

        if str(user.auth_session_key) != token_session_key:
            raise InvalidToken(self.error_messages["no_active_account"])

        return super().validate(attrs)
