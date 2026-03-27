from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("telecalling", "0005_traininglesson_alter_staffaction_action_type_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="companyprofile",
            name="lead_queue_target_per_staff",
            field=models.PositiveIntegerField(default=1),
        ),
    ]
