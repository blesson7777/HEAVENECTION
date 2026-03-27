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
    required this.notes,
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final String statusLabel;
  final String notes;

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    return LeadItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusLabel: json['status_label']?.toString() ?? 'New',
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
  });

  final String activeLabel;
  final int activeSeconds;
  final int callsCount;
  final String resultLabel;
  final bool workingNow;
  final String currentState;
  final String statusLabel;
  final String closeReason;

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
    required this.durationSeconds,
  });

  final String id;
  final String status;
  final int durationSeconds;

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    return CallRecord(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}
