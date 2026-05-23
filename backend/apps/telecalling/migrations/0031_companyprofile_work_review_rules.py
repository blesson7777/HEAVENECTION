from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0030_alter_lead_status"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="work_review_connected_cooldown_seconds",
            field=models.PositiveIntegerField(default=90),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="work_review_idle_gap_seconds",
            field=models.PositiveIntegerField(default=60),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="work_review_zero_talk_attempt_threshold",
            field=models.PositiveIntegerField(default=10),
        ),
    ]
