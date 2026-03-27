import uuid

from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models
from django.utils import timezone


class StaffManager(BaseUserManager):
    def create_user(self, phone, password=None, **extra_fields):
        if not phone:
            raise ValueError("Phone is required.")
        user = self.model(phone=phone, **extra_fields)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password, **extra_fields):
        extra_fields.setdefault("role", Staff.Role.ADMIN)
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)
        return self.create_user(phone, password, **extra_fields)


class Staff(AbstractBaseUser, PermissionsMixin):
    class Role(models.TextChoices):
        ADMIN = "admin", "Admin"
        STAFF = "staff", "Staff"

    class CompensationType(models.TextChoices):
        HOURLY = "hourly", "Hourly"
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, unique=True, db_index=True)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.STAFF)
    is_active = models.BooleanField(default=True, db_index=True)
    is_staff = models.BooleanField(default=False)
    compensation_type = models.CharField(
        max_length=20,
        choices=CompensationType.choices,
        default=CompensationType.HOURLY,
    )
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, default=150)
    weekly_salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    monthly_salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    target_hours_per_week = models.DecimalField(max_digits=6, decimal_places=2, default=48)
    target_hours_per_month = models.DecimalField(max_digits=6, decimal_places=2, default=208)
    call_rate = models.DecimalField(max_digits=10, decimal_places=2, default=3)
    bonus_per_conversion = models.DecimalField(max_digits=10, decimal_places=2, default=500)
    last_seen_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = StaffManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = ["name"]

    class Meta:
        ordering = ("name",)

    def save(self, *args, **kwargs):
        self.is_staff = self.role == self.Role.ADMIN or self.is_superuser
        super().save(*args, **kwargs)

    def __str__(self):
        return self.name


class CompanyProfile(models.Model):
    id = models.PositiveSmallIntegerField(primary_key=True, default=1, editable=False)
    company_name = models.CharField(max_length=150, default="Heavenection")
    legal_name = models.CharField(max_length=200, blank=True)
    company_email = models.EmailField(blank=True)
    company_phone = models.CharField(max_length=20, blank=True)
    support_phone = models.CharField(max_length=20, blank=True)
    website = models.URLField(blank=True)
    address_line_1 = models.CharField(max_length=255, blank=True)
    address_line_2 = models.CharField(max_length=255, blank=True)
    city = models.CharField(max_length=100, blank=True)
    state = models.CharField(max_length=100, blank=True)
    postal_code = models.CharField(max_length=20, blank=True)
    country = models.CharField(max_length=100, blank=True, default="India")
    tax_identifier = models.CharField(max_length=50, blank=True)
    lead_queue_target_per_staff = models.PositiveIntegerField(default=1)
    description = models.TextField(blank=True)
    logo = models.FileField(upload_to="branding/", blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Company Profile"
        verbose_name_plural = "Company Profile"

    def __str__(self):
        return self.company_name


class Lead(models.Model):
    class Status(models.TextChoices):
        NEW = "new", "New"
        INTERESTED = "interested", "Follow Up"
        NOT_INTERESTED = "not_interested", "Rejected"
        NO_ANSWER = "no_answer", "No Response"
        CALL_BACK = "call_back", "Call Back"
        CONVERTED = "converted", "Converted"

    class CallbackWindow(models.TextChoices):
        NOON = "noon", "Noon"
        EVENING = "evening", "Evening"
        NIGHT = "night", "Night"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, db_index=True)
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.NEW, db_index=True)
    assigned_to = models.ForeignKey(
        Staff,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_leads",
    )
    notes = models.TextField(blank=True)
    callback_window = models.CharField(
        max_length=20,
        choices=CallbackWindow.choices,
        blank=True,
        default="",
        db_index=True,
    )
    last_contacted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-updated_at",)


