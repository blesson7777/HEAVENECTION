from datetime import timedelta
from random import choice, randint

from django.core.management.base import BaseCommand
from django.utils import timezone

from backend.apps.telecalling.models import Call, CompanyProfile, Lead, Session, Staff


class Command(BaseCommand):
    help = "Seed demo telecalling data for the Heavenection dashboard."

    def handle(self, *args, **options):
        CompanyProfile.objects.update_or_create(
            id=1,
            defaults={
                "company_name": "Heavenection",
                "description": "Telecalling operations, staff monitoring, and salary tracking.",
                "country": "India",
            },
        )

        if Staff.objects.filter(role=Staff.Role.STAFF).exists():
            self.stdout.write(self.style.WARNING("Demo data already exists."))
            return

        admin = Staff.objects.create_user(
            phone="9999999999",
            password="admin123",
            name="Heavenection Admin",
            role=Staff.Role.ADMIN,
        )
        admin.is_staff = True
        admin.save()

        staff_members = []
        names = ["Asha Patel", "Deepak Roy", "Neha Sharma", "Rahul Das", "Pooja Singh"]
        for index, name in enumerate(names, start=1):
            staff = Staff.objects.create_user(
                phone=f"900000000{index}",
                password="staff123",
                name=name,
                role=Staff.Role.STAFF,
                hourly_rate=150 + (index * 10),
                call_rate=3 + index,
                bonus_per_conversion=400 + (index * 25),
                last_seen_at=timezone.now() - timedelta(seconds=randint(5, 60)),
            )
            staff_members.append(staff)

        statuses = [
            Lead.Status.NEW,
            Lead.Status.INTERESTED,
            Lead.Status.CALL_BACK,
            Lead.Status.NO_ANSWER,
            Lead.Status.CONVERTED,
        ]

        leads = []
        for index in range(1, 31):
            lead = Lead.objects.create(
                name=f"Lead {index}",
                phone=f"+91990000{100 + index}",
                status=choice(statuses),
                assigned_to=choice(staff_members),
                last_contacted_at=timezone.now() - timedelta(minutes=randint(10, 480)),
            )
            leads.append(lead)

        for staff in staff_members:
            active_seconds = randint(3, 6) * 3600 + randint(0, 59) * 60
            Session.objects.create(
                staff=staff,
                login_time=timezone.now() - timedelta(hours=6),
                active_seconds=active_seconds,
                last_heartbeat_at=timezone.now() - timedelta(seconds=randint(10, 70)),
                heartbeat_count=randint(40, 120),
                last_known_state="foreground",
                is_open=True,
            )

        call_statuses = [
            Call.Status.INTERESTED,
            Call.Status.NO_ANSWER,
            Call.Status.CALL_BACK,
            Call.Status.CONVERTED,
            Call.Status.INVALID_SHORT,
        ]

        for lead in leads:
            duration_seconds = randint(8, 420)
            status = choice(call_statuses)
            if status == Call.Status.INVALID_SHORT:
                duration_seconds = randint(1, 4)
            Call.objects.create(
                staff=lead.assigned_to,
                lead=lead,
                start_time=timezone.now() - timedelta(minutes=randint(5, 720)),
                end_time=timezone.now() - timedelta(minutes=randint(1, 4)),
                duration_seconds=duration_seconds,
                status=status,
                is_qualifying=duration_seconds >= 5 and status != Call.Status.INVALID_SHORT,
            )

        self.stdout.write(self.style.SUCCESS("Demo telecalling data created."))
