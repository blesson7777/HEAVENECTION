int _asInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _joinCallbackScheduleLabel(String dateLabel, String windowLabel) {
  final parts = <String>[
    if (dateLabel.trim().isNotEmpty) dateLabel.trim(),
    if (windowLabel.trim().isNotEmpty) windowLabel.trim(),
  ];
  return parts.join(' • ');
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.versionName,
    required this.versionCode,
    required this.minimumSupportedVersionCode,
    required this.releaseNotes,
    required this.isMandatory,
    required this.downloadUrl,
    required this.fileName,
    required this.publishedAt,
    required this.fileSizeBytes,
  });

  final bool updateAvailable;
  final String versionName;
  final int versionCode;
  final int minimumSupportedVersionCode;
  final String releaseNotes;
  final bool isMandatory;
  final String downloadUrl;
  final String fileName;
  final DateTime? publishedAt;
  final int fileSizeBytes;

  String get fileSizeLabel {
    if (fileSizeBytes <= 0) {
      return '--';
    }
    final mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      updateAvailable: json['update_available'] == true,
      versionName: json['version_name']?.toString() ?? '',
      versionCode: _asInt(json['version_code']),
      minimumSupportedVersionCode: _asInt(
        json['minimum_supported_version_code'],
      ),
      releaseNotes: json['release_notes']?.toString() ?? '',
      isMandatory: json['is_mandatory'] == true,
      downloadUrl: json['download_url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? 'heavenection-update.apk',
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'].toString())?.toLocal(),
      fileSizeBytes: _asInt(json['file_size_bytes']),
    );
  }
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
    required this.packageName,
    required this.canInstallPackages,
  });

  final String versionName;
  final int versionCode;
  final String packageName;
  final bool canInstallPackages;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      versionName: json['versionName']?.toString() ?? '',
      versionCode: _asInt(json['versionCode']),
      packageName: json['packageName']?.toString() ?? '',
      canInstallPackages: json['canInstallPackages'] == true,
    );
  }
}

class StaffUser {
  const StaffUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
  });

  final String id;
  final String name;
  final String phone;
  final String role;

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    return StaffUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
    );
  }
}

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.roleLabel,
    required this.isActive,
    required this.bankAccountName,
    required this.bankName,
    required this.bankAccountNumber,
    required this.bankIfscCode,
    required this.aadharNumber,
    required this.aadharPhotoUrl,
    required this.aadharPhotoName,
    required this.passbookPhotoUrl,
    required this.passbookPhotoName,
    required this.lastSeenAt,
    required this.salarySummary,
    required this.salaryHistory,
    required this.referralProgramEnabled,
    required this.referralRequiredHoursLabel,
    required this.referralRewardAmountLabel,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String roleLabel;
  final bool isActive;
  final String bankAccountName;
  final String bankName;
  final String bankAccountNumber;
  final String bankIfscCode;
  final String aadharNumber;
  final String aadharPhotoUrl;
  final String aadharPhotoName;
  final String passbookPhotoUrl;
  final String passbookPhotoName;
  final DateTime? lastSeenAt;
  final SalarySummary salarySummary;
  final List<SalaryHistoryItem> salaryHistory;
  final bool referralProgramEnabled;
  final String referralRequiredHoursLabel;
  final String referralRewardAmountLabel;

  bool get hasAadharPhoto => aadharPhotoUrl.trim().isNotEmpty;
  bool get hasPassbookPhoto => passbookPhotoUrl.trim().isNotEmpty;

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      roleLabel: json['role_label']?.toString() ?? '',
      isActive: json['is_active'] == true,
      bankAccountName: json['bank_account_name']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      bankAccountNumber: json['bank_account_number']?.toString() ?? '',
      bankIfscCode: json['bank_ifsc_code']?.toString() ?? '',
      aadharNumber: json['aadhar_number']?.toString() ?? '',
      aadharPhotoUrl: json['aadhar_photo_url']?.toString() ?? '',
      aadharPhotoName: json['aadhar_photo_name']?.toString() ?? '',
      passbookPhotoUrl: json['passbook_photo_url']?.toString() ?? '',
      passbookPhotoName: json['passbook_photo_name']?.toString() ?? '',
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.tryParse(json['last_seen_at'].toString())?.toLocal(),
      salarySummary: SalarySummary.fromJson(
        json['salary_summary'] is Map<String, dynamic>
            ? json['salary_summary'] as Map<String, dynamic>
            : const {},
      ),
      salaryHistory:
          (json['salary_history'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SalaryHistoryItem.fromJson)
              .toList() ??
          const [],
      referralProgramEnabled: json['referral_program_enabled'] == true,
      referralRequiredHoursLabel:
          json['referral_required_hours_label']?.toString() ?? '0.0h',
      referralRewardAmountLabel:
          json['referral_reward_amount_label']?.toString() ?? 'Rs. 0.00',
    );
  }
}

class SalarySummary {
  const SalarySummary({
    required this.totalWorkingHours,
    required this.totalWorkingHoursLabel,
    required this.totalEarnedAmount,
    required this.totalEarnedAmountLabel,
    required this.totalPaidAmount,
    required this.totalPaidAmountLabel,
    required this.latestTransactionId,
    required this.latestPaidAtLabel,
  });

