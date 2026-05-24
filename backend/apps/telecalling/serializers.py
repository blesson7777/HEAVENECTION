from datetime import timedelta
from pathlib import Path
from decimal import Decimal

from django.urls import reverse
from rest_framework import serializers
from django.utils import timezone

from backend.apps.telecalling.models import (
    AppRelease,
    Call,
    CompanyProfile,
    InterestedLeadDetail,
    Lead,
    ReferralSubmission,
    Salary,
    SalaryPaymentTransaction,
    Session,
    Staff,
    StaffAction,
    TrainingLesson,
)
from backend.apps.telecalling.services import (
    build_staff_current_salary_summary,
    build_staff_document_url,
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
    from_followup_menu = serializers.BooleanField(required=False, default=False)


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
    callback_date = serializers.DateField(required=False)
    duration_seconds = serializers.IntegerField(min_value=0, required=False)
    ended_at = serializers.DateTimeField(required=False)
    source = serializers.CharField(max_length=50, required=False, default="app")

    def validate(self, attrs):
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
    callback_date = serializers.DateField(required=False)

    def validate(self, attrs):
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
    callback_date = serializers.DateField(required=False)
    customer_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    customer_phone = serializers.CharField(max_length=20, required=False, allow_blank=True)
    product_enquired = serializers.CharField(max_length=150, required=False, allow_blank=True)
    enquiry_notes = serializers.CharField(required=False, allow_blank=True)
    preferred_call_time = serializers.CharField(max_length=120, required=False, allow_blank=True)

    def validate(self, attrs):
        status = attrs.get("status")
        if status != Lead.Status.INTERESTED:
            return attrs

        detail_fields = (
            "customer_name",
            "customer_phone",
            "product_enquired",
            "enquiry_notes",
            "preferred_call_time",
        )
        has_detail_payload = any((attrs.get(field) or "").strip() for field in detail_fields)
        if not has_detail_payload:
            raise serializers.ValidationError(
                {
                    "customer_name": "Fill interested customer details before saving as Follow Up.",
                    "customer_phone": "Fill interested customer details before saving as Follow Up.",
                    "product_enquired": "Fill interested customer details before saving as Follow Up.",
                    "preferred_call_time": "Fill interested customer details before saving as Follow Up.",
                }
            )

        required_fields = (
            "customer_name",
            "customer_phone",
            "product_enquired",
            "preferred_call_time",
        )
        errors = {}
        normalized = {}
        for field in required_fields:
            value = (attrs.get(field) or "").strip()
            if not value:
                errors[field] = "This field is required when saving interested details."
            else:
                normalized[field] = value
        if errors:
            raise serializers.ValidationError(errors)

        attrs["interested_detail"] = {
            **normalized,
            "enquiry_notes": (attrs.get("enquiry_notes") or "").strip(),
        }
        return attrs


class InterestedLeadDetailSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)
    lead_name = serializers.CharField(source="lead.name", read_only=True)
    lead_phone = serializers.CharField(source="lead.phone", read_only=True)
    updated_at_label = serializers.SerializerMethodField()
    created_at_label = serializers.SerializerMethodField()

    class Meta:
        model = InterestedLeadDetail
        fields = (
            "id",
            "lead",
            "lead_name",
            "lead_phone",
            "staff",
            "staff_name",
            "call",
            "customer_name",
            "customer_phone",
            "product_enquired",
            "enquiry_notes",
            "preferred_call_time",
            "created_at",
            "created_at_label",
            "updated_at",
            "updated_at_label",
        )
        read_only_fields = (
            "id",
            "lead",
            "lead_name",
            "lead_phone",
            "staff",
            "staff_name",
            "call",
            "created_at",
            "created_at_label",
            "updated_at",
            "updated_at_label",
        )

    def get_updated_at_label(self, obj):
        return timezone.localtime(obj.updated_at).strftime("%d %b %Y, %I:%M %p")

    def get_created_at_label(self, obj):
        return timezone.localtime(obj.created_at).strftime("%d %b %Y, %I:%M %p")


