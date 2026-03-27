import csv
import io
import re
from collections import Counter, defaultdict
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db.models import Count, Q, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from backend.apps.telecalling.models import (
    Call,
    CompanyProfile,
    Lead,
    Salary,
    Session,
    Staff,
    StaffAction,
    TrainingCompletion,
    TrainingLesson,
)

try:
    from openpyxl import load_workbook
except ImportError:  # pragma: no cover - dependency installed in runtime
    load_workbook = None


ONLINE_WINDOW_SECONDS = 90
SHORT_CALL_SECONDS = 5
BACKGROUND_TIMEOUT_SECONDS = 10 * 60
IDLE_WARNING_AFTER_SECONDS = 5 * 60
IDLE_WARNING_GRACE_SECONDS = 5 * 60
IDLE_OFFLINE_AFTER_SECONDS = IDLE_WARNING_AFTER_SECONDS + IDLE_WARNING_GRACE_SECONDS
TWOPLACES = Decimal("0.01")
DEFAULT_LEAD_QUEUE_LIMIT = 1
ACTIVE_QUEUE_STATUSES = (
    Lead.Status.NEW,
    Lead.Status.CALL_BACK,
    Lead.Status.INTERESTED,
)
TERMINAL_QUEUE_STATUSES = (
    Lead.Status.NOT_INTERESTED,
    Lead.Status.NO_ANSWER,
    Lead.Status.CONVERTED,
)
NAME_COLUMN_ALIASES = {
    "name",
    "leadname",
    "lead name",
    "customername",
    "customer name",
    "customer",
    "fullname",
    "full name",
    "clientname",
    "client name",
    "client",
}
PHONE_COLUMN_ALIASES = {
    "phone",
    "phone no",
    "phone no.",
    "phonenumber",
    "phone number",
    "mobile",
    "mobile no",
    "mobile no.",
    "mobilenumber",
    "mobile number",
    "contact",
    "contact no",
    "contact no.",
    "contactnumber",
    "contact number",
    "number",
    "whatsapp",
    "whatsapp number",
}


class TrainingRequiredError(Exception):
    def __init__(self, payload):
        super().__init__("Complete mandatory training before starting work.")
        self.payload = payload


def get_company_profile():
    profile, _ = CompanyProfile.objects.get_or_create(
        id=1,
        defaults={
            "company_name": "Heavenection",
            "country": "India",
        },
    )
    return profile


def get_lead_queue_limit():
    profile = get_company_profile()
    return max(1, int(profile.lead_queue_target_per_staff or DEFAULT_LEAD_QUEUE_LIMIT))


def _today_range():
    today = timezone.localdate()
    start = timezone.make_aware(timezone.datetime.combine(today, timezone.datetime.min.time()))
    end = timezone.make_aware(timezone.datetime.combine(today, timezone.datetime.max.time()))
    return today, start, end


def _format_currency(value):
    rounded = round(float(value or 0), 2)
    return f"Rs. {rounded:,.2f}"


def _format_hours(total_seconds):
    return f"{round((total_seconds or 0) / 3600, 1)}h"


def _format_duration(total_seconds):
    total_seconds = int(total_seconds or 0)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def _format_datetime(value, fallback="--"):
    if not value:
        return fallback
    return timezone.localtime(value).strftime("%d %b %Y, %I:%M %p")


def _week_range(now=None):
    now = now or timezone.now()
    local_now = timezone.localtime(now)
    start_date = local_now.date() - timedelta(days=local_now.weekday())
    start = timezone.make_aware(timezone.datetime.combine(start_date, timezone.datetime.min.time()))
    return start, now


def _month_range(now=None):
    now = now or timezone.now()
    local_now = timezone.localtime(now)
    start_date = local_now.date().replace(day=1)
    start = timezone.make_aware(timezone.datetime.combine(start_date, timezone.datetime.min.time()))
    return start, now


def _decimal_hours(total_seconds):
    return Decimal(str(total_seconds or 0)) / Decimal("3600")


def _decimal_minutes(total_seconds):
    return Decimal(str(total_seconds or 0)) / Decimal("60")


def _money(value):
    return Decimal(value or 0).quantize(TWOPLACES)


def _staff_period_totals(start, end):
    session_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Session.objects.filter(login_time__range=(start, end))
        .values("staff_id")
        .annotate(total=Sum("active_seconds"))
    }
    call_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Call.objects.filter(start_time__range=(start, end), is_qualifying=True)
        .values("staff_id")
        .annotate(total=Sum("duration_seconds"))
    }
    converted_counts = Counter(
        Call.objects.filter(start_time__range=(start, end), status=Call.Status.CONVERTED, is_qualifying=True)
        .values_list("staff_id", flat=True)
    )
    return session_totals, call_totals, converted_counts


def _calculate_base_pay(staff, active_hours):
    active_hours = Decimal(active_hours or 0)
    compensation_type = staff.compensation_type or Staff.CompensationType.HOURLY

    if compensation_type == Staff.CompensationType.WEEKLY:
        target_hours = Decimal(str(staff.target_hours_per_week or 0))
        if target_hours <= 0:
            return Decimal("0.00")
        return _money((active_hours / target_hours) * staff.weekly_salary)

    if compensation_type == Staff.CompensationType.MONTHLY:
        target_hours = Decimal(str(staff.target_hours_per_month or 0))
        if target_hours <= 0:
            return Decimal("0.00")
        return _money((active_hours / target_hours) * staff.monthly_salary)

    return _money(active_hours * staff.hourly_rate)


def calculate_staff_payout(staff, *, active_seconds=0, call_seconds=0, converted_leads=0):
    active_hours = _decimal_hours(active_seconds)
    call_minutes = _decimal_minutes(call_seconds)
    call_earnings = _money(call_minutes * staff.call_rate)
    bonus_earnings = _money(Decimal(str(converted_leads or 0)) * staff.bonus_per_conversion)
    base_pay = _calculate_base_pay(staff, active_hours)
    total_pay = _money(base_pay + call_earnings + bonus_earnings)
    return {
        "active_hours": active_hours,
        "call_minutes": call_minutes,
        "converted_leads": int(converted_leads or 0),
        "base_pay": base_pay,
        "call_earnings": call_earnings,
        "bonus_earnings": bonus_earnings,
        "total_pay": total_pay,
    }


def _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown):
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return weekly_breakdown["total_pay"], "This Week"
    return monthly_breakdown["total_pay"], "This Month"


def _salary_setting_target_label(staff):
    if staff.compensation_type == Staff.CompensationType.WEEKLY:
        return f"{staff.target_hours_per_week} hrs / week"
    if staff.compensation_type == Staff.CompensationType.MONTHLY:
        return f"{staff.target_hours_per_month} hrs / month"
    return f"Rs. {float(staff.hourly_rate):,.2f} / hour"


def _bounded_elapsed_seconds(previous, current, max_seconds=ONLINE_WINDOW_SECONDS):
    if not previous or not current:
        return 0
    return max(0, min(int((current - previous).total_seconds()), max_seconds))


