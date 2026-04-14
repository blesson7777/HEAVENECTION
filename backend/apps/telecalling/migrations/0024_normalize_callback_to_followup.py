from django.db import migrations


def forwards(apps, schema_editor):
    Lead = apps.get_model("telecalling", "Lead")
    Call = apps.get_model("telecalling", "Call")

    Lead.objects.filter(status="call_back").update(status="interested")
    Call.objects.filter(status="call_back").update(status="interested")


def backwards(apps, schema_editor):
    # Keep reverse as a no-op so existing follow-up data is never rewritten back.
    return


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0023_interestedleaddetail"),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