  final double totalWorkingHours;
  final String totalWorkingHoursLabel;
  final double totalEarnedAmount;
  final String totalEarnedAmountLabel;
  final double totalPaidAmount;
  final String totalPaidAmountLabel;
  final String latestTransactionId;
  final String latestPaidAtLabel;

  factory SalarySummary.fromJson(Map<String, dynamic> json) {
    return SalarySummary(
      totalWorkingHours: _asDouble(json['total_working_hours']),
      totalWorkingHoursLabel:
          json['total_working_hours_label']?.toString() ?? '0.0h',
      totalEarnedAmount: _asDouble(json['total_earned_amount']),
      totalEarnedAmountLabel:
          json['total_earned_amount_label']?.toString() ?? 'Rs. 0.00',
      totalPaidAmount: _asDouble(json['total_paid_amount']),
      totalPaidAmountLabel:
          json['total_paid_amount_label']?.toString() ?? 'Rs. 0.00',
      latestTransactionId: json['latest_transaction_id']?.toString() ?? '',
      latestPaidAtLabel: json['latest_paid_at_label']?.toString() ?? '--',
    );
  }
}

class SalaryHistoryItem {
  const SalaryHistoryItem({
    required this.id,
    required this.periodLabel,
    required this.payoutCycleLabel,
    required this.totalHours,
    required this.totalHoursLabel,
    required this.finalSalary,
    required this.finalSalaryLabel,
    required this.paidAmount,
    required this.paidAmountLabel,
    required this.paidAt,
    required this.paidAtLabel,
    required this.paymentMethodLabel,
    required this.paymentReference,
    required this.paymentNote,
  });

  final String id;
  final String periodLabel;
  final String payoutCycleLabel;
  final double totalHours;
  final String totalHoursLabel;
  final double finalSalary;
  final String finalSalaryLabel;
  final double paidAmount;
  final String paidAmountLabel;
  final DateTime? paidAt;
  final String paidAtLabel;
  final String paymentMethodLabel;
  final String paymentReference;
  final String paymentNote;

  factory SalaryHistoryItem.fromJson(Map<String, dynamic> json) {
    return SalaryHistoryItem(
      id: json['id']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
      payoutCycleLabel: json['payout_cycle_label']?.toString() ?? '',
      totalHours: _asDouble(json['total_hours']),
      totalHoursLabel: json['total_hours_label']?.toString() ?? '0.0h',
      finalSalary: _asDouble(json['final_salary']),
      finalSalaryLabel:
          json['final_salary_label']?.toString() ??
          json['final_salary']?.toString() ??
          'Rs. 0.00',
      paidAmount: _asDouble(json['paid_amount']),
      paidAmountLabel:
          json['paid_amount_label']?.toString() ??
          json['paid_amount']?.toString() ??
          '',
      paidAt:
          (json['paid_at_iso'] != null
                  ? DateTime.tryParse(json['paid_at_iso'].toString())
                  : null)
              ?.toLocal() ??
          (json['paid_at'] != null
                  ? DateTime.tryParse(json['paid_at'].toString())
                  : null)
              ?.toLocal(),
      paidAtLabel:
          json['paid_at_label']?.toString() ??
          json['paid_at']?.toString() ??
          '',
      paymentMethodLabel: json['payment_method_label']?.toString() ?? '',
      paymentReference: json['payment_reference']?.toString() ?? '',
      paymentNote: json['payment_note']?.toString() ?? '',
    );
  }
}

class SalaryDetailSummary {
  const SalaryDetailSummary({
    required this.compensationType,
    required this.compensationTypeLabel,
    required this.payoutScheduleLabel,
    required this.weeklyPayoutDayLabel,
    required this.hourlyRateLabel,
    required this.callRateLabel,
    required this.bonusPerConversionLabel,
    required this.targetHoursLabel,
  });

  final String compensationType;
  final String compensationTypeLabel;
  final String payoutScheduleLabel;
  final String weeklyPayoutDayLabel;
  final String hourlyRateLabel;
  final String callRateLabel;
  final String bonusPerConversionLabel;
  final String targetHoursLabel;

  factory SalaryDetailSummary.fromJson(Map<String, dynamic> json) {
    return SalaryDetailSummary(
      compensationType: json['compensation_type']?.toString() ?? '',
      compensationTypeLabel:
          json['compensation_type_label']?.toString() ?? 'Hourly',
      payoutScheduleLabel:
          json['payout_schedule_label']?.toString() ?? 'Running earned amount',
      weeklyPayoutDayLabel:
          json['weekly_payout_day_label']?.toString() ?? '',
      hourlyRateLabel: json['hourly_rate_label']?.toString() ?? 'Rs. 0.00',
      callRateLabel: json['call_rate_label']?.toString() ?? 'Rs. 0.00',
      bonusPerConversionLabel:
          json['bonus_per_conversion_label']?.toString() ?? 'Rs. 0.00',
      targetHoursLabel: json['target_hours_label']?.toString() ?? '0.0h',
    );
  }
}

class ConversionRewardItem {
  const ConversionRewardItem({
    required this.id,
    required this.leadId,
    required this.leadName,
    required this.leadPhone,
    required this.rewardAmountLabel,
    required this.convertedAtLabel,
  });