def _dedupe_fields(field_names):
    return list(dict.fromkeys(field_names + ["updated_at"]))


def _log_staff_action(
    staff,
    action_type,
    *,
    session=None,
    call=None,
    lead=None,
    app_state=None,
    metadata=None,
):
    return StaffAction.objects.create(
        staff=staff,
        session=session,
        call=call,
        lead=lead,
        action_type=action_type,
        app_state=app_state,
        metadata=metadata or {},
    )


def _active_elapsed_until(session, now):
    if session.last_known_state != Session.AppState.FOREGROUND:
        return 0

    active_until = now
    if session.last_interaction_at:
        idle_cutoff = session.last_interaction_at + timedelta(seconds=IDLE_WARNING_AFTER_SECONDS)
        if idle_cutoff < active_until:
            active_until = idle_cutoff

    return _bounded_elapsed_seconds(session.last_heartbeat_at, active_until)


def _resolve_requested_state(session, requested_state, now, interaction):
    if requested_state == Session.AppState.BACKGROUND:
        return Session.AppState.BACKGROUND
    if requested_state == Session.AppState.WARNING:
        return Session.AppState.WARNING
    if requested_state == Session.AppState.OFFLINE:
        return Session.AppState.OFFLINE

    last_interaction_at = now if interaction else (session.last_interaction_at or now)
    idle_seconds = max(0, int((now - last_interaction_at).total_seconds()))

    if session.last_known_state in {Session.AppState.WARNING, Session.AppState.OFFLINE} and not interaction:
        return session.last_known_state
    if idle_seconds >= IDLE_OFFLINE_AFTER_SECONDS:
        return Session.AppState.OFFLINE
    if idle_seconds >= IDLE_WARNING_AFTER_SECONDS:
        return Session.AppState.WARNING
    return Session.AppState.FOREGROUND


def _close_session(session, now, *, close_reason, auto_generated=False):
    if not session or not session.is_open:
        return session

    session.active_seconds += _active_elapsed_until(session, now)
    session.logout_time = now
    session.is_open = False
    session.last_heartbeat_at = now
    session.close_reason = close_reason
    session.save(
        update_fields=_dedupe_fields(
            [
                "active_seconds",
                "logout_time",
                "is_open",
                "last_heartbeat_at",
                "close_reason",
            ]
        )
    )
    mark_staff_seen(session.staff, now)
    _log_staff_action(
        session.staff,
        StaffAction.ActionType.SESSION_AUTO_ENDED if auto_generated else StaffAction.ActionType.SESSION_ENDED,
        session=session,
        app_state=session.last_known_state,
        metadata={"close_reason": close_reason},
    )
    return session


def reconcile_session(session, now=None):
    if not session or not session.is_open:
        return session

    now = now or timezone.now()
    state_anchor = session.state_changed_at or session.last_heartbeat_at or session.login_time
    warning_anchor = session.warning_started_at or state_anchor

    if (
        session.last_known_state == Session.AppState.BACKGROUND
        and state_anchor
        and (now - state_anchor).total_seconds() >= BACKGROUND_TIMEOUT_SECONDS
    ):
        return _close_session(
            session,
            now,
            close_reason="background_timeout",
            auto_generated=True,
        )

    if (
        session.last_known_state == Session.AppState.WARNING
        and warning_anchor
        and (now - warning_anchor).total_seconds() >= IDLE_WARNING_GRACE_SECONDS
    ):
        session.last_known_state = Session.AppState.OFFLINE
        session.state_changed_at = now
        session.save(update_fields=_dedupe_fields(["last_known_state", "state_changed_at"]))
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.MARKED_OFFLINE,
            session=session,
            app_state=Session.AppState.OFFLINE,
            metadata={"reason": "warning_timeout"},
        )

    return session


def authenticate_staff(phone, password, required_role=None):
    queryset = Staff.objects.filter(phone=phone.strip(), is_active=True)
    if required_role:
        queryset = queryset.filter(role=required_role)

    staff = queryset.first()
    if not staff or not staff.check_password(password):
        return None
    return staff


def mark_staff_seen(staff, seen_at=None):
    staff.last_seen_at = seen_at or timezone.now()
    staff.save(update_fields=["last_seen_at", "updated_at"])


def get_open_session(staff, reconcile=False):
    session = Session.objects.filter(staff=staff, is_open=True).order_by("-login_time").first()
    if reconcile and session:
        session = reconcile_session(session)
        if session and not session.is_open:
            return None
    return session


def _touch_session_interaction(session, now, *, metadata=None):
    if not session or not session.is_open:
        return session

    previous_state = session.last_known_state
    session.active_seconds += _active_elapsed_until(session, now)
    session.last_interaction_at = now
    session.last_heartbeat_at = now

    update_fields = ["active_seconds", "last_interaction_at", "last_heartbeat_at"]
    if previous_state != Session.AppState.FOREGROUND:
        session.last_known_state = Session.AppState.FOREGROUND
        session.state_changed_at = now
        session.warning_started_at = None
        update_fields.extend(["last_known_state", "state_changed_at", "warning_started_at"])

    session.save(update_fields=_dedupe_fields(update_fields))

    if previous_state == Session.AppState.WARNING:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.IDLE_WARNING_ACKNOWLEDGED,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )
    elif previous_state == Session.AppState.OFFLINE:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.RETURNED_ONLINE,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )
    elif previous_state == Session.AppState.BACKGROUND:
        _log_staff_action(
            session.staff,
            StaffAction.ActionType.APP_FOREGROUNDED,
            session=session,
            app_state=Session.AppState.FOREGROUND,
            metadata=metadata or {},
        )

    mark_staff_seen(session.staff, now)
    return session


def _session_status_label(open_session, latest_session=None):
    if open_session:
        return {
            Session.AppState.FOREGROUND: "Working",
            Session.AppState.BACKGROUND: "Away from app",
            Session.AppState.WARNING: "Warning shown",
            Session.AppState.OFFLINE: "Offline",
        }.get(open_session.last_known_state, "Working")

    if latest_session and latest_session.close_reason == "background_timeout":
        return "Stopped after background timeout"
    return "Stopped"


def _staff_online_label(session, active_cutoff):
    if not session:
        return "Offline"
    if session.last_known_state == Session.AppState.FOREGROUND and session.last_heartbeat_at and session.last_heartbeat_at >= active_cutoff:
        return "Online"
    if session.last_known_state == Session.AppState.WARNING:
        return "Warning"
    if session.last_known_state == Session.AppState.BACKGROUND:
        return "Away"
    return "Offline"


def _staff_queryset():
    return Staff.objects.filter(role=Staff.Role.STAFF).order_by("name")


def _normalize_phone(phone_value):
    return re.sub(r"\D+", "", str(phone_value or "")).strip()


def _normalize_column_name(value):
    text = re.sub(r"[^a-z0-9]+", " ", str(value or "").strip().lower())
    return " ".join(text.split())