class Call(models.Model):
    class Status(models.TextChoices):
        STARTED = "started", "Started"
        INTERESTED = "interested", "Follow Up"
        NOT_INTERESTED = "not_interested", "Rejected"
        NO_ANSWER = "no_answer", "No Response"
        CALL_BACK = "call_back", "Call Back"
        CONVERTED = "converted", "Converted"
        INVALID_SHORT = "invalid_short", "Invalid Short"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="calls")
    lead = models.ForeignKey(Lead, on_delete=models.CASCADE, related_name="calls")
    start_time = models.DateTimeField(default=timezone.now, db_index=True)
    end_time = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.STARTED, db_index=True)
    callback_window = models.CharField(
        max_length=20,
        choices=Lead.CallbackWindow.choices,
        blank=True,
        default="",
        db_index=True,
    )
    is_qualifying = models.BooleanField(default=False, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-start_time",)


class Session(models.Model):
    class AppState(models.TextChoices):
        FOREGROUND = "foreground", "Foreground"
        BACKGROUND = "background", "Background"
        WARNING = "warning", "Warning"
        OFFLINE = "offline", "Offline"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="sessions")
    login_time = models.DateTimeField(default=timezone.now, db_index=True)
    logout_time = models.DateTimeField(null=True, blank=True)
    active_seconds = models.PositiveIntegerField(default=0)
    last_heartbeat_at = models.DateTimeField(null=True, blank=True, db_index=True)
    last_interaction_at = models.DateTimeField(null=True, blank=True, db_index=True)
    state_changed_at = models.DateTimeField(null=True, blank=True, db_index=True)
    warning_started_at = models.DateTimeField(null=True, blank=True, db_index=True)
    heartbeat_count = models.PositiveIntegerField(default=0)
    last_known_state = models.CharField(max_length=20, choices=AppState.choices, default=AppState.FOREGROUND)
    close_reason = models.CharField(max_length=40, blank=True, default="")
    is_open = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-login_time",)


class StaffAction(models.Model):
    class ActionType(models.TextChoices):
        SESSION_STARTED = "session_started", "Session Started"
        SESSION_ENDED = "session_ended", "Session Ended"
        SESSION_AUTO_ENDED = "session_auto_ended", "Session Auto Ended"
        TRAINING_REQUIRED_BLOCKED = "training_required_blocked", "Training Required Blocked"
        TRAINING_COMPLETED = "training_completed", "Training Completed"
        APP_FOREGROUNDED = "app_foregrounded", "App Foregrounded"
        APP_BACKGROUNDED = "app_backgrounded", "App Backgrounded"
        IDLE_WARNING = "idle_warning", "Idle Warning"
        IDLE_WARNING_ACKNOWLEDGED = "idle_warning_acknowledged", "Idle Warning Acknowledged"
        MARKED_OFFLINE = "marked_offline", "Marked Offline"
        RETURNED_ONLINE = "returned_online", "Returned Online"
        HEARTBEAT = "heartbeat", "Heartbeat"
        CALL_STARTED = "call_started", "Call Started"
        CALL_ENDED = "call_ended", "Call Ended"
        CALL_STATUS_UPDATED = "call_status_updated", "Call Status Updated"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="action_logs")
    session = models.ForeignKey(
        Session,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="action_logs",
    )
    call = models.ForeignKey(
        Call,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="action_logs",
    )
    lead = models.ForeignKey(
        Lead,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="action_logs",
    )
    action_type = models.CharField(max_length=40, choices=ActionType.choices, db_index=True)
    app_state = models.CharField(
        max_length=20,
        choices=Session.AppState.choices,
        null=True,
        blank=True,
    )
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["staff", "created_at"], name="tc_act_staff_created"),
            models.Index(fields=["action_type", "created_at"], name="tc_act_type_created"),
        ]


class Salary(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="salary_records")
    period_start = models.DateField()
    period_end = models.DateField()
    total_hours = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_call_minutes = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    converted_leads = models.PositiveIntegerField(default=0)
    incentives = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    final_salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-period_end", "staff__name")
        constraints = [
            models.UniqueConstraint(
                fields=["staff", "period_start", "period_end"],
                name="telecalling_unique_salary_period",
            )
        ]


class TrainingLesson(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=180)
    description = models.TextField(blank=True)
    video_url = models.URLField(blank=True)
    search_keywords = models.CharField(max_length=255, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    is_mandatory = models.BooleanField(default=True, db_index=True)
    sort_order = models.PositiveIntegerField(default=0)
    published_at = models.DateTimeField(default=timezone.now, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("sort_order", "-published_at", "title")

    def __str__(self):
        return self.title


class TrainingCompletion(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="training_completions")
    lesson = models.ForeignKey(TrainingLesson, on_delete=models.CASCADE, related_name="completions")
    completed_at = models.DateTimeField(default=timezone.now, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-completed_at",)
        constraints = [
            models.UniqueConstraint(
                fields=["staff", "lesson"],
                name="telecalling_unique_training_completion",
            )
        ]
