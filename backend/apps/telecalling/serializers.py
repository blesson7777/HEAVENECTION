from rest_framework import serializers

from backend.apps.telecalling.models import Call, Lead, Salary, Session, Staff, StaffAction


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
    duration_seconds = serializers.IntegerField(min_value=0, required=False)
    ended_at = serializers.DateTimeField(required=False)
    source = serializers.CharField(max_length=50, required=False, default="app")


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


class StaffSerializer(serializers.ModelSerializer):
    class Meta:
        model = Staff
        fields = (
            "id",
            "name",
            "phone",
            "role",
            "is_active",
            "hourly_rate",
            "call_rate",
            "bonus_per_conversion",
            "last_seen_at",
        )


class CreateStaffSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(min_length=6, write_only=True)
    hourly_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
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
    hourly_rate = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
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

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
        instance.save()
        return instance


class LeadSerializer(serializers.ModelSerializer):
    assigned_to_name = serializers.CharField(source="assigned_to.name", read_only=True)
    status_label = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = Lead
        fields = (
            "id",
            "name",
            "phone",
            "status",
            "status_label",
            "assigned_to",
            "assigned_to_name",
            "notes",
            "last_contacted_at",
            "updated_at",
        )


class CreateLeadSerializer(serializers.ModelSerializer):
    class Meta:
        model = Lead
        fields = (
            "id",
            "name",
            "phone",
            "status",
            "assigned_to",
            "notes",
        )


class UpdateLeadSerializer(serializers.ModelSerializer):
    class Meta:
        model = Lead
        fields = (
            "name",
            "phone",
            "status",
            "assigned_to",
            "notes",
        )


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