def _lead_queue_queryset():
    return Lead.objects.filter(status__in=ACTIVE_QUEUE_STATUSES)


def _is_active_queue_status(status):
    return status in ACTIVE_QUEUE_STATUSES


def _daily_completed_call_counts():
    _, start, end = _today_range()
    qualifying_statuses = [
        Call.Status.INTERESTED,
        Call.Status.NOT_INTERESTED,
        Call.Status.NO_ANSWER,
        Call.Status.CALL_BACK,
        Call.Status.CONVERTED,
    ]
    return {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end), status__in=qualifying_statuses)
        .values("staff_id")
        .annotate(count=Count("id"))
    }


def release_staff_queue(staff):
    if not staff:
        return 0
    released = Lead.objects.filter(
        assigned_to=staff,
        status__in=ACTIVE_QUEUE_STATUSES,
    ).update(assigned_to=None, updated_at=timezone.now())
    return released


def _normalize_active_queue_assignments(*, target_staff=None):
    queue_limit = get_lead_queue_limit()
    queue_queryset = _lead_queue_queryset().select_related("assigned_to").exclude(assigned_to=None)
    if target_staff is not None:
        queue_queryset = queue_queryset.filter(assigned_to=target_staff)

    release_ids = []
    kept_counts = defaultdict(int)
    for lead in queue_queryset.order_by(
        "assigned_to_id",
        "-last_contacted_at",
        "-updated_at",
        "created_at",
        "id",
    ):
        assigned_staff = lead.assigned_to
        if not assigned_staff or assigned_staff.role != Staff.Role.STAFF or not assigned_staff.is_active:
            release_ids.append(lead.id)
            continue

        kept_counts[assigned_staff.id] += 1
        if kept_counts[assigned_staff.id] > queue_limit:
            release_ids.append(lead.id)

    if not release_ids:
        return 0

    return Lead.objects.filter(id__in=release_ids).update(
        assigned_to=None,
        updated_at=timezone.now(),
    )


def auto_allocate_leads(*, target_staff=None):
    queue_limit = get_lead_queue_limit()
    _normalize_active_queue_assignments(target_staff=target_staff)
    staff_queryset = _staff_queryset().filter(is_active=True)
    if target_staff is not None:
        staff_queryset = staff_queryset.filter(id=target_staff.id)

    staff_members = list(staff_queryset)
    if not staff_members:
        return {"assigned_count": 0, "remaining_unassigned_count": _lead_queue_queryset().filter(assigned_to=None).count()}

    active_counts = {
        row["assigned_to"]: row["count"]
        for row in _lead_queue_queryset()
        .exclude(assigned_to=None)
        .values("assigned_to")
        .annotate(count=Count("id"))
    }
    completed_today_counts = _daily_completed_call_counts()
    open_lead_ids = list(
        _lead_queue_queryset()
        .filter(assigned_to=None)
        .order_by("created_at", "id")
        .values_list("id", flat=True)
    )
    if not open_lead_ids:
        return {"assigned_count": 0, "remaining_unassigned_count": 0}

    staff_slots = [
        {
            "staff_id": staff.id,
            "name": staff.name.lower(),
            "active_count": active_counts.get(staff.id, 0),
            "completed_today": completed_today_counts.get(staff.id, 0),
        }
        for staff in staff_members
    ]

    assigned_by_staff = defaultdict(list)
    while open_lead_ids:
        staff_slots.sort(
            key=lambda item: (
                item["active_count"],
                -item["completed_today"],
                item["name"],
            )
        )
        assigned_in_pass = False
        for slot in staff_slots:
            if slot["active_count"] >= queue_limit:
                continue
            lead_id = open_lead_ids.pop(0)
            assigned_by_staff[slot["staff_id"]].append(lead_id)
            slot["active_count"] += 1
            assigned_in_pass = True
            if not open_lead_ids:
                break
        if not assigned_in_pass:
            break

    assigned_count = 0
    assigned_at = timezone.now()
    for staff_id, lead_ids in assigned_by_staff.items():
        assigned_count += len(lead_ids)
        Lead.objects.filter(id__in=lead_ids).update(
            assigned_to_id=staff_id,
            updated_at=assigned_at,
        )

    return {
        "assigned_count": assigned_count,
        "remaining_unassigned_count": len(open_lead_ids),
    }


def _decode_csv_bytes(file_bytes):
    for encoding in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return file_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue
    return file_bytes.decode("utf-8", errors="ignore")


def _read_lead_rows_from_upload(uploaded_file):
    file_name = str(getattr(uploaded_file, "name", "")).lower()
    uploaded_file.seek(0)

    if file_name.endswith(".csv"):
        content = _decode_csv_bytes(uploaded_file.read())
        return [row for row in csv.reader(io.StringIO(content)) if any(str(cell or "").strip() for cell in row)]

    if file_name.endswith(".xlsx") or file_name.endswith(".xlsm"):
        if load_workbook is None:
            raise ValueError("Excel import support is not available right now.")
        workbook = load_workbook(uploaded_file, read_only=True, data_only=True)
        worksheet = workbook.active
        rows = []
        for row in worksheet.iter_rows(values_only=True):
            normalized_row = ["" if cell is None else str(cell).strip() for cell in row]
            if any(normalized_row):
                rows.append(normalized_row)
        return rows

    raise ValueError("Upload a CSV or XLSX file.")


def _detect_lead_column_indexes(rows):
    if not rows:
        raise ValueError("The uploaded file is empty.")

    header = rows[0]
    normalized_header = [_normalize_column_name(cell) for cell in header]
    name_index = None
    phone_index = None

    for index, value in enumerate(normalized_header):
        if name_index is None and value in NAME_COLUMN_ALIASES:
            name_index = index
        if phone_index is None and value in PHONE_COLUMN_ALIASES:
            phone_index = index

    has_header_match = name_index is not None or phone_index is not None
    if not has_header_match:
        if len(header) < 2:
            raise ValueError("The file must contain name and phone columns.")
        return 0, 1, rows

    if name_index is None or phone_index is None:
        raise ValueError("The file must include both name and phone columns.")

    return name_index, phone_index, rows[1:]


def import_leads_from_upload(uploaded_file):
    rows = _read_lead_rows_from_upload(uploaded_file)
    name_index, phone_index, data_rows = _detect_lead_column_indexes(rows)

    existing_numbers = {
        _normalize_phone(phone)
        for phone in Lead.objects.values_list("phone", flat=True)
    }
    created_leads = []
    batch_numbers = set()
    skipped_rows = 0

    for row in data_rows:
        row_values = list(row)
        if max(name_index, phone_index) >= len(row_values):
            skipped_rows += 1
            continue

        name = str(row_values[name_index] or "").strip()
        phone = _normalize_phone(row_values[phone_index])
        if not name or len(phone) < 7:
            skipped_rows += 1
            continue
        if phone in existing_numbers or phone in batch_numbers:
            skipped_rows += 1
            continue

        batch_numbers.add(phone)
        created_leads.append(
            Lead(
                name=name[:150],
                phone=phone,
                status=Lead.Status.NEW,
            )
        )

    if created_leads:
        Lead.objects.bulk_create(created_leads)

    allocation = auto_allocate_leads()
    return {
        "created_count": len(created_leads),
        "skipped_count": skipped_rows,
        "assigned_count": allocation["assigned_count"],
        "remaining_unassigned_count": allocation["remaining_unassigned_count"],
        "queue_limit": get_lead_queue_limit(),
    }


