from rest_framework.permissions import BasePermission

from backend.apps.telecalling.models import Staff


class IsAdminStaff(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and user.is_active
            and user.role == Staff.Role.ADMIN
        )


class IsCallingStaff(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and user.is_active
            and user.role == Staff.Role.STAFF
        )