  final String id;
  final String leadId;
  final String leadName;
  final String leadPhone;
  final String rewardAmountLabel;
  final String convertedAtLabel;

  factory ConversionRewardItem.fromJson(Map<String, dynamic> json) {
    return ConversionRewardItem(
      id: json['id']?.toString() ?? '',
      leadId: json['lead_id']?.toString() ?? '',
      leadName: json['lead_name']?.toString() ?? 'Lead',
      leadPhone: json['lead_phone']?.toString() ?? '--',
      rewardAmountLabel:
          json['reward_amount_label']?.toString() ?? 'Rs. 0.00',
      convertedAtLabel: json['converted_at_label']?.toString() ?? '--',
    );
  }
}

class SalaryDetailBlock {
  const SalaryDetailBlock({
    required this.title,
    required this.subtitle,
    required this.periodLabel,
    required this.hoursLabel,
    required this.earnedTotalLabel,
    required this.paidTotalLabel,
    required this.balanceLabel,
    required this.basePayLabel,
    required this.callEarningsLabel,
    required this.conversionRewardLabel,
    required this.hourlyCallBonusLabel,
    required this.bonusEarningsLabel,
    required this.convertedLeadCount,
    required this.conversionRewardRows,
  });

  final String title;
  final String subtitle;
  final String periodLabel;
  final String hoursLabel;
  final String earnedTotalLabel;
  final String paidTotalLabel;
  final String balanceLabel;
  final String basePayLabel;
  final String callEarningsLabel;
  final String conversionRewardLabel;
  final String hourlyCallBonusLabel;
  final String bonusEarningsLabel;
  final int convertedLeadCount;
  final List<ConversionRewardItem> conversionRewardRows;

  factory SalaryDetailBlock.fromJson(Map<String, dynamic> json) {
    return SalaryDetailBlock(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
      hoursLabel: json['hours_label']?.toString() ?? '0.0h',
      earnedTotalLabel: json['earned_total_label']?.toString() ?? 'Rs. 0.00',
      paidTotalLabel: json['paid_total_label']?.toString() ?? 'Rs. 0.00',
      balanceLabel: json['balance_label']?.toString() ?? 'Rs. 0.00',
      basePayLabel: json['base_pay_label']?.toString() ?? 'Rs. 0.00',
      callEarningsLabel:
          json['call_earnings_label']?.toString() ?? 'Rs. 0.00',
      conversionRewardLabel:
          json['conversion_reward_label']?.toString() ?? 'Rs. 0.00',
      hourlyCallBonusLabel:
          json['hourly_call_bonus_label']?.toString() ?? 'Rs. 0.00',
      bonusEarningsLabel:
          json['bonus_earnings_label']?.toString() ?? 'Rs. 0.00',
      convertedLeadCount: _asInt(json['converted_lead_count']),
      conversionRewardRows:
          (json['conversion_reward_rows'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ConversionRewardItem.fromJson)
              .toList() ??
          const [],
    );
  }
}

class SalaryPatternRow {
  const SalaryPatternRow({
    required this.title,
    required this.periodLabel,
    required this.hoursLabel,
    required this.earnedTotalLabel,
    required this.paidTotalLabel,
    required this.balanceLabel,
  });

  final String title;
  final String periodLabel;
  final String hoursLabel;
  final String earnedTotalLabel;
  final String paidTotalLabel;
  final String balanceLabel;

