from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0032_companyprofile_followup_expiry_settings"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="followup_uncalled_alert_enabled",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="followup_uncalled_alert_hours",
            field=models.PositiveIntegerField(default=24),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="work_review_followup_expired_penalty_cap",
            field=models.PositiveIntegerField(default=24),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="work_review_followup_expired_penalty_points",
            field=models.PositiveIntegerField(default=4),
        ),
    ]
