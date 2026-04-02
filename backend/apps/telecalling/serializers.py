from pathlib import Path

from django.db.models import Sum
from django.urls import reverse
from rest_framework import serializers
from django.utils import timezone

from backend.apps.telecalling.models import (
    AppRelease,
    Call,
    CompanyProfile,
    Lead,
    Salary,
    Session,
    Staff,
    StaffAction,
    TrainingLesson,
)


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254, required=False, allow_blank=False)
    phone = serializers.CharField(max_length=254, required=False, allow_blank=False)
    password = serializers.CharField()

    def validate(self, attrs):
        identifier = (attrs.get("identifier") or attrs.get("phone") or "").strip()
        if not identifier:
            raise serializers.ValidationError(
                {"identifier": "Enter your email address or phone number."}
            )
        attrs["identifier"] = identifier
        return attrs


def _validate_unique_email(value, *, instance=None):
    email = value.strip().lower()
    if not email:
        return ""
    queryset = Staff.objects.filter(email__iexact=email)
    if instance:
        queryset = queryset.exclude(pk=instance.pk)
    if queryset.exists():
        raise serializers.ValidationError("Email address already exists.")
    return email


_SUPPORTED_DOCUMENT_IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".heic",
    ".heif",
}


def _validate_document_image(value, *, field_label):
    if not value:
        return value

    content_type = (getattr(value, "content_type", "") or "").lower().strip()
    file_extension = Path(getattr(value, "name", "")).suffix.lower()
    has_supported_extension = file_extension in _SUPPORTED_DOCUMENT_IMAGE_EXTENSIONS
    is_supported_content_type = content_type.startswith("image/")
    is_generic_binary_upload = content_type in {"", "application/octet-stream"}

    if not is_supported_content_type and not (is_generic_binary_upload and has_supported_extension):
        raise serializers.ValidationError(
            f"Upload a JPG, PNG, WEBP, or HEIC image file for the {field_label}."
        )

    if getattr(value, "size", 0) > 10 * 1024 * 1024:
        raise serializers.ValidationError(
            f"{field_label.capitalize()} image size must be 10 MB or smaller."
        )

    return value


class HeartbeatSerializer(serializers.Serializer):
    state = serializers.ChoiceField(
        choices=Session.AppState.choices,
        default=Session.AppState.FOREGROUND,
    )
    interaction = serializers.BooleanField(required=False, default=False)
    source = serializers.CharField(max_length=50, required=False, default="timer")


class StartCallSerializer(serializers.Serializer):
    lead_id = serializers.UUIDField()


class EndCallSerializer(serializers.Serializer):
    status = serializers.ChoiceField(
        choices=[
            Call.Status.INTERESTED,
            Call.Status.NOT_INTERESTED,
            Call.Status.NO_ANSWER,
            Call.Status.CALL_BACK,
            Call.Status.CONVERTED,
        ],
        required=False,
    )
    callback_window = serializers.ChoiceField(
        choices=Lead.CallbackWindow.choices,
        required=False,
        allow_blank=False,
    )
    duration_seconds = serializers.IntegerField(min_value=0, required=False)
    ended_at = serializers.DateTimeField(required=False)
    source = serializers.CharField(max_length=50, required=False, default="app")

    def validate(self, attrs):
        if attrs.get("status") == Call.Status.CALL_BACK and not attrs.get("callback_window"):
            raise serializers.ValidationError(
                {"callback_window": "Select Noon, Evening, or Night for a callback."}
            )
        if ("duration_seconds" in attrs) != ("ended_at" in attrs):
            raise serializers.ValidationError(
                "Provide both duration and ended time for a verified call-log sync."
            )
        return attrs


class CallStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(
        choices=[
            Call.Status.INTERESTED,
            Call.Status.NOT_INTERESTED,
            Call.Status.NO_ANSWER,
            Call.Status.CALL_BACK,
            Call.Status.CONVERTED,
        ]
    )
    callback_window = serializers.ChoiceField(
        choices=Lead.CallbackWindow.choices,
        required=False,
        allow_blank=False,
    )

    def validate(self, attrs):
        if attrs.get("status") == Call.Status.CALL_BACK and not attrs.get("callback_window"):
            raise serializers.ValidationError(
                {"callback_window": "Select Noon, Evening, or Night for a callback."}
            )
        return attrs