def _training_lessons_queryset():
    return TrainingLesson.objects.order_by("sort_order", "-published_at", "title")


def _active_training_lessons_queryset():
    return _training_lessons_queryset().filter(is_active=True)


def _completion_map_for_staff(staff):
    return {
        completion.lesson_id: completion
        for completion in TrainingCompletion.objects.filter(staff=staff).select_related("lesson")
    }


def get_pending_mandatory_lessons(staff):
    completed_lesson_ids = TrainingCompletion.objects.filter(staff=staff).values_list("lesson_id", flat=True)
    return _active_training_lessons_queryset().filter(is_mandatory=True).exclude(id__in=completed_lesson_ids)


def build_staff_learning_payload(staff):
    lessons = list(_active_training_lessons_queryset())
    completion_map = _completion_map_for_staff(staff)
    pending_mandatory_count = 0
    next_required_title = ""
    completed_count = 0
    lesson_rows = []

    for lesson in lessons:
        completion = completion_map.get(lesson.id)
        is_completed = completion is not None
        if is_completed:
            completed_count += 1
        if lesson.is_mandatory and not is_completed:
            pending_mandatory_count += 1
            if not next_required_title:
                next_required_title = lesson.title

        lesson_rows.append(
            {
                "id": str(lesson.id),
                "title": lesson.title,
                "description": lesson.description,
                "video_url": lesson.video_url,
                "search_keywords": lesson.search_keywords,
                "is_active": lesson.is_active,
                "is_mandatory": lesson.is_mandatory,
                "is_completed": is_completed,
                "completed_at": completion.completed_at.isoformat() if completion else None,
                "published_at": lesson.published_at.isoformat() if lesson.published_at else None,
                "published_at_label": _format_datetime(lesson.published_at),
            }
        )

    return {
        "summary": {
            "total_lessons": len(lesson_rows),
            "completed_count": completed_count,
            "pending_mandatory_count": pending_mandatory_count,
            "has_pending_mandatory": pending_mandatory_count > 0,
            "next_required_title": next_required_title,
        },
        "lessons": lesson_rows,
    }


def build_learning_management_payload():
    today = timezone.localdate()
    active_staff_count = _staff_queryset().filter(is_active=True).count()
    completion_counts = {
        row["lesson_id"]: row["count"]
        for row in TrainingCompletion.objects.values("lesson_id").annotate(count=Count("id"))
    }
    lesson_rows = []
    active_count = 0
    mandatory_count = 0
    total_completions = TrainingCompletion.objects.count()

    for lesson in _training_lessons_queryset():
        completed_staff_count = completion_counts.get(lesson.id, 0)
        pending_staff_count = max(active_staff_count - completed_staff_count, 0)
        if lesson.is_active:
            active_count += 1
        if lesson.is_active and lesson.is_mandatory:
            mandatory_count += 1

        if not lesson.is_active:
            status_filter = "inactive"
            status_label = "Inactive"
        elif lesson.is_mandatory:
            status_filter = "mandatory"
            status_label = "Mandatory"
        else:
            status_filter = "optional"
            status_label = "Optional"

        lesson_rows.append(
            {
                "id": str(lesson.id),
                "title": lesson.title,
                "description": lesson.description,
                "video_url": lesson.video_url,
                "search_keywords": lesson.search_keywords,
                "is_active": lesson.is_active,
                "is_mandatory": lesson.is_mandatory,
                "sort_order": lesson.sort_order,
                "published_at": lesson.published_at,
                "published_at_label": _format_datetime(lesson.published_at),
                "completed_staff_count": completed_staff_count,
                "pending_staff_count": pending_staff_count,
                "status_filter": status_filter,
                "status_label": status_label,
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "summary": {
            "active_count": active_count,
            "mandatory_count": mandatory_count,
            "active_staff_count": active_staff_count,
            "total_completions": total_completions,
        },
        "lesson_rows": lesson_rows,
    }


def complete_training_lesson(staff, lesson):
    now = timezone.now()
    completion, created = TrainingCompletion.objects.get_or_create(
        staff=staff,
        lesson=lesson,
        defaults={"completed_at": now},
    )
    if not created and not completion.completed_at:
        completion.completed_at = now
        completion.save(update_fields=["completed_at"])

    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.TRAINING_COMPLETED,
        metadata={
            "lesson_id": str(lesson.id),
            "lesson_title": lesson.title,
            "created": created,
        },
    )
    return completion


def _open_sessions_by_staff():
    open_sessions = {}
    for session in Session.objects.select_related("staff").filter(is_open=True).order_by("-login_time"):
        session = reconcile_session(session)
        if session and session.is_open and session.staff_id not in open_sessions:
            open_sessions[session.staff_id] = session
    return open_sessions