class InterestedLeadCaptureSerializer(serializers.Serializer):
    customer_name = serializers.CharField(max_length=150)
    customer_phone = serializers.CharField(max_length=20)
    product_enquired = serializers.CharField(max_length=150)
    enquiry_notes = serializers.CharField(required=False, allow_blank=True)
    preferred_call_time = serializers.CharField(max_length=120)

    def validate_customer_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter the customer name.")
        return value

    def validate_customer_phone(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter the customer number.")
        return value

    def validate_product_enquired(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter the product enquired.")
        return value

    def validate_preferred_call_time(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter the preferred call time.")
        return value


class StaffSerializer(serializers.ModelSerializer):
    compensation_type_label = serializers.CharField(source="get_compensation_type_display", read_only=True)
    weekly_payout_day_label = serializers.CharField(source="get_weekly_payout_day_display", read_only=True)
    referred_by_name = serializers.CharField(source="referred_by.name", read_only=True)

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
            "weekly_payout_day",
            "weekly_payout_day_label",
            "call_rate",
            "bonus_per_conversion",
            "referred_by",
            "referred_by_name",
            "last_seen_at",
        )


class StaffProfileSerializer(serializers.ModelSerializer):
    role_label = serializers.CharField(source="get_role_display", read_only=True)
    aadhar_photo_url = serializers.SerializerMethodField()
    aadhar_photo_name = serializers.SerializerMethodField()
    passbook_photo_url = serializers.SerializerMethodField()
    passbook_photo_name = serializers.SerializerMethodField()
    salary_summary = serializers.SerializerMethodField()
    referral_program_enabled = serializers.SerializerMethodField()
    referral_required_hours_label = serializers.SerializerMethodField()
    referral_reward_amount_label = serializers.SerializerMethodField()

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
            "referral_program_enabled",
            "referral_required_hours_label",
            "referral_reward_amount_label",
        )

    def get_aadhar_photo_url(self, obj):
        request = self.context.get("request")
        return build_staff_document_url(
            obj,
            "aadhar",
            request=request,
            route_name="api-staff-profile-document",
        )

    def get_passbook_photo_url(self, obj):
        request = self.context.get("request")
        return build_staff_document_url(
            obj,
            "passbook",
            request=request,
            route_name="api-staff-profile-document",
        )

    def get_aadhar_photo_name(self, obj):
        if not obj.aadhar_photo:
            return ""
        return Path(obj.aadhar_photo.name).name

    def get_passbook_photo_name(self, obj):
        if not obj.passbook_photo:
            return ""
        return Path(obj.passbook_photo.name).name

    def get_salary_summary(self, obj):
        return build_staff_current_salary_summary(obj)

    def get_referral_program_enabled(self, obj):
        return CompanyProfile.objects.filter(pk=1).values_list(
            "referral_program_enabled",
            flat=True,
        ).first() is True

    def get_referral_required_hours_label(self, obj):
        required_hours = CompanyProfile.objects.filter(pk=1).values_list(
            "referral_required_hours",
            flat=True,
        ).first()
        return f"{float(required_hours or 0):,.1f}h"

    def get_referral_reward_amount_label(self, obj):
        reward_amount = CompanyProfile.objects.filter(pk=1).values_list(
            "referral_reward_amount",
            flat=True,
        ).first()
        return f"Rs. {Decimal(reward_amount or 0):,.2f}"


class StaffReferralSubmissionSerializer(serializers.ModelSerializer):
    status_label = serializers.CharField(source="get_status_display", read_only=True)
    joined_staff_name = serializers.CharField(source="joined_staff.name", read_only=True)

    class Meta:
        model = ReferralSubmission
        fields = (
            "id",
            "referred_name",
            "referred_phone",
            "status",
            "status_label",
            "joined_staff",
            "joined_staff_name",
            "created_at",
        )


class CreateStaffReferralSubmissionSerializer(serializers.Serializer):
    referred_name = serializers.CharField(max_length=150)
    referred_phone = serializers.CharField(max_length=20)

    def validate_referred_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError("Enter your friend's name.")
        return name

    def validate_referred_phone(self, value):
        phone = value.strip()
        if not phone:
            raise serializers.ValidationError("Enter your friend's phone number.")
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user and phone == user.phone:
            raise serializers.ValidationError("You cannot refer your own phone number.")
        if Staff.objects.filter(phone=phone).exists():
            raise serializers.ValidationError("This phone number already belongs to a team member.")
        if ReferralSubmission.objects.filter(referred_phone=phone).exists():
            raise serializers.ValidationError("This phone number has already been referred.")
        return phone

    def validate(self, attrs):
        if not CompanyProfile.objects.filter(pk=1, referral_program_enabled=True).exists():
            raise serializers.ValidationError(
                {"referred_phone": "Referral program is not enabled right now."}
            )
        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        company_profile = CompanyProfile.objects.filter(pk=1).first()
        return ReferralSubmission.objects.create(
            referrer=request.user,
            referred_name=validated_data["referred_name"],
            referred_phone=validated_data["referred_phone"],
            program_enabled_at_submit=bool(company_profile and company_profile.referral_program_enabled),
            required_hours_at_submit=(
                company_profile.referral_required_hours if company_profile else 0
            ),
            reward_amount_at_submit=(
                company_profile.referral_reward_amount if company_profile else 0
            ),
        )


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
    weekly_payout_day = serializers.ChoiceField(choices=Staff.WeeklyPayoutDay.choices, required=False)
    call_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    bonus_per_conversion = serializers.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
    )
    referred_by_id = serializers.UUIDField(required=False, allow_null=True)
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
        referred_by_id = validated_data.pop("referred_by_id", None)
        if referred_by_id:
            validated_data["referred_by"] = Staff.objects.filter(
                id=referred_by_id,
                role=Staff.Role.STAFF,
            ).first()
        staff = Staff.objects.create_user(
            password=password,
            role=Staff.Role.STAFF,
            **validated_data,
        )
        if staff.referred_by_id:
            ReferralSubmission.objects.filter(
                referrer=staff.referred_by,
                referred_phone=staff.phone,
            ).update(
                status=ReferralSubmission.Status.JOINED,
                joined_staff=staff,
            )
        return staff


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
    weekly_payout_day = serializers.ChoiceField(choices=Staff.WeeklyPayoutDay.choices, required=False)
    call_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    bonus_per_conversion = serializers.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
    )
    referred_by_id = serializers.UUIDField(required=False, allow_null=True)
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
        referred_by_id = attrs.get("referred_by_id")
        instance = getattr(self, "instance", None)
        if referred_by_id:
            referred_by = Staff.objects.filter(id=referred_by_id, role=Staff.Role.STAFF).first()
            if not referred_by:
                raise serializers.ValidationError({"referred_by_id": "Select a valid staff member."})
            if instance and referred_by.id == instance.id:
                raise serializers.ValidationError({"referred_by_id": "A staff member cannot refer themselves."})
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
        referred_by_id = validated_data.pop("referred_by_id", None)
        remove_aadhar_photo = validated_data.pop("remove_aadhar_photo", False)
        new_photo = validated_data.pop("aadhar_photo", None)
        remove_passbook_photo = validated_data.pop("remove_passbook_photo", False)
        new_passbook_photo = validated_data.pop("passbook_photo", None)
        previous_photo = instance.aadhar_photo if instance.aadhar_photo else None
        previous_passbook_photo = instance.passbook_photo if instance.passbook_photo else None
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if referred_by_id is not None:
            instance.referred_by = Staff.objects.filter(
                id=referred_by_id,
                role=Staff.Role.STAFF,
            ).first()
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
        if instance.referred_by_id:
            ReferralSubmission.objects.filter(
                referrer=instance.referred_by,
                referred_phone=instance.phone,
            ).update(
                status=ReferralSubmission.Status.JOINED,
                joined_staff=instance,
            )
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
    weekly_payout_day_label = serializers.CharField(source="get_weekly_payout_day_display", read_only=True)
    referred_by_name = serializers.CharField(source="referred_by.name", read_only=True)

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
            "weekly_payout_day",
            "weekly_payout_day_label",
            "call_rate",
            "bonus_per_conversion",
            "referred_by",
            "referred_by_name",
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
            "referral_program_enabled",
            "referral_required_hours",
            "referral_reward_amount",
            "hourly_call_bonus_enabled",
            "hourly_call_bonus_threshold",
            "hourly_call_bonus_rate",
            "followup_auto_expire_enabled",
            "followup_auto_expire_days",
            "followup_staff_warning_days",
            "followup_uncalled_alert_enabled",
            "followup_uncalled_alert_hours",
            "work_review_zero_talk_attempt_threshold",
            "work_review_idle_gap_seconds",
            "work_review_connected_cooldown_seconds",
            "work_review_followup_expired_penalty_points",
            "work_review_followup_expired_penalty_cap",
            "lead_auto_delete_enabled",
            "lead_auto_delete_mode",
            "lead_auto_delete_days",
            "lead_auto_delete_count",
            "lead_auto_delete_last_run_on",
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
            "referral_program_enabled",
            "referral_required_hours",
            "referral_reward_amount",
            "hourly_call_bonus_enabled",
            "hourly_call_bonus_threshold",
            "hourly_call_bonus_rate",
            "followup_auto_expire_enabled",
            "followup_auto_expire_days",
            "followup_staff_warning_days",
            "followup_uncalled_alert_enabled",
            "followup_uncalled_alert_hours",
            "work_review_zero_talk_attempt_threshold",
            "work_review_idle_gap_seconds",
            "work_review_connected_cooldown_seconds",
            "work_review_followup_expired_penalty_points",
            "work_review_followup_expired_penalty_cap",
            "lead_auto_delete_enabled",
            "lead_auto_delete_mode",
            "lead_auto_delete_days",
            "lead_auto_delete_count",
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

    def validate_hourly_call_bonus_threshold(self, value):
        if value is None:
            return value
        if int(value) < 0:
            raise serializers.ValidationError("Target calls per hour cannot be negative.")
        return value

    def validate_work_review_zero_talk_attempt_threshold(self, value):
        if value is None:
            return value
        threshold = int(value)
        if threshold < 1:
            raise serializers.ValidationError("Zero-talk attempt threshold must be at least 1.")
        if threshold > 200:
            raise serializers.ValidationError("Zero-talk attempt threshold cannot exceed 200.")
        return threshold

    def validate_work_review_idle_gap_seconds(self, value):
        if value is None:
            return value
        gap_seconds = int(value)
        if gap_seconds < 1:
            raise serializers.ValidationError("Idle gap split seconds must be at least 1.")
        if gap_seconds > 3600:
            raise serializers.ValidationError("Idle gap split seconds cannot exceed 3600.")
        return gap_seconds

    def validate_work_review_connected_cooldown_seconds(self, value):
        if value is None:
            return value
        cooldown_seconds = int(value)
        if cooldown_seconds < 0:
            raise serializers.ValidationError("Connected cooldown seconds cannot be negative.")
        if cooldown_seconds > 3600:
            raise serializers.ValidationError("Connected cooldown seconds cannot exceed 3600.")
        return cooldown_seconds

    def validate_followup_auto_expire_days(self, value):
        if value is None:
            return value
        expiry_days = int(value)
        if expiry_days < 1:
            raise serializers.ValidationError("Follow-up auto-expire days must be at least 1.")
        if expiry_days > 3650:
            raise serializers.ValidationError("Follow-up auto-expire days cannot exceed 3650.")
        return expiry_days

    def validate_followup_staff_warning_days(self, value):
        if value is None:
            return value
        warning_days = int(value)
        if warning_days < 1:
            raise serializers.ValidationError("Follow-up warning days must be at least 1.")
        if warning_days > 3650:
            raise serializers.ValidationError("Follow-up warning days cannot exceed 3650.")
        return warning_days

    def validate_followup_uncalled_alert_hours(self, value):
        if value is None:
            return value
        alert_hours = int(value)
        if alert_hours < 1:
            raise serializers.ValidationError("Follow-up uncalled alert hours must be at least 1.")
        if alert_hours > 24 * 120:
            raise serializers.ValidationError("Follow-up uncalled alert hours cannot exceed 2880.")
        return alert_hours

    def validate_work_review_followup_expired_penalty_points(self, value):
        if value is None:
            return value
        penalty_points = int(value)
        if penalty_points < 0:
            raise serializers.ValidationError("Expired follow-up penalty points cannot be negative.")
        if penalty_points > 100:
            raise serializers.ValidationError("Expired follow-up penalty points cannot exceed 100.")
        return penalty_points

    def validate_work_review_followup_expired_penalty_cap(self, value):
        if value is None:
            return value
        penalty_cap = int(value)
        if penalty_cap < 0:
            raise serializers.ValidationError("Expired follow-up penalty cap cannot be negative.")
        if penalty_cap > 100:
            raise serializers.ValidationError("Expired follow-up penalty cap cannot exceed 100.")
        return penalty_cap

    def validate_lead_auto_delete_days(self, value):
        if value is None:
            return value
        if int(value) < 1:
            raise serializers.ValidationError("Auto delete days must be at least 1.")
        return value

    def validate_lead_auto_delete_count(self, value):
        if value is None:
            return value
        if int(value) < 1:
            raise serializers.ValidationError("Auto delete count must be at least 1.")
        return value

    def validate_hourly_call_bonus_rate(self, value):
        if value is None:
            return value
        if Decimal(value) < Decimal("0.00"):
            raise serializers.ValidationError("Bonus per extra call cannot be negative.")
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
    handover_status_label = serializers.CharField(source="get_handover_status_display", read_only=True)
    callback_window_label = serializers.CharField(
        source="get_callback_window_display",
        read_only=True,
    )
    callback_date_label = serializers.SerializerMethodField()
    callback_schedule_label = serializers.SerializerMethodField()

    class Meta:
        model = Lead
        fields = (
            "id",
            "name",
            "phone",
            "status",
            "status_label",
            "handover_status",
            "handover_status_label",
            "callback_window",
            "callback_window_label",
            "callback_date",
            "callback_date_label",
            "callback_schedule_label",
            "assigned_to",
            "assigned_to_name",
            "notes",
            "last_contacted_at",
            "updated_at",
        )

    def get_callback_date_label(self, obj):
        if not obj.callback_date:
            return ""
        return obj.callback_date.strftime("%d %b %Y")

    def get_callback_schedule_label(self, obj):
        parts = []
        if obj.callback_date:
            parts.append(obj.callback_date.strftime("%d %b %Y"))
        if obj.callback_window:
            parts.append(obj.get_callback_window_display())
        return " • ".join(parts)


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
            "handover_status",
            "callback_window",
            "callback_date",
            "assigned_to",
            "notes",
        )

    def validate(self, attrs):
        if attrs.get("status") == Lead.Status.CALL_BACK:
            errors = {}
            if not attrs.get("callback_window"):
                errors["callback_window"] = "Select Noon, Evening, or Night for callback leads."
            if not attrs.get("callback_date"):
                errors["callback_date"] = "Select the requested callback date."
            if errors:
                raise serializers.ValidationError(errors)
        else:
            attrs["callback_window"] = ""
            attrs["callback_date"] = None
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
            "handover_status",
            "callback_window",
            "callback_date",
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
        callback_date = attrs.get(
            "callback_date",
            getattr(instance, "callback_date", None),
        )
        if status == Lead.Status.CALL_BACK:
            errors = {}
            if not callback_window:
                errors["callback_window"] = "Select Noon, Evening, or Night for callback leads."
            if not callback_date:
                errors["callback_date"] = "Select the requested callback date."
            if errors:
                raise serializers.ValidationError(errors)
        else:
            attrs["callback_window"] = ""
            attrs["callback_date"] = None
        return attrs

    def update(self, instance, validated_data):
        new_handover_status = validated_data.get("handover_status")
        if new_handover_status and new_handover_status != instance.handover_status:
            validated_data["handover_updated_at"] = timezone.now()
        return super().update(instance, validated_data)


