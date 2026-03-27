from rest_framework import serializers

from backend.apps.telecalling.models import (
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
    phone = serializers.CharField(max_length=20)
    password = serializers.CharField()


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
        compensation_type = attrs.get("compensation_type", Staff.CompensationType.HOURLY)
        if compensation_type == Staff.CompensationType.WEEKLY and not attrs.get("weekly_salary"):
            raise serializers.ValidationError({"weekly_salary": "Weekly salary is required for weekly pay mode."})
        if compensation_type == Staff.CompensationType.MONTHLY and not attrs.get("monthly_salary"):
            raise serializers.ValidationError({"monthly_salary": "Monthly salary is required for monthly pay mode."})
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
        instance = getattr(self, "instance", None)
        compensation_type = attrs.get(
            "compensation_type",
            getattr(instance, "compensation_type", Staff.CompensationType.HOURLY),
        )
        weekly_salary = attrs.get("weekly_salary", getattr(instance, "weekly_salary", None))
        monthly_salary = attrs.get("monthly_salary", getattr(instance, "monthly_salary", None))
        if compensation_type == Staff.CompensationType.WEEKLY and not weekly_salary:
            raise serializers.ValidationError({"weekly_salary": "Weekly salary is required for weekly pay mode."})
        if compensation_type == Staff.CompensationType.MONTHLY and not monthly_salary:
            raise serializers.ValidationError({"monthly_salary": "Monthly salary is required for monthly pay mode."})
        return attrs

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
        instance.save()
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
        )


class SalarySerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source="staff.name", read_only=True)

    class Meta:
        model = Salary
        fields = (
            "id",
            "staff",
            "staff_name",
            "period_start",
            "period_end",
            "total_hours",
            "total_call_minutes",
            "converted_leads",
            "incentives",
            "final_salary",
        )


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
