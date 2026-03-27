import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_models.dart';

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  SharedPreferences? _preferences;
  String? _accessToken;
  String? _refreshToken;

  static const _accessKey = 'heavenection_access_token';
  static const _refreshKey = 'heavenection_refresh_token';

  Future<void> loadStoredSession() async {
    _preferences ??= await SharedPreferences.getInstance();
    _accessToken = _preferences!.getString(_accessKey);
    _refreshToken = _preferences!.getString(_refreshKey);
  }

  Future<StaffUser?> restoreSession() async {
    await loadStoredSession();
    if (_accessToken == null || _refreshToken == null) {
      return null;
    }
    try {
      return await fetchMe();
    } on ApiException catch (error) {
      if (error.code == 'network_error') {
        rethrow;
      }
      await clearSession();
      return null;
    }
  }

  Future<StaffUser> login({
    required String phone,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/auth/login/',
      body: {'phone': phone, 'password': password},
      requiresAuth: false,
    );
    final payload = _decodeMap(response.body);
    _accessToken = payload['access']?.toString();
    _refreshToken = payload['refresh']?.toString();
    await _persistTokens();
    final user = payload['user'];
    return StaffUser.fromJson(user is Map<String, dynamic> ? user : const {});
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/api/auth/logout/');
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    _preferences ??= await SharedPreferences.getInstance();
    _accessToken = null;
    _refreshToken = null;
    await _preferences!.remove(_accessKey);
    await _preferences!.remove(_refreshKey);
  }

  Future<StaffUser> fetchMe() async {
    final response = await _send('GET', '/api/auth/me/');
    return StaffUser.fromJson(_decodeMap(response.body));
  }

  Future<DailySummary> fetchTodaySummary() async {
    final response = await _send('GET', '/api/staff/today-summary/');
    final payload = _decodeMap(response.body);
    final summary = payload['summary'];
    return DailySummary.fromJson(
      summary is Map<String, dynamic> ? summary : const {},
    );
  }

  Future<List<LeadItem>> fetchAssignedLeads() async {
    final response = await _send('GET', '/api/staff/leads/');
    final payload = jsonDecode(response.body);
    if (payload is! List) {
      return const [];
    }
    return payload
        .whereType<Map<String, dynamic>>()
        .map(LeadItem.fromJson)
        .toList();
  }

  Future<LearningCenterPayload> fetchLearningCenter() async {
    final response = await _send('GET', '/api/staff/learning/');
    return LearningCenterPayload.fromJson(_decodeMap(response.body));
  }

  Future<LearningCenterPayload> completeTrainingLesson({
    required String lessonId,
  }) async {
    final response = await _send(
      'POST',
      '/api/staff/learning/$lessonId/complete/',
    );
    return LearningCenterPayload.fromJson(_decodeMap(response.body));
  }

  Future<SessionResponse> startSession() async {
    final response = await _send('POST', '/api/staff/session/start/');
    return SessionResponse.fromJson(_decodeMap(response.body));
  }

  Future<SessionResponse> endSession() async {
    final response = await _send('POST', '/api/staff/session/end/');
    return SessionResponse.fromJson(_decodeMap(response.body));
  }

  Future<SessionResponse> sendHeartbeat({
    required String state,
    bool interaction = false,
    String source = 'timer',
  }) async {
    final response = await _send(
      'POST',
      '/api/staff/heartbeat/',
      body: {'state': state, 'interaction': interaction, 'source': source},
    );
    return SessionResponse.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> startCall({required String leadId}) async {
    final response = await _send(
      'POST',
      '/api/staff/calls/start/',
      body: {'lead_id': leadId},
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> endCall({
    required String callId,
    String? status,
    String? callbackWindow,
    int? durationSeconds,
    DateTime? endedAt,
    String source = 'app',
  }) async {
    final body = <String, dynamic>{'source': source};
    if (status != null && status.isNotEmpty) {
      body['status'] = status;
    }
    if (callbackWindow != null && callbackWindow.isNotEmpty) {
      body['callback_window'] = callbackWindow;
    }
    if (durationSeconds != null) {
      body['duration_seconds'] = durationSeconds;
    }
    if (endedAt != null) {
      body['ended_at'] = endedAt.toUtc().toIso8601String();
    }

    final response = await _send(
      'POST',
      '/api/staff/calls/$callId/end/',
      body: body,
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> retryPendingCall({required String callId}) async {
    final response = await _send(
      'POST',
      '/api/staff/calls/$callId/retry/',
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> updateCallStatus({
    required String callId,
    required String status,
    String? callbackWindow,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (callbackWindow != null && callbackWindow.isNotEmpty) {
      body['callback_window'] = callbackWindow;
    }
    final response = await _send(
      'POST',
      '/api/staff/calls/$callId/status/',
      body: body,
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<void> _persistTokens() async {
    _preferences ??= await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await _preferences!.setString(_accessKey, _accessToken!);
    }
    if (_refreshToken != null) {
      await _preferences!.setString(_refreshKey, _refreshToken!);
    }
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) {
      throw const ApiException('Session expired.', statusCode: 401);
    }
    final response = await _send(
      'POST',
      '/api/auth/refresh/',
      body: {'refresh': _refreshToken},
      requiresAuth: false,
      retryOnAuthFailure: false,
    );
    final payload = _decodeMap(response.body);
    _accessToken = payload['access']?.toString();
    await _persistTokens();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool retryOnAuthFailure = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (requiresAuth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          );
          break;
        default:
          throw UnsupportedError('Unsupported method: $method');
      }
    } on SocketException {
      throw const ApiException(
        'Network connection lost.',
        statusCode: 0,
        code: 'network_error',
      );
    } on http.ClientException {
      throw const ApiException(
        'Network connection lost.',
        statusCode: 0,
        code: 'network_error',
      );
    }

    if (response.statusCode == 401 && requiresAuth && retryOnAuthFailure) {
      await _refreshAccessToken();
      return _send(
        method,
        path,
        body: body,
        requiresAuth: requiresAuth,
        retryOnAuthFailure: false,
      );
    }

    if (response.statusCode >= 400) {
      final payload = _tryDecodeMap(response.body);
      final detail = payload?['detail']?.toString();
      final code = payload?['code']?.toString();
      final message = detail == null || detail.isEmpty
          ? 'Request failed.'
          : detail;
      throw ApiException(message, statusCode: response.statusCode, code: code);
    }

    return response;
  }

  Map<String, dynamic> _decodeMap(String body) {
    final payload = jsonDecode(body);
    return payload is Map<String, dynamic> ? payload : const {};
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    try {
      final payload = jsonDecode(body);
      return payload is Map<String, dynamic> ? payload : null;
    } catch (_) {
      return null;
    }
  }
}