class LeadImportUploadSerializer(serializers.Serializer):
    class AssignmentMode:
        AUTOMATIC = "auto"
        SELECTED_STAFF = "selected_staff"

    file = serializers.FileField()
    assignment_mode = serializers.ChoiceField(
        choices=[
            (AssignmentMode.AUTOMATIC, "Automatic"),
            (AssignmentMode.SELECTED_STAFF, "Selected Staff"),
        ],
        required=False,
        default=AssignmentMode.AUTOMATIC,
    )
    assigned_staff_ids = serializers.PrimaryKeyRelatedField(
        queryset=Staff.objects.filter(role=Staff.Role.STAFF, is_active=True),
        many=True,
        required=False,
    )

    def validate_file(self, value):
        file_name = str(getattr(value, "name", "")).lower()
        if not file_name.endswith((".csv", ".xlsx", ".xlsm", ".vcf")):
            raise serializers.ValidationError("Upload a CSV, Excel, or VCF file.")
        return value

    def validate(self, attrs):
        assignment_mode = attrs.get("assignment_mode", self.AssignmentMode.AUTOMATIC)
        selected_staff = attrs.get("assigned_staff_ids") or []
        if assignment_mode == self.AssignmentMode.SELECTED_STAFF and not selected_staff:
            raise serializers.ValidationError(
                {"assigned_staff_ids": "Select at least one active staff member for manual import assignment."}
            )
        return attrs


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
    sync_skip_reason_label = serializers.CharField(
        source="get_sync_skip_reason_display",
        read_only=True,
    )
    callback_window_label = serializers.CharField(
        source="get_callback_window_display",
        read_only=True,
    )
    callback_date_label = serializers.SerializerMethodField()
    callback_schedule_label = serializers.SerializerMethodField()

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
            "callback_date",
            "callback_date_label",
            "callback_schedule_label",
            "is_qualifying",
            "is_verified",
            "verification_source",
            "auto_skipped_sync_issue",
            "sync_skip_reason",
            "sync_skip_reason_label",
        )

    def get_callback_date_label(self, obj):
        if not obj.callback_date:
            return ""
        return obj.callback_date.strftime("%d %b %Y")

    def get_callback_schedule_label(self, obj):
        parts = []
        if obj.callback_date:
            parts.append(obj.callback_date.strftime("%d %b %Y"))
        if obj.callback_window:
            parts.append(obj.get_callback_window_display())
        return " • ".join(parts)


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
    period_start = serializers.DateField(source="salary_record.period_start", read_only=True)
    period_end = serializers.DateField(source="salary_record.period_end", read_only=True)
    payout_cycle = serializers.CharField(source="salary_record.payout_cycle", read_only=True)
    payout_cycle_label = serializers.CharField(source="salary_record.get_payout_cycle_display", read_only=True)
    total_hours = serializers.DecimalField(
        source="salary_record.total_hours",
        max_digits=10,
        decimal_places=2,
        read_only=True,
    )
    final_salary = serializers.DecimalField(
        source="salary_record.final_salary",
        max_digits=12,
        decimal_places=2,
        read_only=True,
    )
    paid_amount = serializers.DecimalField(source="amount", max_digits=12, decimal_places=2, read_only=True)
    payment_method_label = serializers.CharField(source="get_payment_method_display", read_only=True)
    period_label = serializers.SerializerMethodField()
    total_hours_label = serializers.SerializerMethodField()
    final_salary_label = serializers.SerializerMethodField()
    paid_amount_label = serializers.SerializerMethodField()
    paid_at_label = serializers.SerializerMethodField()
    payment_kind_label = serializers.CharField(source="get_payment_kind_display", read_only=True)

    class Meta:
        model = SalaryPaymentTransaction
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
            "payment_kind",
            "payment_kind_label",
            "payment_method",
            "payment_method_label",
            "payment_reference",
            "payment_note",
        )

    def get_period_label(self, obj):
        return (
            f"{obj.salary_record.period_start.strftime('%d %b %Y')} "
            f"to {obj.salary_record.period_end.strftime('%d %b %Y')}"
        )

    def get_total_hours_label(self, obj):
        return f"{float(obj.salary_record.total_hours or 0):,.1f}h"

    def get_final_salary_label(self, obj):
        return f"Rs. {float(obj.salary_record.final_salary or 0):,.2f}"

    def get_paid_amount_label(self, obj):
        return f"Rs. {float(obj.amount or 0):,.2f}"

    def get_paid_at_label(self, obj):
        if not obj.paid_at:
            return "--"
        return timezone.localtime(obj.paid_at).strftime("%d %b %Y, %I:%M %p")


class SalaryPaymentSerializer(serializers.Serializer):
    payout_cycle = serializers.ChoiceField(choices=Salary.PayoutCycle.choices)
    period_start = serializers.DateField()
    period_end = serializers.DateField()
    paid_amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal("0.01"))
    payment_kind = serializers.ChoiceField(
        choices=SalaryPaymentTransaction.PaymentKind.choices,
        required=False,
        default=SalaryPaymentTransaction.PaymentKind.SALARY,
    )
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



