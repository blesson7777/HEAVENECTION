import os

from django.core.management.base import BaseCommand

from backend.apps.telecalling.models import Staff


class Command(BaseCommand):
    help = "Create or update the initial admin account from environment variables."

    def handle(self, *args, **options):
        phone = os.getenv("BOOTSTRAP_ADMIN_PHONE", "").strip()
        password = os.getenv("BOOTSTRAP_ADMIN_PASSWORD", "").strip()
        name = os.getenv("BOOTSTRAP_ADMIN_NAME", "HEAVENECTION Admin").strip() or "HEAVENECTION Admin"
        email = os.getenv("BOOTSTRAP_ADMIN_EMAIL", "").strip().lower()

        if not phone or not password:
            self.stdout.write(self.style.WARNING("Skipping admin bootstrap: BOOTSTRAP_ADMIN_PHONE or BOOTSTRAP_ADMIN_PASSWORD not set."))
            return

        admin = Staff.objects.filter(phone=phone).first()
        created = admin is None
        if admin is None:
            admin = Staff(phone=phone)

        admin.name = name
        admin.email = email
        admin.role = Staff.Role.ADMIN
        admin.is_active = True
        admin.is_staff = True
        admin.is_superuser = True
        admin.set_password(password)
        admin.save()

        action = "Created" if created else "Updated"
        self.stdout.write(self.style.SUCCESS(f"{action} admin account for {phone}."))