def build_dashboard_payload():
    today, start, end = _today_range()
    staff_queryset = Staff.objects.filter(is_active=True, role=Staff.Role.STAFF)
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    week_start, week_end = _week_range()
    month_start, month_end = _month_range()

    open_sessions = _open_sessions_by_staff()

    active_staff = sum(
        1
        for session in open_sessions.values()
        if session.last_known_state == Session.AppState.FOREGROUND
        and session.last_heartbeat_at
        and session.last_heartbeat_at >= active_cutoff
    )
    total_staff = staff_queryset.count()

    leads = Lead.objects.select_related("assigned_to")
    calls_today = Call.objects.filter(start_time__range=(start, end))
    qualifying_calls_today = calls_today.filter(is_qualifying=True)
    sessions_today = Session.objects.filter(login_time__range=(start, end))

    total_leads = leads.count()
    interested_count = leads.filter(status=Lead.Status.INTERESTED).count()
    converted_count = leads.filter(status=Lead.Status.CONVERTED).count()
    no_answer_count = leads.filter(status=Lead.Status.NO_ANSWER).count()
    callbacks_count = leads.filter(status=Lead.Status.CALL_BACK).count()

    calls_today_count = qualifying_calls_today.count()
    converted_calls_today = qualifying_calls_today.filter(status=Call.Status.CONVERTED).count()
    conversion_rate = round((converted_calls_today / calls_today_count) * 100, 1) if calls_today_count else 0
    work_coverage_pct = round((active_staff / total_staff) * 100) if total_staff else 0
    short_calls_blocked = calls_today.filter(status=Call.Status.INVALID_SHORT).count()

    active_seconds_today = sessions_today.aggregate(total=Sum("active_seconds")).get("total") or 0
    salary_ready = sessions_today.values("staff_id").distinct().count()

    converted_counter = Counter(
        calls_today.filter(status=Call.Status.CONVERTED).values_list("staff_id", flat=True)
    )
    session_totals = {
        row["staff_id"]: row["total"] or 0
        for row in sessions_today.values("staff_id").annotate(total=Sum("active_seconds"))
    }
    call_totals = {
        row["staff_id"]: row["total"] or 0
        for row in qualifying_calls_today.values("staff_id").annotate(total=Sum("duration_seconds"))
    }
    month_session_totals, month_call_totals, month_converted = _staff_period_totals(month_start, month_end)
    week_session_totals, week_call_totals, week_converted = _staff_period_totals(week_start, week_end)
    salary_estimate = Decimal("0.00")
    for staff in staff_queryset:
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, _ = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)
        salary_estimate += current_payable

    trend_rows = (
        Call.objects.filter(start_time__date__gte=today - timedelta(days=6), start_time__date__lte=today)
        .annotate(day=TruncDate("start_time"))
        .values("day")
        .annotate(
            call_count=Count("id", filter=Q(is_qualifying=True)),
            conversion_count=Count("id", filter=Q(status=Call.Status.CONVERTED, is_qualifying=True)),
        )
        .order_by("day")
    )
    trend_map = {row["day"]: row for row in trend_rows}
    trend_labels = []
    trend_calls = []
    trend_conversions = []
    for offset in range(6, -1, -1):
        day = today - timedelta(days=offset)
        trend_labels.append(day.strftime("%a"))
        trend_calls.append(trend_map.get(day, {}).get("call_count", 0))
        trend_conversions.append(trend_map.get(day, {}).get("conversion_count", 0))

    lead_pipeline = {
        "labels": ["New", "Interested", "Call Back", "No Answer", "Converted"],
        "values": [
            leads.filter(status=Lead.Status.NEW).count(),
            interested_count,
            callbacks_count,
            no_answer_count,
            converted_count,
        ],
    }

    top_staff = []
    for staff in staff_queryset.order_by("name")[:5]:
        top_staff.append(
            {
                "label": staff.name.split()[0],
                "active_hours": round((session_totals.get(staff.id, 0) or 0) / 3600, 1),
                "call_minutes": round((call_totals.get(staff.id, 0) or 0) / 60),
            }
        )

    live_staff = []
    for staff in staff_queryset.order_by("name")[:8]:
        session = open_sessions.get(staff.id)
        if session:
            status_label = _session_status_label(session)
            session_hours = round((session.active_seconds or 0) / 3600, 1)
            status_text = f"{status_label} - {session_hours}h active"
        else:
            status_text = "Offline - No active session"

        live_staff.append(
            {
                "name": staff.name,
                "status_text": status_text,
                "is_online": _staff_online_label(session, active_cutoff) == "Online",
            }
        )

    lead_rows = []
    for lead in leads.order_by("-updated_at")[:20]:
        lead_rows.append(
            {
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "last_call": timezone.localtime(lead.last_contacted_at).strftime("%I:%M %p") if lead.last_contacted_at else "Not called yet",
                "next_action": {
                    Lead.Status.NEW: "Assign and dial",
                    Lead.Status.CALL_BACK: "Follow up on schedule",
                    Lead.Status.INTERESTED: "Send offer details",
                    Lead.Status.CONVERTED: "Move to onboarding",
                    Lead.Status.NO_ANSWER: "Retry later",
                    Lead.Status.NOT_INTERESTED: "Keep for reporting",
                }.get(lead.status, "Review"),
            }
        )

    salary_records = []
    for staff in staff_queryset.order_by("name")[:6]:
        staff_hours = round((session_totals.get(staff.id, 0) or 0) / 3600, 1)
        staff_call_minutes = round((call_totals.get(staff.id, 0) or 0) / 60)
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, cycle_label = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)
        salary_records.append(
            {
                "name": staff.name,
                "hours": f"{staff_hours}h",
                "call_time": f"{staff_call_minutes}m",
                "bonus": _format_currency(monthly_breakdown["bonus_earnings"]),
                "final_salary": _format_currency(current_payable),
                "cycle_label": cycle_label,
            }
        )

    team_directory = []
    for staff in staff_queryset.order_by("name"):
        session = open_sessions.get(staff.id)
        team_directory.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "is_active": staff.is_active,
                "online_label": _staff_online_label(session, active_cutoff),
            }
        )

    dashboard = {
        "today_label": today.strftime("%A, %d %b %Y"),
        "staff_active": active_staff,
        "calls_today": calls_today_count,
        "conversion_rate": f"{conversion_rate:.1f}%",
        "callbacks": callbacks_count,
        "work_coverage": work_coverage_pct,
        "short_calls_blocked": short_calls_blocked,
        "salary_ready": salary_ready,
        "total_leads": total_leads,
        "no_answer": no_answer_count,
        "interested": interested_count,
        "converted": converted_count,
        "salary_estimate": _format_currency(salary_estimate),
        "active_hours": _format_hours(active_seconds_today),
    }

    chart_payload = {
        "callVolume": {
            "labels": trend_labels,
            "calls": trend_calls,
            "conversions": trend_conversions,
        },
        "leadPipeline": lead_pipeline,
        "activityBalance": {
            "labels": [item["label"] for item in top_staff],
            "activeHours": [item["active_hours"] for item in top_staff],
            "callMinutes": [item["call_minutes"] for item in top_staff],
        },
    }

    return {
        "dashboard": dashboard,
        "chart_payload": chart_payload,
        "live_staff": live_staff,
        "lead_rows": lead_rows,
        "salary_records": salary_records,
        "team_directory": team_directory,
    }


def build_team_management_payload():
    today, start, end = _today_range()
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    staff_queryset = _staff_queryset()
    open_sessions = _open_sessions_by_staff()

    call_totals = {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end))
        .values("staff_id")
        .annotate(count=Count("id"))
    }
    converted_totals = {
        row["staff_id"]: row["count"]
        for row in Call.objects.filter(start_time__range=(start, end), status=Call.Status.CONVERTED)
        .values("staff_id")
        .annotate(count=Count("id"))
    }
    active_totals = {
        row["staff_id"]: row["total"] or 0
        for row in Session.objects.filter(login_time__range=(start, end))
        .values("staff_id")
        .annotate(total=Sum("active_seconds"))
    }
    assigned_totals = {
        row["assigned_to"]: row["count"]
        for row in _lead_queue_queryset().exclude(assigned_to=None)
        .values("assigned_to")
        .annotate(count=Count("id"))
    }

    team_rows = []
    for staff in staff_queryset:
        session = open_sessions.get(staff.id)
        team_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "is_active": staff.is_active,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "online_label": _staff_online_label(session, active_cutoff),
                "session_state": session.last_known_state if session else "stopped",
                "active_hours_today": _format_hours(active_totals.get(staff.id, 0)),
                "active_seconds_today": active_totals.get(staff.id, 0),
                "calls_today": call_totals.get(staff.id, 0),
                "converted_today": converted_totals.get(staff.id, 0),
                "assigned_leads": assigned_totals.get(staff.id, 0),
                "last_seen": _format_datetime(staff.last_seen_at),
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "team_rows": team_rows,
    }


