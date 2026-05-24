from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0033_companyprofile_followup_monitoring_rules"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="followup_staff_warning_days",
            field=models.PositiveIntegerField(default=7),
        ),
    ]
