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
        DEVELOPER = "developer", "Developer"
        STAFF = "staff", "Staff"

    class CompensationType(models.TextChoices):
        HOURLY = "hourly", "Hourly"
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"

    class WeeklyPayoutDay(models.TextChoices):
        MONDAY = "monday", "Monday"
        TUESDAY = "tuesday", "Tuesday"
        WEDNESDAY = "wednesday", "Wednesday"
        THURSDAY = "thursday", "Thursday"
        FRIDAY = "friday", "Friday"
        SATURDAY = "saturday", "Saturday"
        SUNDAY = "sunday", "Sunday"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, unique=True, db_index=True)
    email = models.EmailField(blank=True)
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
    weekly_payout_day = models.CharField(
        max_length=12,
        choices=WeeklyPayoutDay.choices,
        default=WeeklyPayoutDay.WEDNESDAY,
    )
    call_rate = models.DecimalField(max_digits=10, decimal_places=2, default=3)
    bonus_per_conversion = models.DecimalField(max_digits=10, decimal_places=2, default=500)
    bank_account_name = models.CharField(max_length=150, blank=True)
    bank_name = models.CharField(max_length=150, blank=True)
    bank_account_number = models.CharField(max_length=50, blank=True)
    bank_ifsc_code = models.CharField(max_length=30, blank=True)
    aadhar_number = models.CharField(max_length=20, blank=True)
    aadhar_photo = models.FileField(upload_to="staff_documents/aadhar/", blank=True, null=True)
    passbook_photo = models.FileField(upload_to="staff_documents/passbook/", blank=True, null=True)
    referred_by = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="referred_staff_members",
    )
    auth_session_key = models.UUIDField(default=uuid.uuid4, editable=False, db_index=True)
    last_seen_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = StaffManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = ["name"]

    class Meta:
        ordering = ("name",)

    def save(self, *args, **kwargs):
        self.is_staff = self.role in {self.Role.ADMIN, self.Role.DEVELOPER} or self.is_superuser
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
    referral_program_enabled = models.BooleanField(default=False)
    referral_required_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    referral_reward_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    hourly_call_bonus_enabled = models.BooleanField(default=False)
    hourly_call_bonus_threshold = models.PositiveIntegerField(default=50)
    hourly_call_bonus_rate = models.DecimalField(max_digits=10, decimal_places=2, default=0.50)
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

    class HandoverStatus(models.TextChoices):
        NOT_SENT = "not_sent", "Not Sent"
        SENT = "sent", "Sent to Client"
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"
        COMPLETED = "completed", "Completed"

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
    handover_status = models.CharField(
        max_length=20,
        choices=HandoverStatus.choices,
        default=HandoverStatus.NOT_SENT,
        db_index=True,
    )
    handover_updated_at = models.DateTimeField(null=True, blank=True)
    callback_window = models.CharField(
        max_length=20,
        choices=CallbackWindow.choices,
        blank=True,
        default="",
        db_index=True,
    )
    callback_date = models.DateField(null=True, blank=True, db_index=True)
    last_contacted_at = models.DateTimeField(null=True, blank=True)
    readd_count = models.PositiveIntegerField(default=0, db_index=True)
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
    callback_date = models.DateField(null=True, blank=True, db_index=True)
    is_qualifying = models.BooleanField(default=False, db_index=True)
    is_verified = models.BooleanField(default=False, db_index=True)
    verification_source = models.CharField(max_length=40, blank=True, default="")
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
    last_verified_call_at = models.DateTimeField(null=True, blank=True, db_index=True)
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
    class PayoutCycle(models.TextChoices):
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"
        CUSTOM = "custom", "Custom"

    class PaymentMethod(models.TextChoices):
        BANK_TRANSFER = "bank_transfer", "Bank Transfer"
        CASH = "cash", "Cash"
        UPI = "upi", "UPI"
        CHEQUE = "cheque", "Cheque"
        OTHER = "other", "Other"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    staff = models.ForeignKey(Staff, on_delete=models.CASCADE, related_name="salary_records")
    period_start = models.DateField()
    period_end = models.DateField()
    payout_cycle = models.CharField(
        max_length=20,
        choices=PayoutCycle.choices,
        default=PayoutCycle.MONTHLY,
        db_index=True,
    )
    total_hours = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_call_minutes = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    converted_leads = models.PositiveIntegerField(default=0)
    base_pay = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    call_earnings = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    bonus_earnings = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    incentives = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    final_salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    paid_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    is_paid = models.BooleanField(default=False, db_index=True)
    paid_at = models.DateTimeField(null=True, blank=True, db_index=True)
    payment_method = models.CharField(
        max_length=30,
        choices=PaymentMethod.choices,
        blank=True,
        default="",
    )
    payment_reference = models.CharField(max_length=120, blank=True)
    payment_note = models.TextField(blank=True)
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


