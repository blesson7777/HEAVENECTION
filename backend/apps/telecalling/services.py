import json
from collections import Counter
from datetime import timedelta
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.db.models import Count, Q, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from backend.apps.telecalling.models import Call, Lead, Salary, Session, Staff


ONLINE_WINDOW_SECONDS = 90


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


def build_dashboard_payload():
    today, start, end = _today_range()
    staff_queryset = Staff.objects.filter(is_active=True, role=Staff.Role.STAFF)
    active_cutoff = timezone.now() - timedelta(seconds=ONLINE_WINDOW_SECONDS)
    active_staff = staff_queryset.filter(last_seen_at__gte=active_cutoff).count()
    total_staff = staff_queryset.count()

    leads = Lead.objects.select_related("assigned_to")
    leads_today = leads.filter(updated_at__range=(start, end))
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

    salary_estimate = Decimal("0")
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

    for staff in staff_queryset:
        hours = Decimal(str((session_totals.get(staff.id, 0) or 0) / 3600))
        call_minutes = Decimal(str((call_totals.get(staff.id, 0) or 0) / 60))
        conversions = Decimal(str(converted_counter.get(staff.id, 0)))
        salary_estimate += (
            (hours * staff.hourly_rate)
            + (call_minutes * staff.call_rate)
            + (conversions * staff.bonus_per_conversion)
        )

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
    open_sessions = {
        session.staff_id: session
        for session in Session.objects.select_related("staff").filter(is_open=True)
    }
    for staff in staff_queryset.order_by("name")[:8]:
        session = open_sessions.get(staff.id)
        live_staff.append(
            {
                "name": staff.name,
                "status_text": (
                    f"Online - {session.last_known_state.title()} - Session {round(session.active_seconds / 3600, 1)}h"
                    if session
                    else "Offline - No active session"
                ),
                "is_online": bool(staff.last_seen_at and staff.last_seen_at >= active_cutoff),
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
        staff_bonus = Decimal(str(converted_counter.get(staff.id, 0))) * staff.bonus_per_conversion
        final_salary = (
            Decimal(str(staff_hours)) * staff.hourly_rate
            + Decimal(str(staff_call_minutes)) * staff.call_rate
            + staff_bonus
        )
        salary_records.append(
            {
                "name": staff.name,
                "hours": f"{staff_hours}h",
                "call_time": f"{staff_call_minutes}m",
                "bonus": _format_currency(staff_bonus),
                "final_salary": _format_currency(final_salary),
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
    }


def read_root_file(filename):
    return (settings.BASE_DIR / filename).read_text(encoding="utf-8")
