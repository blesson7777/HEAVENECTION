from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0031_companyprofile_work_review_rules"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="followup_auto_expire_days",
            field=models.PositiveIntegerField(default=14),
        ),
        migrations.AddField(
            model_name="companyprofile",
            name="followup_auto_expire_enabled",
            field=models.BooleanField(default=True),
        ),
    ]