class SalaryPaymentTransaction(models.Model):
    class PaymentKind(models.TextChoices):
        SALARY = "salary", "Salary"
        ADVANCE = "advance", "Advance"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    salary_record = models.ForeignKey(
        Salary,
        on_delete=models.CASCADE,
        related_name="payment_transactions",
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    payment_kind = models.CharField(
        max_length=20,
        choices=PaymentKind.choices,
        default=PaymentKind.SALARY,
        db_index=True,
    )
    payment_method = models.CharField(
        max_length=30,
        choices=Salary.PaymentMethod.choices,
        blank=True,
        default="",
    )
    payment_reference = models.CharField(max_length=120, blank=True)
    payment_note = models.TextField(blank=True)
    paid_at = models.DateTimeField(default=timezone.now, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-paid_at", "-created_at")


class ReferralReward(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    referrer = models.ForeignKey(
        Staff,
        on_delete=models.CASCADE,
        related_name="referral_rewards",
    )
    referred_staff = models.OneToOneField(
        Staff,
        on_delete=models.CASCADE,
        related_name="earned_referral_reward",
    )
    required_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    reward_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    qualified_at = models.DateTimeField(default=timezone.now, db_index=True)
    is_paid = models.BooleanField(default=False, db_index=True)
    paid_at = models.DateTimeField(null=True, blank=True, db_index=True)
    payment_method = models.CharField(
        max_length=30,
        choices=Salary.PaymentMethod.choices,
        blank=True,
        default="",
    )
    payment_reference = models.CharField(max_length=120, blank=True)
    payment_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-qualified_at", "-created_at")


class ReferralSubmission(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        REVIEWED = "reviewed", "Reviewed"
        JOINED = "joined", "Joined"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    referrer = models.ForeignKey(
        Staff,
        on_delete=models.CASCADE,
        related_name="referral_submissions",
    )
    referred_name = models.CharField(max_length=150)
    referred_phone = models.CharField(max_length=20, unique=True, db_index=True)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
        db_index=True,
    )
    joined_staff = models.ForeignKey(
        Staff,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="referral_submission_matches",
    )
    program_enabled_at_submit = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)


class AppRelease(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    version_name = models.CharField(max_length=40)
    version_code = models.PositiveIntegerField(unique=True, db_index=True)
    minimum_supported_version_code = models.PositiveIntegerField(default=0)
    release_notes = models.TextField(blank=True)
    apk_file = models.FileField(upload_to="app_releases/android/")
    file_size_bytes = models.PositiveBigIntegerField(default=0)
    is_mandatory = models.BooleanField(default=False, db_index=True)
    is_active = models.BooleanField(default=True, db_index=True)
    published_at = models.DateTimeField(default=timezone.now, db_index=True)
    created_by = models.ForeignKey(
        Staff,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="published_app_releases",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-version_code", "-published_at")

    def save(self, *args, **kwargs):
        if self.apk_file and getattr(self.apk_file, "size", None):
            self.file_size_bytes = int(self.apk_file.size or 0)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.version_name} ({self.version_code})"


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