  factory SalaryPatternRow.fromJson(Map<String, dynamic> json) {
    return SalaryPatternRow(
      title: json['title']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
      hoursLabel: json['hours_label']?.toString() ?? '0.0h',
      earnedTotalLabel: json['earned_total_label']?.toString() ?? 'Rs. 0.00',
      paidTotalLabel: json['paid_total_label']?.toString() ?? 'Rs. 0.00',
      balanceLabel: json['balance_label']?.toString() ?? 'Rs. 0.00',
    );
  }
}

class SalaryPatternSection {
  const SalaryPatternSection({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<SalaryPatternRow> rows;

  factory SalaryPatternSection.fromJson(Map<String, dynamic> json) {
    return SalaryPatternSection(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      rows:
          (json['rows'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SalaryPatternRow.fromJson)
              .toList() ??
          const [],
    );
  }
}

class SalaryPaymentHistoryItem {
  const SalaryPaymentHistoryItem({
    required this.id,
    required this.periodLabel,
    required this.payoutCycleLabel,
    required this.totalHoursLabel,
    required this.finalSalaryLabel,
    required this.paidAmountLabel,
    required this.paidAtLabel,
    required this.paymentKindLabel,
    required this.paymentMethodLabel,
    required this.paymentReference,
    required this.paymentNote,
  });

  final String id;
  final String periodLabel;
  final String payoutCycleLabel;
  final String totalHoursLabel;
  final String finalSalaryLabel;
  final String paidAmountLabel;
  final String paidAtLabel;
  final String paymentKindLabel;
  final String paymentMethodLabel;
  final String paymentReference;
  final String paymentNote;

  factory SalaryPaymentHistoryItem.fromJson(Map<String, dynamic> json) {
    return SalaryPaymentHistoryItem(
      id: json['id']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
      payoutCycleLabel: json['payout_cycle_label']?.toString() ?? '',
      totalHoursLabel: json['total_hours_label']?.toString() ?? '0.0h',
      finalSalaryLabel:
          json['final_salary']?.toString() ??
          json['final_salary_label']?.toString() ??
          'Rs. 0.00',
      paidAmountLabel:
          json['paid_amount']?.toString() ??
          json['paid_amount_label']?.toString() ??
          'Rs. 0.00',
      paidAtLabel: json['paid_at']?.toString() ?? json['paid_at_label']?.toString() ?? '--',
      paymentKindLabel:
          json['payment_kind_label']?.toString() ?? 'Payment',
      paymentMethodLabel:
          json['payment_method_label']?.toString() ?? 'Manual',
      paymentReference: json['payment_reference']?.toString() ?? '--',
      paymentNote: json['payment_note']?.toString() ?? '--',
    );
  }
}

class ReferralSummary {
  const ReferralSummary({
    required this.enabled,
    required this.requiredHoursLabel,
    required this.rewardAmountLabel,
    required this.referredByName,
    required this.submittedCount,
    required this.notJoinedCount,
    required this.joinedCount,
    required this.startedWorkingCount,
    required this.completedCount,
    required this.qualifiedCount,
    required this.pendingCount,
    required this.paidCount,
    required this.pendingTotalLabel,
  });

  final bool enabled;
  final String requiredHoursLabel;
  final String rewardAmountLabel;
  final String referredByName;
  final int submittedCount;
  final int notJoinedCount;
  final int joinedCount;
  final int startedWorkingCount;
  final int completedCount;
  final int qualifiedCount;
  final int pendingCount;
  final int paidCount;
  final String pendingTotalLabel;

  factory ReferralSummary.fromJson(Map<String, dynamic> json) {
    return ReferralSummary(
      enabled: json['enabled'] == true,
      requiredHoursLabel: json['required_hours_label']?.toString() ?? '0.0h',
      rewardAmountLabel: json['reward_amount_label']?.toString() ?? 'Rs. 0.00',
      referredByName: json['referred_by_name']?.toString() ?? '',
      submittedCount: _asInt(json['submitted_count']),
      notJoinedCount: _asInt(json['not_joined_count']),
      joinedCount: _asInt(json['joined_count']),
      startedWorkingCount: _asInt(json['started_working_count']),
      completedCount: _asInt(json['completed_count']),
      qualifiedCount: _asInt(json['qualified_count']),
      pendingCount: _asInt(json['pending_count']),
      paidCount: _asInt(json['paid_count']),
      pendingTotalLabel: json['pending_total_label']?.toString() ?? 'Rs. 0.00',
    );
  }
}

class ReferralTrackingItem {
  const ReferralTrackingItem({
    required this.id,
    required this.referredName,
    required this.referredPhone,
    required this.workflowStage,
    required this.workflowStageLabel,
    required this.progressLabel,
    required this.activeHoursLabel,
    required this.requiredHoursLabel,
    required this.rewardAmountLabel,
    required this.rewardStatusLabel,
    required this.joinedStaffName,
    required this.createdAtLabel,
  });

  final String id;
  final String referredName;
  final String referredPhone;
  final String workflowStage;
  final String workflowStageLabel;
  final String progressLabel;
  final String activeHoursLabel;
  final String requiredHoursLabel;
  final String rewardAmountLabel;
  final String rewardStatusLabel;
  final String joinedStaffName;
  final String createdAtLabel;

  factory ReferralTrackingItem.fromJson(Map<String, dynamic> json) {
    return ReferralTrackingItem(
      id: json['id']?.toString() ?? '',
      referredName: json['referred_name']?.toString() ?? '',
      referredPhone: json['referred_phone']?.toString() ?? '',
      workflowStage: json['workflow_stage']?.toString() ?? '',
      workflowStageLabel: json['workflow_stage_label']?.toString() ?? '',
      progressLabel: json['progress_label']?.toString() ?? '',
      activeHoursLabel: json['active_hours_label']?.toString() ?? '0.0h',
      requiredHoursLabel: json['required_hours_label']?.toString() ?? '0.0h',
      rewardAmountLabel: json['reward_amount_label']?.toString() ?? '--',
      rewardStatusLabel: json['reward_status_label']?.toString() ?? '',
      joinedStaffName: json['joined_staff_name']?.toString() ?? '',
      createdAtLabel: json['created_at']?.toString() ?? '--',
    );
  }
}

class ReferralRewardHistoryItem {
  const ReferralRewardHistoryItem({
    required this.id,
    required this.referredStaffName,
    required this.referredStaffPhone,
    required this.requiredHoursLabel,
    required this.rewardAmountLabel,
    required this.qualifiedAtLabel,
    required this.isPaid,
    required this.paidAtLabel,
    required this.paymentMethodLabel,
    required this.paymentReference,
    required this.paymentNote,
  });

  final String id;
  final String referredStaffName;
  final String referredStaffPhone;
  final String requiredHoursLabel;
  final String rewardAmountLabel;
  final String qualifiedAtLabel;
  final bool isPaid;
  final String paidAtLabel;
  final String paymentMethodLabel;
  final String paymentReference;
  final String paymentNote;

  factory ReferralRewardHistoryItem.fromJson(Map<String, dynamic> json) {
    return ReferralRewardHistoryItem(
      id: json['id']?.toString() ?? '',
      referredStaffName: json['referred_staff_name']?.toString() ?? '',
      referredStaffPhone: json['referred_staff_phone']?.toString() ?? '',
      requiredHoursLabel:
          json['required_hours_label']?.toString() ?? '0.0h',
      rewardAmountLabel:
          json['reward_amount_label']?.toString() ?? 'Rs. 0.00',
      qualifiedAtLabel: json['qualified_at_label']?.toString() ?? '--',
      isPaid: json['is_paid'] == true,
      paidAtLabel: json['paid_at_label']?.toString() ?? '--',
      paymentMethodLabel:
          json['payment_method_label']?.toString() ?? 'Manual',
      paymentReference: json['payment_reference']?.toString() ?? '--',
      paymentNote: json['payment_note']?.toString() ?? '--',
    );
  }
}

class StaffSalaryDetails {
  const StaffSalaryDetails({
    required this.summary,
    required this.currentCycle,
    required this.previousMonth,
    required this.pattern,
    required this.paymentHistory,
    required this.referralSummary,
    required this.referralTracking,
    required this.referralHistory,
  });

  final SalaryDetailSummary summary;
  final SalaryDetailBlock currentCycle;
  final SalaryDetailBlock previousMonth;
  final SalaryPatternSection pattern;
  final List<SalaryPaymentHistoryItem> paymentHistory;
  final ReferralSummary referralSummary;
  final List<ReferralTrackingItem> referralTracking;
  final List<ReferralRewardHistoryItem> referralHistory;

  factory StaffSalaryDetails.fromJson(Map<String, dynamic> json) {
    return StaffSalaryDetails(
      summary: SalaryDetailSummary.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : const {},
      ),
      currentCycle: SalaryDetailBlock.fromJson(
        json['current_cycle'] is Map<String, dynamic>
            ? json['current_cycle'] as Map<String, dynamic>
            : const {},
      ),
      previousMonth: SalaryDetailBlock.fromJson(
        json['previous_month'] is Map<String, dynamic>
            ? json['previous_month'] as Map<String, dynamic>
            : const {},
      ),
      pattern: SalaryPatternSection.fromJson(
        json['pattern'] is Map<String, dynamic>
            ? json['pattern'] as Map<String, dynamic>
            : const {},
      ),
      paymentHistory:
          (json['payment_history'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SalaryPaymentHistoryItem.fromJson)
              .toList() ??
          const [],
      referralSummary: ReferralSummary.fromJson(
        json['referral'] is Map<String, dynamic>
            ? json['referral'] as Map<String, dynamic>
            : const {},
      ),
      referralTracking:
          ((json['referral'] is Map<String, dynamic>
                      ? (json['referral'] as Map<String, dynamic>)['tracking_rows']
                      : null)
                  as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ReferralTrackingItem.fromJson)
              .toList() ??
          const [],
      referralHistory:
          ((json['referral'] is Map<String, dynamic>
                      ? (json['referral'] as Map<String, dynamic>)['history']
                      : null)
                  as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ReferralRewardHistoryItem.fromJson)
              .toList() ??
          const [],
    );
  }
}

class LeadItem {
  const LeadItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.statusLabel,
    required this.callbackWindow,
    required this.callbackWindowLabel,
    required this.callbackDate,
    required this.callbackDateLabel,
    required this.callbackScheduleLabel,
    required this.notes,
    this.assignedToName = '',
    this.lastContactedAt,
    this.updatedAt,
    this.isDueNow = false,
    this.followupAttemptCount = 0,
    this.followupAttemptsRemaining = 3,
    this.canMarkFollowupNoResponse = false,
    this.isScheduledFollowup = false,
    this.followupWarningDue = false,
    this.followupWarningDays = 0,
    this.followupStaleDays = 0,
    this.followupWarningLabel = '',
    this.daysToAutoExpiry,
    this.followupWorkSeconds = 0,
    this.followupWorkLabel = '',
    this.followupCallCount = 0,
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final String statusLabel;
  final String callbackWindow;
  final String callbackWindowLabel;
  final DateTime? callbackDate;
  final String callbackDateLabel;
  final String callbackScheduleLabel;
  final String notes;
  final String assignedToName;
  final DateTime? lastContactedAt;
  final DateTime? updatedAt;
  final bool isDueNow;
  final int followupAttemptCount;
  final int followupAttemptsRemaining;
  final bool canMarkFollowupNoResponse;
  final bool isScheduledFollowup;
  final bool followupWarningDue;
  final int followupWarningDays;
  final int followupStaleDays;
  final String followupWarningLabel;
  final int? daysToAutoExpiry;
  final int followupWorkSeconds;
  final String followupWorkLabel;
  final int followupCallCount;

  bool get isRecoveryLead =>
      status == 'no_answer' || status == 'not_interested';
  bool get isPriorityCallback => status == 'call_back';

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    final callbackDateLabel = json['callback_date_label']?.toString() ?? '';
    final callbackWindowLabel = json['callback_window_label']?.toString() ?? '';
    final rawStatus = json['status']?.toString() ?? '';
    final displayStatus = rawStatus == 'call_back'
        ? 'Follow Up'
        : (rawStatus == 'interested' ? 'Interested' : '');
    final statusLabel =
        json['status_label']?.toString().trim().isNotEmpty == true
            ? json['status_label']?.toString() ?? 'New'
            : (displayStatus.isNotEmpty ? displayStatus : 'New');
    final normalizedStatusLabel =
        displayStatus.isNotEmpty ? displayStatus : statusLabel;
    return LeadItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusLabel: normalizedStatusLabel,
      callbackWindow: json['callback_window']?.toString() ?? '',
      callbackWindowLabel: callbackWindowLabel,
      callbackDate: json['callback_date'] == null
          ? null
          : DateTime.tryParse(json['callback_date'].toString()),
      callbackDateLabel: callbackDateLabel,
      callbackScheduleLabel:
          json['callback_schedule_label']?.toString() ??
          _joinCallbackScheduleLabel(callbackDateLabel, callbackWindowLabel),
      notes: json['notes']?.toString() ?? '',
      assignedToName: json['assigned_to_name']?.toString() ?? '',
      lastContactedAt: json['last_contacted_at'] == null
          ? null
          : DateTime.tryParse(json['last_contacted_at'].toString())?.toLocal(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString())?.toLocal(),
      isDueNow: json['is_due_now'] == true,
      followupAttemptCount: _asInt(json['followup_attempt_count']),
      followupAttemptsRemaining: _asInt(
        json['followup_attempts_remaining'],
      ),
      canMarkFollowupNoResponse: json['can_mark_followup_no_response'] == true,
      isScheduledFollowup: json['is_scheduled_followup'] == true,
      followupWarningDue: json['followup_warning_due'] == true,
      followupWarningDays: _asInt(json['followup_warning_days']),
      followupStaleDays: _asInt(json['followup_stale_days']),
      followupWarningLabel: json['followup_warning_label']?.toString() ?? '',
      daysToAutoExpiry: json['days_to_auto_expiry'] == null
          ? null
          : _asInt(json['days_to_auto_expiry']),
      followupWorkSeconds: _asInt(json['followup_work_seconds']),
      followupWorkLabel: json['followup_work_label']?.toString() ?? '',
      followupCallCount: _asInt(json['followup_call_count']),
    );
  }
}

class FollowupWarningSummary {
  const FollowupWarningSummary({
    this.warningDays = 0,
    this.warningCount = 0,
    this.oldestWarningDays = 0,
    this.popupRequired = false,
    this.title = '',
    this.message = '',
  });