class StaffLeadRecoverySerializer(serializers.Serializer):
    status = serializers.ChoiceField(
        choices=[
            Lead.Status.INTERESTED,
            Lead.Status.CALL_BACK,
        ]
    )
    callback_window = serializers.ChoiceField(
        choices=Lead.CallbackWindow.choices,
        required=False,
        allow_blank=False,
    )

    def validate(self, attrs):
        if attrs.get("status") == Lead.Status.CALL_BACK and not attrs.get("callback_window"):
            raise serializers.ValidationError(
                {"callback_window": "Select Noon, Evening, or Night for a callback."}
            )
        return attrs


class StaffSerializer(serializers.ModelSerializer):
    compensation_type_label = serializers.CharField(source="get_compensation_type_display", read_only=True)

    class Meta:
        model = Staff
        fields = (
            "id",
            "name",
            "phone",
            "role",
            "is_active",
            "compensation_type",
            "compensation_type_label",
            "hourly_rate",
            "weekly_salary",
            "monthly_salary",
            "target_hours_per_week",
            "target_hours_per_month",
            "call_rate",
            "bonus_per_conversion",
            "last_seen_at",
        )


class StaffProfileSerializer(serializers.ModelSerializer):
    role_label = serializers.CharField(source="get_role_display", read_only=True)
    aadhar_photo_url = serializers.SerializerMethodField()
    aadhar_photo_name = serializers.SerializerMethodField()
    passbook_photo_url = serializers.SerializerMethodField()
    passbook_photo_name = serializers.SerializerMethodField()
    salary_summary = serializers.SerializerMethodField()
    salary_history = serializers.SerializerMethodField()

    class Meta:
        model = Staff
        fields = (
            "id",
            "name",
            "phone",
            "email",
            "role",
            "role_label",
            "is_active",
            "bank_account_name",
            "bank_name",
            "bank_account_number",
            "bank_ifsc_code",
            "aadhar_number",
            "aadhar_photo_url",
            "aadhar_photo_name",
            "passbook_photo_url",
            "passbook_photo_name",
            "last_seen_at",
            "salary_summary",
            "salary_history",
        )

    def get_aadhar_photo_url(self, obj):
        request = self.context.get("request")
        if not obj.aadhar_photo:
            return ""
        url = reverse("api-staff-profile-document", args=["aadhar"])
        if request:
            return request.build_absolute_uri(url)
        return url

    def get_passbook_photo_url(self, obj):
        request = self.context.get("request")
        if not obj.passbook_photo:
            return ""
        url = reverse("api-staff-profile-document", args=["passbook"])
        if request:
            return request.build_absolute_uri(url)
        return url

    def get_aadhar_photo_name(self, obj):
        if not obj.aadhar_photo:
            return ""
        return Path(obj.aadhar_photo.name).name

    def get_passbook_photo_name(self, obj):
        if not obj.passbook_photo:
            return ""
        return Path(obj.passbook_photo.name).name

    def get_salary_history(self, obj):
        records = obj.salary_records.filter(is_paid=True).order_by("-paid_at", "-period_end")[:20]
        return SalaryHistorySerializer(records, many=True).data

    def get_salary_summary(self, obj):
        totals = obj.salary_records.filter(is_paid=True).aggregate(
            total_hours=Sum("total_hours"),
            total_earned=Sum("final_salary"),
            total_paid=Sum("paid_amount"),
        )
        latest_record = obj.salary_records.filter(is_paid=True).order_by("-paid_at", "-period_end").first()
        total_hours = totals.get("total_hours") or 0
        total_earned = totals.get("total_earned") or 0
        total_paid = totals.get("total_paid") or 0
        return {
            "total_working_hours": float(total_hours),
            "total_working_hours_label": f"{float(total_hours):,.1f}h",
            "total_earned_amount": float(total_earned),
            "total_earned_amount_label": f"Rs. {float(total_earned):,.2f}",
            "total_paid_amount": float(total_paid),
            "total_paid_amount_label": f"Rs. {float(total_paid):,.2f}",
            "latest_transaction_id": latest_record.payment_reference if latest_record and latest_record.payment_reference else "",
            "latest_paid_at_label": timezone.localtime(latest_record.paid_at).strftime("%d %b %Y, %I:%M %p")
            if latest_record and latest_record.paid_at
            else "--",
        }


class StaffProfileUpdateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150, required=False)
    phone = serializers.CharField(max_length=20, required=False)
    email = serializers.EmailField(required=False, allow_blank=True)
    bank_account_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    bank_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    bank_account_number = serializers.CharField(max_length=50, required=False, allow_blank=True)
    bank_ifsc_code = serializers.CharField(max_length=30, required=False, allow_blank=True)
    aadhar_number = serializers.CharField(max_length=20, required=False, allow_blank=True)
    aadhar_photo = serializers.FileField(required=False, allow_null=True)
    remove_aadhar_photo = serializers.BooleanField(required=False, default=False, write_only=True)
    passbook_photo = serializers.FileField(required=False, allow_null=True)
    remove_passbook_photo = serializers.BooleanField(required=False, default=False, write_only=True)
    current_password = serializers.CharField(required=False, allow_blank=False, write_only=True)
    new_password = serializers.CharField(min_length=6, required=False, allow_blank=False, write_only=True)

    def validate_phone(self, value):
        phone = value.strip()
        instance = getattr(self, "instance", None)
        queryset = Staff.objects.filter(phone=phone)
        if instance:
            queryset = queryset.exclude(pk=instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("Phone number already exists.")
        return phone

    def validate_email(self, value):
        return _validate_unique_email(value, instance=getattr(self, "instance", None))

    def validate_aadhar_number(self, value):
        normalized = "".join(char for char in value if char.isdigit())
        if normalized and len(normalized) != 12:
            raise serializers.ValidationError("Enter a valid 12-digit Aadhaar number.")
        return normalized

    def validate_aadhar_photo(self, value):
        return _validate_document_image(value, field_label="Aadhaar photo")

    def validate_passbook_photo(self, value):
        return _validate_document_image(value, field_label="passbook")

    def validate(self, attrs):
        current_password = attrs.get("current_password")
        new_password = attrs.get("new_password")
        instance = getattr(self, "instance", None)

        if new_password and not current_password:
            raise serializers.ValidationError(
                {"current_password": "Enter your current password to set a new password."}
            )
        if current_password and instance and not instance.check_password(current_password):
            raise serializers.ValidationError(
                {"current_password": "Current password is incorrect."}
            )
        return attrs

    def update(self, instance, validated_data):
        remove_aadhar_photo = validated_data.pop("remove_aadhar_photo", False)
        new_photo = validated_data.pop("aadhar_photo", None)
        remove_passbook_photo = validated_data.pop("remove_passbook_photo", False)
        new_passbook_photo = validated_data.pop("passbook_photo", None)
        validated_data.pop("current_password", None)
        new_password = validated_data.pop("new_password", None)
        previous_photo = instance.aadhar_photo if instance.aadhar_photo else None
        previous_passbook_photo = instance.passbook_photo if instance.passbook_photo else None

        for field, value in validated_data.items():
            setattr(instance, field, value)

        if remove_aadhar_photo:
            instance.aadhar_photo = None
        elif new_photo is not None:
            instance.aadhar_photo = new_photo

        if remove_passbook_photo:
            instance.passbook_photo = None
        elif new_passbook_photo is not None:
            instance.passbook_photo = new_passbook_photo

        if new_password:
            instance.set_password(new_password)

        instance.save()

        if remove_aadhar_photo and previous_photo:
            previous_photo.delete(save=False)
        elif new_photo is not None and previous_photo and previous_photo.name != instance.aadhar_photo.name:
            previous_photo.delete(save=False)

        if remove_passbook_photo and previous_passbook_photo:
            previous_passbook_photo.delete(save=False)
        elif (
            new_passbook_photo is not None
            and previous_passbook_photo
            and previous_passbook_photo.name != instance.passbook_photo.name
        ):
            previous_passbook_photo.delete(save=False)
        return instance


class CreateStaffSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(min_length=6, write_only=True)
    compensation_type = serializers.ChoiceField(
        choices=Staff.CompensationType.choices,
        required=False,
        default=Staff.CompensationType.HOURLY,
    )
    hourly_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    weekly_salary = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    monthly_salary = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    target_hours_per_week = serializers.DecimalField(max_digits=6, decimal_places=2, required=False)
    target_hours_per_month = serializers.DecimalField(max_digits=6, decimal_places=2, required=False)
    call_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    bonus_per_conversion = serializers.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
    )
    is_active = serializers.BooleanField(required=False, default=True)

    def validate_phone(self, value):
        phone = value.strip()
        if Staff.objects.filter(phone=phone).exists():
            raise serializers.ValidationError("Phone number already exists.")
        return phone

    def validate(self, attrs):
        return attrs

    def create(self, validated_data):
        password = validated_data.pop("password")
        return Staff.objects.create_user(
            password=password,
            role=Staff.Role.STAFF,
            **validated_data,
        )


class UpdateStaffSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150, required=False)
    phone = serializers.CharField(max_length=20, required=False)
    email = serializers.EmailField(required=False, allow_blank=True)
    password = serializers.CharField(min_length=6, write_only=True, required=False, allow_blank=False)
    compensation_type = serializers.ChoiceField(choices=Staff.CompensationType.choices, required=False)
    hourly_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    weekly_salary = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    monthly_salary = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    target_hours_per_week = serializers.DecimalField(max_digits=6, decimal_places=2, required=False)
    target_hours_per_month = serializers.DecimalField(max_digits=6, decimal_places=2, required=False)
    call_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    bonus_per_conversion = serializers.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
    )
    bank_account_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    bank_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    bank_account_number = serializers.CharField(max_length=50, required=False, allow_blank=True)
    bank_ifsc_code = serializers.CharField(max_length=30, required=False, allow_blank=True)
    aadhar_number = serializers.CharField(max_length=20, required=False, allow_blank=True)
    aadhar_photo = serializers.FileField(required=False, allow_null=True)
    remove_aadhar_photo = serializers.BooleanField(required=False, default=False, write_only=True)
    passbook_photo = serializers.FileField(required=False, allow_null=True)
    remove_passbook_photo = serializers.BooleanField(required=False, default=False, write_only=True)
    is_active = serializers.BooleanField(required=False)

    def validate_phone(self, value):
        phone = value.strip()
        instance = getattr(self, "instance", None)
        queryset = Staff.objects.filter(phone=phone)
        if instance:
            queryset = queryset.exclude(pk=instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("Phone number already exists.")
        return phone

    def validate(self, attrs):
        return attrs

    def validate_aadhar_number(self, value):
        normalized = "".join(char for char in value if char.isdigit())
        if normalized and len(normalized) != 12:
            raise serializers.ValidationError("Enter a valid 12-digit Aadhaar number.")
        return normalized

    def validate_aadhar_photo(self, value):
        return _validate_document_image(value, field_label="Aadhaar photo")

    def validate_passbook_photo(self, value):
        return _validate_document_image(value, field_label="passbook")

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        remove_aadhar_photo = validated_data.pop("remove_aadhar_photo", False)
        new_photo = validated_data.pop("aadhar_photo", None)
        remove_passbook_photo = validated_data.pop("remove_passbook_photo", False)
        new_passbook_photo = validated_data.pop("passbook_photo", None)
        previous_photo = instance.aadhar_photo if instance.aadhar_photo else None
        previous_passbook_photo = instance.passbook_photo if instance.passbook_photo else None
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if remove_aadhar_photo:
            instance.aadhar_photo = None
        elif new_photo is not None:
            instance.aadhar_photo = new_photo
        if remove_passbook_photo:
            instance.passbook_photo = None
        elif new_passbook_photo is not None:
            instance.passbook_photo = new_passbook_photo
        if password:
            instance.set_password(password)
        instance.save()
        if remove_aadhar_photo and previous_photo:
            previous_photo.delete(save=False)
        elif new_photo is not None and previous_photo and previous_photo.name != instance.aadhar_photo.name:
            previous_photo.delete(save=False)
        if remove_passbook_photo and previous_passbook_photo:
            previous_passbook_photo.delete(save=False)
        elif (
            new_passbook_photo is not None
            and previous_passbook_photo
            and previous_passbook_photo.name != instance.passbook_photo.name
        ):
            previous_passbook_photo.delete(save=False)
        return instance


class SalarySettingsSerializer(serializers.ModelSerializer):
    compensation_type_label = serializers.CharField(source="get_compensation_type_display", read_only=True)

    class Meta:
        model = Staff
        fields = (
            "id",
            "name",
            "phone",
            "compensation_type",
            "compensation_type_label",
            "hourly_rate",
            "weekly_salary",
            "monthly_salary",
            "target_hours_per_week",
            "target_hours_per_month",
            "call_rate",
            "bonus_per_conversion",
            "is_active",
        )


class AdminProfileSerializer(serializers.ModelSerializer):
    role_label = serializers.CharField(source="get_role_display", read_only=True)

    class Meta:
        model = Staff
        fields = (
            "id",
            "name",
            "phone",
            "role",
            "role_label",
            "is_active",
            "last_seen_at",
        )


class AdminProfileUpdateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150, required=False)
    phone = serializers.CharField(max_length=20, required=False)
    password = serializers.CharField(min_length=6, write_only=True, required=False, allow_blank=False)

    def validate_phone(self, value):
        phone = value.strip()
        instance = getattr(self, "instance", None)
        queryset = Staff.objects.filter(phone=phone)
        if instance:
            queryset = queryset.exclude(pk=instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("Phone number already exists.")
        return phone

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
        instance.save()
        return instance


class CompanyProfileSerializer(serializers.ModelSerializer):
    logo_url = serializers.SerializerMethodField()

    class Meta:
        model = CompanyProfile
        fields = (
            "id",
            "company_name",
            "legal_name",
            "company_email",
            "company_phone",
            "support_phone",
            "website",
            "address_line_1",
            "address_line_2",
            "city",
            "state",
            "postal_code",
            "country",
            "tax_identifier",
            "lead_queue_target_per_staff",
            "description",
            "logo",
            "logo_url",
            "updated_at",
        )

    def get_logo_url(self, obj):
        request = self.context.get("request")
        if not obj.logo:
            return ""
        if request:
            return request.build_absolute_uri(obj.logo.url)
        return obj.logo.url


class CompanyProfileUpdateSerializer(serializers.ModelSerializer):
    remove_logo = serializers.BooleanField(required=False, default=False, write_only=True)

    class Meta:
        model = CompanyProfile
        fields = (
            "company_name",
            "legal_name",
            "company_email",
            "company_phone",
            "support_phone",
            "website",
            "address_line_1",
            "address_line_2",
            "city",
            "state",
            "postal_code",
            "country",
            "tax_identifier",
            "lead_queue_target_per_staff",
            "description",
            "logo",
            "remove_logo",
        )

    def validate_logo(self, value):
        if not value:
            return value
        content_type = getattr(value, "content_type", "")
        if content_type and not content_type.startswith("image/"):
            raise serializers.ValidationError("Upload an image file for the company logo.")
        if getattr(value, "size", 0) > 5 * 1024 * 1024:
            raise serializers.ValidationError("Logo size must be 5 MB or smaller.")
        return value

    def update(self, instance, validated_data):
        remove_logo = validated_data.pop("remove_logo", False)
        new_logo = validated_data.get("logo")
        previous_logo = instance.logo if instance.logo else None

        for field, value in validated_data.items():
            setattr(instance, field, value)

        if remove_logo:
            instance.logo = None

        instance.save()

        if remove_logo and previous_logo:
            previous_logo.delete(save=False)
        elif new_logo and previous_logo and previous_logo.name != instance.logo.name:
            previous_logo.delete(save=False)
        return instance


class LeadSerializer(serializers.ModelSerializer):
    assigned_to_name = serializers.CharField(source="assigned_to.name", read_only=True)
    status_label = serializers.CharField(source="get_status_display", read_only=True)
    callback_window_label = serializers.CharField(
        source="get_callback_window_display",
        read_only=True,
    )

    class Meta:
        model = Lead
        fields = (
            "id",
            "name",
            "phone",
            "status",
            "status_label",
            "callback_window",
            "callback_window_label",
            "assigned_to",
            "assigned_to_name",
            "notes",
            "last_contacted_at",
            "updated_at",
        )


class CreateLeadSerializer(serializers.ModelSerializer):
    assigned_to = serializers.PrimaryKeyRelatedField(
        queryset=Staff.objects.filter(role=Staff.Role.STAFF, is_active=True),
        required=False,
        allow_null=True,
    )

    class Meta:
        model = Lead
        fields = (
            "id",
            "name",
            "phone",
            "status",
            "callback_window",
            "assigned_to",
            "notes",
        )

    def validate(self, attrs):
        if attrs.get("status") == Lead.Status.CALL_BACK and not attrs.get("callback_window"):
            raise serializers.ValidationError(
                {"callback_window": "Select Noon, Evening, or Night for callback leads."}
            )
        if attrs.get("status") != Lead.Status.CALL_BACK:
            attrs["callback_window"] = ""
        return attrs


class UpdateLeadSerializer(serializers.ModelSerializer):
    assigned_to = serializers.PrimaryKeyRelatedField(
        queryset=Staff.objects.filter(role=Staff.Role.STAFF, is_active=True),
        required=False,
        allow_null=True,
    )

    class Meta:
        model = Lead
        fields = (
            "name",
            "phone",
            "status",
            "callback_window",
            "assigned_to",
            "notes",
        )

    def validate(self, attrs):
        instance = getattr(self, "instance", None)
        status = attrs.get("status", getattr(instance, "status", Lead.Status.NEW))
        callback_window = attrs.get(
            "callback_window",
            getattr(instance, "callback_window", ""),
        )
        if status == Lead.Status.CALL_BACK and not callback_window:
            raise serializers.ValidationError(
                {"callback_window": "Select Noon, Evening, or Night for callback leads."}
            )
        if status != Lead.Status.CALL_BACK:
            attrs["callback_window"] = ""
        return attrs


class LeadImportUploadSerializer(serializers.Serializer):
    file = serializers.FileField()

    def validate_file(self, value):
        file_name = str(getattr(value, "name", "")).lower()
        if not file_name.endswith((".csv", ".xlsx", ".xlsm")):
            raise serializers.ValidationError("Upload a CSV or Excel file.")
        return value


class FollowupUpdateUploadSerializer(serializers.Serializer):
    file = serializers.FileField()

    def validate_file(self, value):
        file_name = str(getattr(value, "name", "")).lower()
        if not file_name.endswith((".csv", ".xlsx", ".xlsm")):
            raise serializers.ValidationError("Upload a CSV or Excel file for follow-up updates.")
        return value


class SessionSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)

    class Meta:
        model = Session
        fields = (
            "id",
            "staff",
            "staff_name",
            "login_time",
            "logout_time",
            "active_seconds",
            "last_heartbeat_at",
            "last_interaction_at",
            "state_changed_at",
            "warning_started_at",
            "heartbeat_count",
            "last_known_state",
            "last_verified_call_at",
            "close_reason",
            "is_open",
        )


class StaffActionSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)
    lead_name = serializers.CharField(source="lead.name", read_only=True)

    class Meta:
        model = StaffAction
        fields = (
            "id",
            "staff",
            "staff_name",
            "session",
            "call",
            "lead",
            "lead_name",
            "action_type",
            "app_state",
            "metadata",
            "created_at",
        )


class CallSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)
    lead_name = serializers.CharField(source="lead.name", read_only=True)
    lead_phone = serializers.CharField(source="lead.phone", read_only=True)
    status_label = serializers.CharField(source="get_status_display", read_only=True)
    callback_window_label = serializers.CharField(
        source="get_callback_window_display",
        read_only=True,
    )

    class Meta:
        model = Call
        fields = (
            "id",
            "staff",
            "staff_name",
            "lead",
            "lead_name",
            "lead_phone",
            "start_time",
            "end_time",
            "duration_seconds",
            "status",
            "status_label",
            "callback_window",
            "callback_window_label",
            "is_qualifying",
            "is_verified",
            "verification_source",
        )


class SalarySerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)
    payout_cycle_label = serializers.CharField(source="get_payout_cycle_display", read_only=True)
    payment_method_label = serializers.CharField(source="get_payment_method_display", read_only=True)

    class Meta:
        model = Salary
        fields = (
            "id",
            "staff",
            "staff_name",
            "period_start",
            "period_end",
            "payout_cycle",
            "payout_cycle_label",
            "total_hours",
            "total_call_minutes",
            "converted_leads",
            "base_pay",
            "call_earnings",
            "bonus_earnings",
            "incentives",
            "final_salary",
            "paid_amount",
            "is_paid",
            "paid_at",
            "payment_method",
            "payment_method_label",
            "payment_reference",
            "payment_note",
        )