def build_salary_control_payload():
    hourly_count = 0
    weekly_count = 0
    monthly_count = 0
    salary_rows = []
    for staff in _staff_queryset():
        if staff.compensation_type == Staff.CompensationType.HOURLY:
            hourly_count += 1
        elif staff.compensation_type == Staff.CompensationType.WEEKLY:
            weekly_count += 1
        else:
            monthly_count += 1

        salary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "is_active": staff.is_active,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "hourly_rate": _format_currency(staff.hourly_rate),
                "hourly_rate_raw": str(staff.hourly_rate),
                "weekly_salary": _format_currency(staff.weekly_salary),
                "weekly_salary_raw": str(staff.weekly_salary),
                "monthly_salary": _format_currency(staff.monthly_salary),
                "monthly_salary_raw": str(staff.monthly_salary),
                "target_hours_per_week": float(staff.target_hours_per_week),
                "target_hours_per_month": float(staff.target_hours_per_month),
                "call_rate": _format_currency(staff.call_rate),
                "call_rate_raw": str(staff.call_rate),
                "bonus_per_conversion": _format_currency(staff.bonus_per_conversion),
                "bonus_per_conversion_raw": str(staff.bonus_per_conversion),
                "target_label": _salary_setting_target_label(staff),
            }
        )

    return {
        "summary": {
            "hourly_count": hourly_count,
            "weekly_count": weekly_count,
            "monthly_count": monthly_count,
        },
        "salary_rows": salary_rows,
    }


def build_salary_page_payload():
    today = timezone.localdate()
    week_start, week_end = _week_range()
    month_start, month_end = _month_range()
    week_session_totals, week_call_totals, week_converted = _staff_period_totals(week_start, week_end)
    month_session_totals, month_call_totals, month_converted = _staff_period_totals(month_start, month_end)

    weekly_total = Decimal("0.00")
    monthly_total = Decimal("0.00")
    current_cycle_total = Decimal("0.00")
    hourly_staff_count = 0
    fixed_staff_count = 0
    salary_rows = []

    for staff in _staff_queryset():
        weekly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=week_session_totals.get(staff.id, 0),
            call_seconds=week_call_totals.get(staff.id, 0),
            converted_leads=week_converted.get(staff.id, 0),
        )
        monthly_breakdown = calculate_staff_payout(
            staff,
            active_seconds=month_session_totals.get(staff.id, 0),
            call_seconds=month_call_totals.get(staff.id, 0),
            converted_leads=month_converted.get(staff.id, 0),
        )
        current_payable, cycle_label = _current_cycle_payout(staff, weekly_breakdown, monthly_breakdown)

        weekly_total += weekly_breakdown["total_pay"]
        monthly_total += monthly_breakdown["total_pay"]
        current_cycle_total += current_payable

        if staff.compensation_type == Staff.CompensationType.HOURLY:
            hourly_staff_count += 1
        else:
            fixed_staff_count += 1

        salary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "compensation_type": staff.compensation_type,
                "compensation_type_label": staff.get_compensation_type_display(),
                "target_label": _salary_setting_target_label(staff),
                "weekly_hours": round(float(weekly_breakdown["active_hours"]), 2),
                "monthly_hours": round(float(monthly_breakdown["active_hours"]), 2),
                "weekly_hours_label": f"{round(float(weekly_breakdown['active_hours']), 1)}h",
                "monthly_hours_label": f"{round(float(monthly_breakdown['active_hours']), 1)}h",
                "weekly_base": _format_currency(weekly_breakdown["base_pay"]),
                "weekly_call": _format_currency(weekly_breakdown["call_earnings"]),
                "weekly_bonus": _format_currency(weekly_breakdown["bonus_earnings"]),
                "weekly_total": _format_currency(weekly_breakdown["total_pay"]),
                "monthly_base": _format_currency(monthly_breakdown["base_pay"]),
                "monthly_call": _format_currency(monthly_breakdown["call_earnings"]),
                "monthly_bonus": _format_currency(monthly_breakdown["bonus_earnings"]),
                "monthly_total": _format_currency(monthly_breakdown["total_pay"]),
                "current_cycle_label": cycle_label,
                "current_payable_raw": current_payable,
                "current_payable": _format_currency(current_payable),
            }
        )

    top_row = max(
        salary_rows,
        key=lambda row: row["current_payable_raw"],
        default=None,
    )
    for row in salary_rows:
        row.pop("current_payable_raw", None)

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "week_label": f"Week of {timezone.localtime(week_start).strftime('%d %b %Y')}",
        "month_label": today.strftime("%B %Y"),
        "summary": {
            "weekly_total": _format_currency(weekly_total),
            "monthly_total": _format_currency(monthly_total),
            "current_cycle_total": _format_currency(current_cycle_total),
            "hourly_staff_count": hourly_staff_count,
            "fixed_staff_count": fixed_staff_count,
            "top_payout_name": top_row["name"] if top_row else "No staff data",
            "top_payout_value": top_row["current_payable"] if top_row else _format_currency(0),
        },
        "salary_rows": salary_rows,
    }


def build_settings_payload(current_user):
    company_profile = get_company_profile()
    company_details = [
        ("Company Email", company_profile.company_email or "Not added yet"),
        ("Company Phone", company_profile.company_phone or "Not added yet"),
        ("Support Phone", company_profile.support_phone or "Not added yet"),
        ("Website", company_profile.website or "Not added yet"),
        ("Tax ID", company_profile.tax_identifier or "Not added yet"),
        ("Country", company_profile.country or "Not added yet"),
        ("Lead Target / Staff", str(get_lead_queue_limit())),
    ]
    address_parts = [
        company_profile.address_line_1,
        company_profile.address_line_2,
        company_profile.city,
        company_profile.state,
        company_profile.postal_code,
        company_profile.country,
    ]
    formatted_address = ", ".join(part for part in address_parts if part) or "Not added yet"

    return {
        "company_profile": company_profile,
        "profile_summary": {
            "name": current_user.name,
            "phone": current_user.phone,
            "role_label": current_user.get_role_display(),
            "last_seen": _format_datetime(current_user.last_seen_at),
            "status_label": "Active" if current_user.is_active else "Inactive",
        },
        "company_summary": {
            "address": formatted_address,
            "description": company_profile.description or "Add company details, address, and support information here.",
            "details": company_details,
        },
    }