  final int warningDays;
  final int warningCount;
  final int oldestWarningDays;
  final bool popupRequired;
  final String title;
  final String message;

  factory FollowupWarningSummary.fromJson(Map<String, dynamic> json) {
    return FollowupWarningSummary(
      warningDays: _asInt(json['warning_days']),
      warningCount: _asInt(json['warning_count']),
      oldestWarningDays: _asInt(json['oldest_warning_days']),
      popupRequired: json['popup_required'] == true,
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class FollowupInboxPayload {
  const FollowupInboxPayload({
    required this.followups,
    required this.warningSummary,
  });

  final List<LeadItem> followups;
  final FollowupWarningSummary warningSummary;

  factory FollowupInboxPayload.fromJson(Map<String, dynamic> json) {
    final rows = json['followups'];
    final warning = json['warning_summary'];
    return FollowupInboxPayload(
      followups:
          (rows as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(LeadItem.fromJson)
              .toList() ??
          const [],
      warningSummary: FollowupWarningSummary.fromJson(
        warning is Map<String, dynamic> ? warning : const {},
      ),
    );
  }
}

class InterestedLeadDetail {
  const InterestedLeadDetail({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.productEnquired,
    required this.enquiryNotes,
    required this.preferredCallTime,
    required this.updatedAtLabel,
  });

  final String id;
  final String customerName;
  final String customerPhone;
  final String productEnquired;
  final String enquiryNotes;
  final String preferredCallTime;
  final String updatedAtLabel;

  factory InterestedLeadDetail.fromJson(Map<String, dynamic> json) {
    return InterestedLeadDetail(
      id: json['id']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      productEnquired: json['product_enquired']?.toString() ?? '',
      enquiryNotes: json['enquiry_notes']?.toString() ?? '',
      preferredCallTime: json['preferred_call_time']?.toString() ?? '',
      updatedAtLabel: json['updated_at_label']?.toString() ?? '--',
    );
  }
}

class DailySummary {
  const DailySummary({
    required this.activeLabel,
    required this.activeSeconds,
    required this.callsCount,
    required this.resultLabel,
    required this.workingNow,
    required this.currentState,
    required this.statusLabel,
    required this.closeReason,
    required this.pendingTrainingCount,
    required this.trainingRequired,
    required this.nextTrainingTitle,
    required this.pendingCallStatusRequired,
    required this.pendingCallId,
    required this.pendingCallLeadId,
    required this.pendingCallLeadName,
    required this.pendingCallLeadPhone,
    required this.recoverableCallRequired,
    required this.recoverableCallId,
    required this.recoverableCallLeadId,
    required this.recoverableCallLeadName,
    required this.recoverableCallLeadPhone,
    required this.recoverableCallStartedAt,
    required this.followupSlaCrossedCount,
    required this.followupSlaWarningDays,
    required this.followupSlaGateEnabled,
    required this.followupSlaGateMode,
    required this.followupSlaFollowupCallsToday,
    required this.normalLeadCallsBlockedBySla,
    required this.followupSlaBlockMessage,
  });

  final String activeLabel;
  final int activeSeconds;
  final int callsCount;
  final String resultLabel;
  final bool workingNow;
  final String currentState;
  final String statusLabel;
  final String closeReason;
  final int pendingTrainingCount;
  final bool trainingRequired;
  final String nextTrainingTitle;
  final bool pendingCallStatusRequired;
  final String pendingCallId;
  final String pendingCallLeadId;
  final String pendingCallLeadName;
  final String pendingCallLeadPhone;
  final bool recoverableCallRequired;
  final String recoverableCallId;
  final String recoverableCallLeadId;
  final String recoverableCallLeadName;
  final String recoverableCallLeadPhone;
  final DateTime? recoverableCallStartedAt;
  final int followupSlaCrossedCount;
  final int followupSlaWarningDays;
  final bool followupSlaGateEnabled;
  final String followupSlaGateMode;
  final int followupSlaFollowupCallsToday;
  final bool normalLeadCallsBlockedBySla;
  final String followupSlaBlockMessage;

  factory DailySummary.empty() {
    return const DailySummary(
      activeLabel: '0h',
      activeSeconds: 0,
      callsCount: 0,
      resultLabel: '0 interested / 0 converted',
      workingNow: false,
      currentState: 'stopped',
      statusLabel: 'Stopped',
      closeReason: '',
      pendingTrainingCount: 0,
      trainingRequired: false,
      nextTrainingTitle: '',
      pendingCallStatusRequired: false,
      pendingCallId: '',
      pendingCallLeadId: '',
      pendingCallLeadName: '',
      pendingCallLeadPhone: '',
      recoverableCallRequired: false,
      recoverableCallId: '',
      recoverableCallLeadId: '',
      recoverableCallLeadName: '',
      recoverableCallLeadPhone: '',
      recoverableCallStartedAt: null,
      followupSlaCrossedCount: 0,
      followupSlaWarningDays: 0,
      followupSlaGateEnabled: false,
      followupSlaGateMode: '',
      followupSlaFollowupCallsToday: 0,
      normalLeadCallsBlockedBySla: false,
      followupSlaBlockMessage: '',
    );
  }

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      activeLabel: json['active_label']?.toString() ?? '0h',
      activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
      callsCount: (json['calls_count'] as num?)?.toInt() ?? 0,
      resultLabel:
          json['result_label']?.toString() ?? '0 interested / 0 converted',
      workingNow: json['working_now'] == true,
      currentState: json['current_state']?.toString() ?? 'stopped',
      statusLabel: json['status_label']?.toString() ?? 'Stopped',
      closeReason: json['close_reason']?.toString() ?? '',
      pendingTrainingCount:
          (json['pending_training_count'] as num?)?.toInt() ?? 0,
      trainingRequired: json['training_required'] == true,
      nextTrainingTitle: json['next_training_title']?.toString() ?? '',
      pendingCallStatusRequired: json['pending_call_status_required'] == true,
      pendingCallId: json['pending_call_id']?.toString() ?? '',
      pendingCallLeadId: json['pending_call_lead_id']?.toString() ?? '',
      pendingCallLeadName: json['pending_call_lead_name']?.toString() ?? '',
      pendingCallLeadPhone: json['pending_call_lead_phone']?.toString() ?? '',
      recoverableCallRequired: json['recoverable_call_required'] == true,
      recoverableCallId: json['recoverable_call_id']?.toString() ?? '',
      recoverableCallLeadId:
          json['recoverable_call_lead_id']?.toString() ?? '',
      recoverableCallLeadName:
          json['recoverable_call_lead_name']?.toString() ?? '',
      recoverableCallLeadPhone:
          json['recoverable_call_lead_phone']?.toString() ?? '',
      recoverableCallStartedAt: json['recoverable_call_started_at'] == null
          ? null
          : DateTime.tryParse(
              json['recoverable_call_started_at'].toString(),
            )?.toLocal(),
      followupSlaCrossedCount:
          (json['followup_sla_crossed_count'] as num?)?.toInt() ?? 0,
      followupSlaWarningDays:
          (json['followup_sla_warning_days'] as num?)?.toInt() ?? 0,
      followupSlaGateEnabled: json['followup_sla_gate_enabled'] == true,
      followupSlaGateMode: json['followup_sla_gate_mode']?.toString() ?? '',
      followupSlaFollowupCallsToday:
          (json['followup_sla_followup_calls_today'] as num?)?.toInt() ?? 0,
      normalLeadCallsBlockedBySla:
          json['normal_lead_calls_blocked_by_sla'] == true,
      followupSlaBlockMessage: json['followup_sla_block_message']?.toString() ?? '',
    );
  }
}

class SessionResponse {
  const SessionResponse({required this.summary, required this.notifications});

  final DailySummary summary;
  final List<AppNotificationItem> notifications;

  factory SessionResponse.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final rows = json['notifications'];
    return SessionResponse(
      summary: DailySummary.fromJson(
        summary is Map<String, dynamic> ? summary : const {},
      ),
      notifications:
          (rows as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(AppNotificationItem.fromJson)
              .toList() ??
          const [],
    );
  }
}

class StaffTodayPayload {
  const StaffTodayPayload({required this.summary, required this.notifications});

  final DailySummary summary;
  final List<AppNotificationItem> notifications;

  factory StaffTodayPayload.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final rows = json['notifications'];
    return StaffTodayPayload(
      summary: DailySummary.fromJson(
        summary is Map<String, dynamic> ? summary : const {},
      ),
      notifications:
          (rows as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(AppNotificationItem.fromJson)
              .toList() ??
          const [],
    );
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.severityLabel,
    required this.source,
    required this.sourceLabel,
    required this.autoDismissSeconds,
    required this.allowManualClose,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String severity;
  final String severityLabel;
  final String source;
  final String sourceLabel;
  final int autoDismissSeconds;
  final bool allowManualClose;
  final DateTime? createdAt;

  factory AppNotificationItem.fromJson(Map<String, dynamic> json) {
    return AppNotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'normal',
      severityLabel: json['severity_label']?.toString() ?? 'Normal',
      source: json['source']?.toString() ?? 'manual',
      sourceLabel: json['source_label']?.toString() ?? 'Manual',
      autoDismissSeconds: _asInt(json['auto_dismiss_seconds']),
      allowManualClose: json['allow_manual_close'] != false,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString())?.toLocal(),
    );
  }
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.status,
    required this.callbackWindow,
    required this.callbackDate,
    required this.callbackDateLabel,
    required this.callbackScheduleLabel,
    required this.durationSeconds,
    required this.isVerified,
  });

