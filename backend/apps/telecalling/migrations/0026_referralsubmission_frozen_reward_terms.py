from django.db import migrations, models


def freeze_existing_referral_terms(apps, schema_editor):
    CompanyProfile = apps.get_model("telecalling", "CompanyProfile")
    ReferralReward = apps.get_model("telecalling", "ReferralReward")
    ReferralSubmission = apps.get_model("telecalling", "ReferralSubmission")

    company_profile = CompanyProfile.objects.order_by("pk").first()
    default_required_hours = getattr(company_profile, "referral_required_hours", 0) or 0
    default_reward_amount = getattr(company_profile, "referral_reward_amount", 0) or 0

    reward_map = {
        (reward.referrer_id, reward.referred_staff_id): reward
        for reward in ReferralReward.objects.all().only(
            "referrer_id",
            "referred_staff_id",
            "required_hours",
            "reward_amount",
        )
    }

    for submission in ReferralSubmission.objects.all().only(
        "id",
        "referrer_id",
        "joined_staff_id",
        "required_hours_at_submit",
        "reward_amount_at_submit",
    ):
        reward = None
        if submission.joined_staff_id:
            reward = reward_map.get((submission.referrer_id, submission.joined_staff_id))
        submission.required_hours_at_submit = (
            reward.required_hours if reward else default_required_hours
        )
        submission.reward_amount_at_submit = (
            reward.reward_amount if reward else default_reward_amount
        )
        submission.save(
            update_fields=[
                "required_hours_at_submit",
                "reward_amount_at_submit",
            ]
        )


class Migration(migrations.Migration):

    dependencies = [
        ("telecalling", "0025_staff_bonus_per_conversion_default_10"),
    ]

    operations = [
        migrations.AddField(
            model_name="referralsubmission",
            name="required_hours_at_submit",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=8),
        ),
        migrations.AddField(
            model_name="referralsubmission",
            name="reward_amount_at_submit",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=12),
        ),
        migrations.RunPython(
            freeze_existing_referral_terms,
            migrations.RunPython.noop,
        ),
    ]