class SalaryHistorySerializer(serializers.ModelSerializer):
    payout_cycle_label = serializers.CharField(source="get_payout_cycle_display", read_only=True)
    payment_method_label = serializers.CharField(source="get_payment_method_display", read_only=True)
    period_label = serializers.SerializerMethodField()
    total_hours_label = serializers.SerializerMethodField()
    final_salary_label = serializers.SerializerMethodField()
    paid_amount_label = serializers.SerializerMethodField()
    paid_at_label = serializers.SerializerMethodField()

    class Meta:
        model = Salary
        fields = (
            "id",
            "period_start",
            "period_end",
            "period_label",
            "payout_cycle",
            "payout_cycle_label",
            "total_hours",
            "total_hours_label",
            "final_salary",
            "final_salary_label",
            "paid_amount",
            "paid_amount_label",
            "paid_at",
            "paid_at_label",
            "payment_method",
            "payment_method_label",
            "payment_reference",
            "payment_note",
        )

    def get_period_label(self, obj):
        return f"{obj.period_start.strftime('%d %b %Y')} to {obj.period_end.strftime('%d %b %Y')}"

    def get_total_hours_label(self, obj):
        return f"{float(obj.total_hours or 0):,.1f}h"

    def get_final_salary_label(self, obj):
        return f"Rs. {float(obj.final_salary or 0):,.2f}"

    def get_paid_amount_label(self, obj):
        return f"Rs. {float(obj.paid_amount or 0):,.2f}"

    def get_paid_at_label(self, obj):
        if not obj.paid_at:
            return "--"
        return timezone.localtime(obj.paid_at).strftime("%d %b %Y, %I:%M %p")