  final String id;
  final String status;
  final String callbackWindow;
  final DateTime? callbackDate;
  final String callbackDateLabel;
  final String callbackScheduleLabel;
  final int durationSeconds;
  final bool isVerified;

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    final callbackDateLabel = json['callback_date_label']?.toString() ?? '';
    final callbackWindowLabel = json['callback_window_label']?.toString() ?? '';
    return CallRecord(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      callbackWindow: json['callback_window']?.toString() ?? '',
      callbackDate: json['callback_date'] == null
          ? null
          : DateTime.tryParse(json['callback_date'].toString()),
      callbackDateLabel: callbackDateLabel,
      callbackScheduleLabel:
          json['callback_schedule_label']?.toString() ??
          _joinCallbackScheduleLabel(callbackDateLabel, callbackWindowLabel),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      isVerified: json['is_verified'] == true,
    );
  }
}

class LearningSummary {
  const LearningSummary({
    required this.totalLessons,
    required this.completedCount,
    required this.pendingMandatoryCount,
    required this.hasPendingMandatory,
    required this.nextRequiredTitle,
  });

  final int totalLessons;
  final int completedCount;
  final int pendingMandatoryCount;
  final bool hasPendingMandatory;
  final String nextRequiredTitle;

  factory LearningSummary.empty() {
    return const LearningSummary(
      totalLessons: 0,
      completedCount: 0,
      pendingMandatoryCount: 0,
      hasPendingMandatory: false,
      nextRequiredTitle: '',
    );
  }

