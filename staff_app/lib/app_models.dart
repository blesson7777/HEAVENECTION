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
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final String statusLabel;
  final String callbackWindow;
  final String callbackWindowLabel;
  final String notes;

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
  });

  final String id;
  final String status;
  final String callbackWindow;
  final int durationSeconds;

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    return CallRecord(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      callbackWindow: json['callback_window']?.toString() ?? '',
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
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