class SalaryPaymentSerializer(serializers.Serializer):
    payout_cycle = serializers.ChoiceField(choices=Salary.PayoutCycle.choices)
    period_start = serializers.DateField()
    period_end = serializers.DateField()
    paid_amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=0)
    payment_method = serializers.ChoiceField(choices=Salary.PaymentMethod.choices, required=False, allow_blank=True)
    payment_reference = serializers.CharField(max_length=120, required=False, allow_blank=True)
    payment_note = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        if attrs["period_end"] < attrs["period_start"]:
            raise serializers.ValidationError({"period_end": "End date must be on or after the start date."})
        return attrs


class CreateAppReleaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = AppRelease
        fields = (
            "version_name",
            "version_code",
            "minimum_supported_version_code",
            "release_notes",
            "apk_file",
            "is_mandatory",
            "is_active",
            "published_at",
        )

    def validate_apk_file(self, value):
        file_name = getattr(value, "name", "").lower()
        if not file_name.endswith(".apk"):
            raise serializers.ValidationError("Upload a valid Android APK file.")
        if getattr(value, "size", 0) <= 0:
            raise serializers.ValidationError("The uploaded APK file is empty.")
        return value

    def validate(self, attrs):
        version_code = attrs.get("version_code")
        min_supported = attrs.get("minimum_supported_version_code", 0)
        if version_code is not None and min_supported and min_supported > version_code:
            raise serializers.ValidationError(
                {"minimum_supported_version_code": "Minimum supported version cannot be higher than the uploaded version."}
            )
        return attrs


class AppReleaseSerializer(serializers.ModelSerializer):
    download_url = serializers.SerializerMethodField()
    file_size_mb = serializers.SerializerMethodField()
    created_by_name = serializers.CharField(source="created_by.name", read_only=True)

    class Meta:
        model = AppRelease
        fields = (
            "id",
            "version_name",
            "version_code",
            "minimum_supported_version_code",
            "release_notes",
            "download_url",
            "file_size_bytes",
            "file_size_mb",
            "is_mandatory",
            "is_active",
            "published_at",
            "created_by_name",
        )

    def get_download_url(self, obj):
        request = self.context.get("request")
        if not obj.apk_file:
            return ""
        url = reverse("app-release-download", args=[obj.id])
        if request:
            return request.build_absolute_uri(url)
        return url

    def get_file_size_mb(self, obj):
        return round((obj.file_size_bytes or 0) / (1024 * 1024), 2)

class TrainingLessonSerializer(serializers.ModelSerializer):
    completed_staff_count = serializers.IntegerField(read_only=True)
    pending_staff_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = TrainingLesson
        fields = (
            "id",
            "title",
            "description",
            "video_url",
            "search_keywords",
            "is_active",
            "is_mandatory",
            "sort_order",
            "published_at",
            "completed_staff_count",
            "pending_staff_count",
        )


class CreateTrainingLessonSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrainingLesson
        fields = (
            "id",
            "title",
            "description",
            "video_url",
            "search_keywords",
            "is_active",
            "is_mandatory",
            "sort_order",
            "published_at",
        )


class UpdateTrainingLessonSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrainingLesson
        fields = (
            "title",
            "description",
            "video_url",
            "search_keywords",
            "is_active",
            "is_mandatory",
            "sort_order",
            "published_at",
        )