  factory LearningSummary.fromJson(Map<String, dynamic> json) {
    return LearningSummary(
      totalLessons: (json['total_lessons'] as num?)?.toInt() ?? 0,
      completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
      pendingMandatoryCount:
          (json['pending_mandatory_count'] as num?)?.toInt() ?? 0,
      hasPendingMandatory: json['has_pending_mandatory'] == true,
      nextRequiredTitle: json['next_required_title']?.toString() ?? '',
    );
  }
}

class TrainingLesson {
  const TrainingLesson({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.searchKeywords,
    required this.isMandatory,
    required this.isCompleted,
    required this.completedAt,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final String videoUrl;
  final String searchKeywords;
  final bool isMandatory;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime? publishedAt;

  bool get hasVideo => videoUrl.trim().isNotEmpty;
  bool get isYouTubeVideo => youtubeVideoId.isNotEmpty;

  String get youtubeVideoId {
    final raw = videoUrl.trim();
    if (raw.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return '';
    }

    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    }

    if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      final queryId = uri.queryParameters['v'];
      if (queryId != null && queryId.isNotEmpty) {
        return queryId;
      }
      if (uri.pathSegments.length >= 2 &&
          const ['embed', 'shorts', 'live'].contains(uri.pathSegments.first)) {
        return uri.pathSegments[1];
      }
    }

    return '';
  }

  String get searchableText =>
      '$title $description $searchKeywords'.toLowerCase();

  factory TrainingLesson.fromJson(Map<String, dynamic> json) {
    return TrainingLesson(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      searchKeywords: json['search_keywords']?.toString() ?? '',
      isMandatory: json['is_mandatory'] == true,
      isCompleted: json['is_completed'] == true,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'].toString())?.toLocal(),
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'].toString())?.toLocal(),
    );
  }
}

class LearningCenterPayload {
  const LearningCenterPayload({required this.summary, required this.lessons});

  final LearningSummary summary;
  final List<TrainingLesson> lessons;

  factory LearningCenterPayload.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final lessons = json['lessons'];
    return LearningCenterPayload(
      summary: LearningSummary.fromJson(
        summary is Map<String, dynamic> ? summary : const {},
      ),
      lessons: lessons is List
          ? lessons
                .whereType<Map<String, dynamic>>()
                .map(TrainingLesson.fromJson)
                .toList()
          : const [],
    );
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;
}
