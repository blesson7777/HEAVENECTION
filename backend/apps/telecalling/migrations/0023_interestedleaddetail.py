from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0022_lead_readd_count"),
    ]

    operations = [
        migrations.CreateModel(
            name="InterestedLeadDetail",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("customer_name", models.CharField(max_length=150)),
                ("customer_phone", models.CharField(db_index=True, max_length=20)),
                ("product_enquired", models.CharField(max_length=150)),
                ("enquiry_notes", models.TextField(blank=True)),
                ("preferred_call_time", models.CharField(blank=True, default="", max_length=120)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "call",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="interested_lead_details",
                        to="telecalling.call",
                    ),
                ),
                (
                    "lead",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="interested_detail",
                        to="telecalling.lead",
                    ),
                ),
                (
                    "staff",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="interested_lead_details",
                        to="telecalling.staff",
                    ),
                ),
            ],
            options={
                "ordering": ("-updated_at",),
            },
        ),
    ]
