from decimal import Decimal

from django.db import migrations, models


def set_default_conversion_bonus(apps, schema_editor):
    Staff = apps.get_model("telecalling", "Staff")
    Staff.objects.filter(bonus_per_conversion=Decimal("500.00")).update(
        bonus_per_conversion=Decimal("10.00")
    )


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0024_normalize_callback_to_followup"),
    ]

    operations = [
        migrations.AlterField(
            model_name="staff",
            name="bonus_per_conversion",
            field=models.DecimalField(decimal_places=2, default=10, max_digits=10),
        ),
        migrations.RunPython(set_default_conversion_bonus, migrations.RunPython.noop),
    ]
