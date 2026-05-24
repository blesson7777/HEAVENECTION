from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0034_companyprofile_followup_staff_warning_days"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="followup_sla_gate_enabled",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="followup_sla_gate_mode",
            field=models.CharField(
                choices=[
                    ("allow_normal_calls", "Allow normal lead calls"),
                    ("require_one_followup_call", "Require one follow-up call first"),
                ],
                default="allow_normal_calls",
                max_length=40,
            ),
        ),
    ]
