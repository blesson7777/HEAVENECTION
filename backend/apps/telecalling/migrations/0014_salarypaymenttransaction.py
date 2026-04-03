from decimal import Decimal

from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone
import uuid


def seed_salary_payment_transactions(apps, schema_editor):
    Salary = apps.get_model("telecalling", "Salary")
    SalaryPaymentTransaction = apps.get_model("telecalling", "SalaryPaymentTransaction")

    for salary in Salary.objects.filter(is_paid=True).exclude(paid_amount__lte=Decimal("0.00")):
        if SalaryPaymentTransaction.objects.filter(salary_record_id=salary.id).exists():
            continue
        SalaryPaymentTransaction.objects.create(
            salary_record_id=salary.id,
            amount=salary.paid_amount,
            payment_method=salary.payment_method,
            payment_reference=salary.payment_reference,
            payment_note=salary.payment_note,
            paid_at=salary.paid_at or django.utils.timezone.now(),
        )


def noop_reverse(apps, schema_editor):
    return


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0013_staff_auth_session_key"),
    ]

    operations = [
        migrations.CreateModel(
            name="SalaryPaymentTransaction",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("amount", models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                (
                    "payment_method",
                    models.CharField(
                        blank=True,
                        choices=[
                            ("bank_transfer", "Bank Transfer"),
                            ("cash", "Cash"),
                            ("upi", "UPI"),
                            ("cheque", "Cheque"),
                            ("other", "Other"),
                        ],
                        default="",
                        max_length=30,
                    ),
                ),
                ("payment_reference", models.CharField(blank=True, max_length=120)),
                ("payment_note", models.TextField(blank=True)),
                ("paid_at", models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "salary_record",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="payment_transactions",
                        to="telecalling.salary",
                    ),
                ),
            ],
            options={
                "ordering": ("-paid_at", "-created_at"),
            },
        ),
        migrations.RunPython(seed_salary_payment_transactions, noop_reverse),
    ]