def build_lead_management_payload():
    auto_allocate_leads()
    leads = Lead.objects.select_related("assigned_to").order_by("-updated_at")
    active_queue = _lead_queue_queryset()
    queue_limit = get_lead_queue_limit()
    staff_options = [
        {"id": str(staff.id), "name": staff.name}
        for staff in _staff_queryset().filter(is_active=True)
    ]

    lead_rows = []
    for lead in leads:
        lead_rows.append(
            {
                "id": str(lead.id),
                "name": lead.name,
                "phone": lead.phone,
                "status": lead.status,
                "status_label": lead.get_status_display(),
                "assigned_to_id": str(lead.assigned_to_id) if lead.assigned_to_id else "",
                "assigned_to": lead.assigned_to.name if lead.assigned_to else "Unassigned",
                "notes": lead.notes,
                "last_contacted": _format_datetime(lead.last_contacted_at, fallback="Not called yet"),
                "updated_at": _format_datetime(lead.updated_at),
            }
        )

    return {
        "lead_rows": lead_rows,
        "staff_options": staff_options,
        "queue_summary": {
            "active_queue_total": active_queue.count(),
            "unassigned_total": active_queue.filter(assigned_to=None).count(),
            "staff_active_count": _staff_queryset().filter(is_active=True).count(),
            "queue_limit": queue_limit,
        },
    }


def build_call_detail_payload(limit=200):
    calls = Call.objects.select_related("staff", "lead").order_by("-start_time")[:limit]
    call_rows = []
    for call in calls:
        call_rows.append(
            {
                "id": str(call.id),
                "staff_name": call.staff.name,
                "lead_name": call.lead.name,
                "lead_phone": call.lead.phone,
                "start_time": _format_datetime(call.start_time),
                "end_time": _format_datetime(call.end_time),
                "duration_seconds": call.duration_seconds,
                "duration_label": _format_duration(call.duration_seconds),
                "status": call.status,
                "status_label": call.get_status_display(),
                "is_qualifying": call.is_qualifying,
            }
        )

    return {"call_rows": call_rows}


def build_work_hours_payload():
    today, start, end = _today_range()
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    open_sessions = _open_sessions_by_staff()

    sessions_today = Session.objects.filter(login_time__range=(start, end)).select_related("staff").order_by("-login_time")
    totals = {
        row["staff_id"]: row["total"] or 0
        for row in sessions_today.values("staff_id").annotate(total=Sum("active_seconds"))
    }
    session_counts = {
        row["staff_id"]: row["count"]
        for row in sessions_today.values("staff_id").annotate(count=Count("id"))
    }
    first_login_map = {}
    last_logout_map = {}
    for session in sessions_today:
        first_login_map[session.staff_id] = min(
            session.login_time,
            first_login_map.get(session.staff_id, session.login_time),
        )
        if session.logout_time:
            last_logout_map[session.staff_id] = max(
                session.logout_time,
                last_logout_map.get(session.staff_id, session.logout_time),
            )

    summary_rows = []
    for staff in _staff_queryset():
        session = open_sessions.get(staff.id)
        summary_rows.append(
            {
                "id": str(staff.id),
                "name": staff.name,
                "phone": staff.phone,
                "active_hours_today": _format_hours(totals.get(staff.id, 0)),
                "active_seconds_today": totals.get(staff.id, 0),
                "session_count_today": session_counts.get(staff.id, 0),
                "first_login": _format_datetime(first_login_map.get(staff.id)),
                "last_logout": _format_datetime(last_logout_map.get(staff.id)),
                "state_label": _session_status_label(session),
                "online_label": _staff_online_label(session, active_cutoff),
            }
        )

    session_rows = []
    for session in sessions_today[:200]:
        session_rows.append(
            {
                "id": str(session.id),
                "staff_name": session.staff.name,
                "login_time": _format_datetime(session.login_time),
                "logout_time": _format_datetime(session.logout_time),
                "active_seconds": session.active_seconds,
                "active_label": _format_duration(session.active_seconds),
                "last_known_state": session.last_known_state,
                "close_reason": session.close_reason or "Manual",
                "is_open": session.is_open,
            }
        )

    return {
        "today_label": today.strftime("%A, %d %b %Y"),
        "summary_rows": summary_rows,
        "session_rows": session_rows,
    }


def start_staff_session(staff):
    now = timezone.now()
    session = get_open_session(staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "start_work_reuse"})
        return session, False

    pending_lessons = list(get_pending_mandatory_lessons(staff)[:20])
    if pending_lessons:
        pending_payload = build_staff_learning_payload(staff)
        _log_staff_action(
            staff,
            StaffAction.ActionType.TRAINING_REQUIRED_BLOCKED,
            metadata={
                "pending_mandatory_count": pending_payload["summary"]["pending_mandatory_count"],
                "next_required_title": pending_payload["summary"]["next_required_title"],
            },
        )
        raise TrainingRequiredError(pending_payload)

    auto_allocate_leads(target_staff=staff)
    session = Session.objects.create(
        staff=staff,
        login_time=now,
        last_heartbeat_at=now,
        last_interaction_at=now,
        state_changed_at=now,
        last_known_state=Session.AppState.FOREGROUND,
        is_open=True,
    )
    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.SESSION_STARTED,
        session=session,
        app_state=Session.AppState.FOREGROUND,
        metadata={"source": "manual_start"},
    )
    return session, True


def record_session_heartbeat(staff, state, *, interaction=False, source="timer"):
    session = get_open_session(staff)
    if not session:
        return None

    now = timezone.now()
    session = reconcile_session(session, now=now)
    if not session or not session.is_open:
        return None

    previous_state = session.last_known_state
    session.active_seconds += _active_elapsed_until(session, now)
    session.last_heartbeat_at = now
    session.heartbeat_count += 1

    if interaction:
        session.last_interaction_at = now

    requested_state = _resolve_requested_state(session, state, now, interaction)
    update_fields = ["active_seconds", "last_heartbeat_at", "heartbeat_count"]

    if interaction:
        update_fields.append("last_interaction_at")

    if requested_state != previous_state:
        session.last_known_state = requested_state
        session.state_changed_at = now
        update_fields.extend(["last_known_state", "state_changed_at"])

    if requested_state == Session.AppState.WARNING:
        if previous_state != Session.AppState.WARNING or session.warning_started_at is None:
            session.warning_started_at = now
            update_fields.append("warning_started_at")
    elif session.warning_started_at is not None:
        session.warning_started_at = None
        update_fields.append("warning_started_at")

    session.save(update_fields=_dedupe_fields(update_fields))
    mark_staff_seen(staff, now)

    action_type = None
    if requested_state == Session.AppState.BACKGROUND and previous_state != Session.AppState.BACKGROUND:
        action_type = StaffAction.ActionType.APP_BACKGROUNDED
    elif requested_state == Session.AppState.WARNING and previous_state != Session.AppState.WARNING:
        action_type = StaffAction.ActionType.IDLE_WARNING
    elif requested_state == Session.AppState.OFFLINE and previous_state != Session.AppState.OFFLINE:
        action_type = StaffAction.ActionType.MARKED_OFFLINE
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.WARNING:
        action_type = StaffAction.ActionType.IDLE_WARNING_ACKNOWLEDGED if interaction else None
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.OFFLINE and interaction:
        action_type = StaffAction.ActionType.RETURNED_ONLINE
    elif requested_state == Session.AppState.FOREGROUND and previous_state == Session.AppState.BACKGROUND:
        action_type = StaffAction.ActionType.APP_FOREGROUNDED

    if action_type:
        _log_staff_action(
            staff,
            action_type,
            session=session,
            app_state=requested_state,
            metadata={"source": source, "interaction": interaction},
        )

    return session


