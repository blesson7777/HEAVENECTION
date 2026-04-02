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
      finalSalaryLabel: json['final_salary_label']?.toString() ?? 'Rs. 0.00',
      paidAmount: _asDouble(json['paid_amount']),
      paidAmountLabel: json['paid_amount_label']?.toString() ?? '',
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.tryParse(json['paid_at'].toString())?.toLocal(),
      paidAtLabel: json['paid_at_label']?.toString() ?? '',
      paymentMethodLabel: json['payment_method_label']?.toString() ?? '',
      paymentReference: json['payment_reference']?.toString() ?? '',
      paymentNote: json['payment_note']?.toString() ?? '',
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
    required this.notes,
    this.assignedToName = '',
    this.lastContactedAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final String statusLabel;
  final String callbackWindow;
  final String callbackWindowLabel;
  final String notes;
  final String assignedToName;
  final DateTime? lastContactedAt;
  final DateTime? updatedAt;

  bool get isRecoveryLead =>
      status == 'no_answer' || status == 'not_interested';

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    return LeadItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusLabel: json['status_label']?.toString() ?? 'New',
      callbackWindow: json['callback_window']?.toString() ?? '',
      callbackWindowLabel: json['callback_window_label']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      assignedToName: json['assigned_to_name']?.toString() ?? '',
      lastContactedAt: json['last_contacted_at'] == null
          ? null
          : DateTime.tryParse(json['last_contacted_at'].toString())?.toLocal(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString())?.toLocal(),
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
    );
  }
}

class SessionResponse {
  const SessionResponse({required this.summary});

  final DailySummary summary;

  factory SessionResponse.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return SessionResponse(
      summary: DailySummary.fromJson(
        summary is Map<String, dynamic> ? summary : const {},
      ),
    );
  }
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.status,
    required this.callbackWindow,
    required this.durationSeconds,
    required this.isVerified,
  });

  final String id;
  final String status;
  final String callbackWindow;
  final int durationSeconds;
  final bool isVerified;

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    return CallRecord(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      callbackWindow: json['callback_window']?.toString() ?? '',
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