def end_staff_session(staff, *, close_reason="manual"):
    session = get_open_session(staff)
    if not session:
        return None

    now = timezone.now()
    session = reconcile_session(session, now=now)
    if not session or not session.is_open:
        return None

    return _close_session(
        session,
        now,
        close_reason=close_reason,
        auto_generated=close_reason != "manual",
    )


def build_staff_today_payload(staff):
    today, start, end = _today_range()
    sessions_today = Session.objects.filter(staff=staff, login_time__range=(start, end))
    calls_today = Call.objects.filter(staff=staff, start_time__range=(start, end))
    qualifying_calls = calls_today.filter(is_qualifying=True)
    assigned_leads = Lead.objects.filter(assigned_to=staff)
    open_session = get_open_session(staff, reconcile=True)
    latest_session = sessions_today.order_by("-login_time").first()
    learning_payload = build_staff_learning_payload(staff)

    active_seconds = sessions_today.aggregate(total=Sum("active_seconds")).get("total") or 0
    calls_count = qualifying_calls.count()
    interested_count = assigned_leads.filter(status=Lead.Status.INTERESTED).count()
    converted_count = assigned_leads.filter(status=Lead.Status.CONVERTED).count()

    return {
        "today": today.isoformat(),
        "summary": {
            "active_seconds": active_seconds,
            "active_label": _format_hours(active_seconds),
            "calls_count": calls_count,
            "interested_count": interested_count,
            "converted_count": converted_count,
            "result_label": f"{interested_count} interested / {converted_count} converted",
            "working_now": bool(open_session),
            "current_state": open_session.last_known_state if open_session else "stopped",
            "status_label": _session_status_label(open_session, latest_session=latest_session),
            "close_reason": latest_session.close_reason if latest_session else "",
            "pending_training_count": learning_payload["summary"]["pending_mandatory_count"],
            "training_required": learning_payload["summary"]["has_pending_mandatory"],
            "next_training_title": learning_payload["summary"]["next_required_title"],
        },
        "session": {
            "id": str(open_session.id),
            "is_open": open_session.is_open,
            "last_known_state": open_session.last_known_state,
            "active_seconds": open_session.active_seconds,
            "last_interaction_at": open_session.last_interaction_at.isoformat() if open_session.last_interaction_at else None,
            "warning_started_at": open_session.warning_started_at.isoformat() if open_session.warning_started_at else None,
            "close_reason": open_session.close_reason,
        }
        if open_session
        else None,
    }


def get_assigned_leads(staff):
    auto_allocate_leads(target_staff=staff)
    return (
        Lead.objects.filter(assigned_to=staff, status__in=ACTIVE_QUEUE_STATUSES)
        .select_related("assigned_to")
        .order_by("-updated_at")
    )


def start_staff_call(staff, lead):
    now = timezone.now()
    session = get_open_session(staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_start"})

    call = Call.objects.create(
        staff=staff,
        lead=lead,
        start_time=now,
        status=Call.Status.STARTED,
    )
    lead.last_contacted_at = now
    lead.save(update_fields=["last_contacted_at", "updated_at"])
    mark_staff_seen(staff, now)
    _log_staff_action(
        staff,
        StaffAction.ActionType.CALL_STARTED,
        session=session,
        call=call,
        lead=lead,
        app_state=session.last_known_state if session else None,
        metadata={"lead_name": lead.name},
    )
    return call


def end_staff_call(call, status=None, *, duration_seconds=None, ended_at=None, source="app"):
    if call.end_time:
        return call

    now = timezone.now()
    session = get_open_session(call.staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_end"})

    resolved_duration = None if duration_seconds is None else max(0, int(duration_seconds))
    resolved_end_time = ended_at
    if resolved_end_time is None and resolved_duration is not None:
        resolved_end_time = call.start_time + timedelta(seconds=resolved_duration)
    if resolved_end_time is None:
        resolved_end_time = now
    if resolved_end_time < call.start_time:
        resolved_end_time = call.start_time + timedelta(seconds=resolved_duration or 0)

    if resolved_duration is None:
        resolved_duration = max(0, int((resolved_end_time - call.start_time).total_seconds()))

    if duration_seconds is not None:
        call.start_time = resolved_end_time - timedelta(seconds=resolved_duration)

    requested_status = status
    call.end_time = resolved_end_time
    call.duration_seconds = resolved_duration
    call.is_qualifying = call.duration_seconds >= SHORT_CALL_SECONDS
    if not call.is_qualifying and requested_status == Call.Status.NO_ANSWER:
        call.status = Call.Status.NO_ANSWER
    else:
        call.status = Call.Status.INVALID_SHORT if not call.is_qualifying else call.status
    call.save(
        update_fields=[
            "start_time",
            "end_time",
            "duration_seconds",
            "is_qualifying",
            "status",
            "updated_at",
        ]
    )

    call.lead.last_contacted_at = call.end_time
    call.lead.save(update_fields=["last_contacted_at", "updated_at"])

    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_ENDED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={
            "duration_seconds": call.duration_seconds,
            "is_qualifying": call.is_qualifying,
            "status": call.status,
            "source": source,
            "ended_at": call.end_time.isoformat(),
        },
    )

    if requested_status and (call.is_qualifying or requested_status == Call.Status.NO_ANSWER):
        update_staff_call_status(call, requested_status)
    return call


def update_staff_call_status(call, status):
    if call.status == Call.Status.INVALID_SHORT:
        return call

    now = timezone.now()
    session = get_open_session(call.staff, reconcile=True)
    if session:
        _touch_session_interaction(session, now, metadata={"source": "call_status"})

    call.status = status
    call.save(update_fields=["status", "updated_at"])
    call.lead.status = status
    call.lead.last_contacted_at = call.end_time or now
    call.lead.save(update_fields=["status", "last_contacted_at", "updated_at"])

    _log_staff_action(
        call.staff,
        StaffAction.ActionType.CALL_STATUS_UPDATED,
        session=session,
        call=call,
        lead=call.lead,
        app_state=session.last_known_state if session else None,
        metadata={"status": status},
    )
    if status in TERMINAL_QUEUE_STATUSES:
        auto_allocate_leads(target_staff=call.staff)
    return call


def read_root_file(filename):
    return (settings.BASE_DIR / filename).read_text(encoding="utf-8")
