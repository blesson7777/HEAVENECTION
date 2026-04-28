import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_models.dart';

String _dateOnlyString(DateTime value) {
  final normalized = DateTime(value.year, value.month, value.day);
  return normalized.toIso8601String().split('T').first;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    List<String> fallbackBaseUrls = const [],
    http.Client? client,
  }) : fallbackBaseUrls =
           fallbackBaseUrls
               .map((item) => item.trim())
               .where((item) => item.isNotEmpty)
               .toList(growable: false),
       _client = client ?? http.Client();

  final String baseUrl;
  final List<String> fallbackBaseUrls;
  final http.Client _client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SharedPreferences? _preferences;
  String? _accessToken;
  String? _refreshToken;

  static const _accessKey = 'heavenection_access_token';
  static const _refreshKey = 'heavenection_refresh_token';

  Future<void> loadStoredSession() async {
    _preferences ??= await SharedPreferences.getInstance();
    _accessToken = await _secureStorage.read(key: _accessKey);
    _refreshToken = await _secureStorage.read(key: _refreshKey);
    if (_accessToken == null || _refreshToken == null) {
      await _migrateLegacyStoredSession();
    }
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
    required String identifier,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/auth/login/',
      body: {'identifier': identifier, 'password': password},
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
    await _secureStorage.delete(key: _accessKey);
    await _secureStorage.delete(key: _refreshKey);
    await _preferences!.remove(_accessKey);
    await _preferences!.remove(_refreshKey);
  }

  Future<StaffUser> fetchMe() async {
    final response = await _send('GET', '/api/auth/me/');
    return StaffUser.fromJson(_decodeMap(response.body));
  }

  Future<StaffProfile> fetchStaffProfile() async {
    final response = await _send('GET', '/api/staff/profile/');
    return StaffProfile.fromJson(_decodeMap(response.body));
  }

  Future<StaffSalaryDetails> fetchStaffSalaryDetails() async {
    final response = await _send('GET', '/api/staff/salary/');
    return StaffSalaryDetails.fromJson(_decodeMap(response.body));
  }

  Future<void> submitReferral({
    required String referredName,
    required String referredPhone,
  }) async {
    await _send(
      'POST',
      '/api/staff/referrals/',
      body: {'referred_name': referredName, 'referred_phone': referredPhone},
    );
  }

  Map<String, String> get authenticatedDocumentHeaders {
    if (_accessToken == null || _accessToken!.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $_accessToken'};
  }

  Future<AppUpdateInfo?> fetchAppUpdate({required int versionCode}) async {
    final response = await _send(
      'GET',
      '/api/staff/app-update/?version_code=$versionCode',
    );
    final payload = _decodeMap(response.body);
    if (payload['update_available'] != true) {
      return null;
    }
    return AppUpdateInfo.fromJson(payload);
  }

  Future<StaffProfile> updateStaffProfile({
    required String name,
    required String phone,
    required String email,
    required String bankAccountName,
    required String bankName,
    required String bankAccountNumber,
    required String bankIfscCode,
    required String aadharNumber,
    File? passbookPhoto,
    String? currentPassword,
    String? newPassword,
    File? aadharPhoto,
    bool removeAadharPhoto = false,
    bool removePassbookPhoto = false,
  }) async {
    final response = await _sendMultipart(
      'PATCH',
      '/api/staff/profile/',
      fields: {
        'name': name,
        'phone': phone,
        'email': email,
        'bank_account_name': bankAccountName,
        'bank_name': bankName,
        'bank_account_number': bankAccountNumber,
        'bank_ifsc_code': bankIfscCode,
        'aadhar_number': aadharNumber,
        'remove_aadhar_photo': removeAadharPhoto ? 'true' : 'false',
        'remove_passbook_photo': removePassbookPhoto ? 'true' : 'false',
        if (currentPassword != null && currentPassword.isNotEmpty)
          'current_password': currentPassword,
        if (newPassword != null && newPassword.isNotEmpty)
          'new_password': newPassword,
      },
      filePaths: {
        if (aadharPhoto != null) 'aadhar_photo': aadharPhoto.path,
        if (passbookPhoto != null) 'passbook_photo': passbookPhoto.path,
      },
    );
    return StaffProfile.fromJson(_decodeMap(response.body));
  }

  Future<StaffProfile> removeStaffDocument({
    bool removeAadharPhoto = false,
    bool removePassbookPhoto = false,
  }) async {
    final response = await _send(
      'PATCH',
      '/api/staff/profile/',
      body: {
        'remove_aadhar_photo': removeAadharPhoto,
        'remove_passbook_photo': removePassbookPhoto,
      },
    );
    return StaffProfile.fromJson(_decodeMap(response.body));
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

  Future<List<LeadItem>> fetchFollowups() async {
    final response = await _send('GET', '/api/staff/followups/');
    final payload = _decodeMap(response.body);
    final rows = payload['followups'];
    if (rows is! List) {
      return const [];
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(LeadItem.fromJson)
        .toList();
  }

  Future<List<LeadItem>> searchCustomerHistory({String query = ''}) async {
    final encodedQuery = Uri.encodeQueryComponent(query.trim());
    final path = query.trim().isEmpty
        ? '/api/staff/customers/'
        : '/api/staff/customers/?q=$encodedQuery';
    final response = await _send('GET', path);
    final payload = jsonDecode(response.body);
    if (payload is! List) {
      return const [];
    }
    return payload
        .whereType<Map<String, dynamic>>()
        .map(LeadItem.fromJson)
        .toList();
  }

  Future<LeadItem> recoverCustomerLead({
    required String leadId,
    required String status,
    String? callbackWindow,
    DateTime? callbackDate,
    String? customerName,
    String? customerPhone,
    String? productEnquired,
    String? enquiryNotes,
    String? preferredCallTime,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (callbackWindow != null && callbackWindow.isNotEmpty) {
      body['callback_window'] = callbackWindow;
    }
    if (callbackDate != null) {
      body['callback_date'] = _dateOnlyString(callbackDate);
    }
    if (customerName != null && customerName.trim().isNotEmpty) {
      body['customer_name'] = customerName.trim();
    }
    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      body['customer_phone'] = customerPhone.trim();
    }
    if (productEnquired != null && productEnquired.trim().isNotEmpty) {
      body['product_enquired'] = productEnquired.trim();
    }
    if (enquiryNotes != null && enquiryNotes.trim().isNotEmpty) {
      body['enquiry_notes'] = enquiryNotes.trim();
    }
    if (preferredCallTime != null && preferredCallTime.trim().isNotEmpty) {
      body['preferred_call_time'] = preferredCallTime.trim();
    }
    final response = await _send(
      'POST',
      '/api/staff/customers/$leadId/recover/',
      body: body,
    );
    return LeadItem.fromJson(_decodeMap(response.body));
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

  Future<CallRecord> startCall({
    required String leadId,
    bool fromFollowupMenu = false,
  }) async {
    final response = await _send(
      'POST',
      '/api/staff/calls/start/',
      body: {'lead_id': leadId, 'from_followup_menu': fromFollowupMenu},
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> endCall({
    required String callId,
    String? status,
    String? callbackWindow,
    DateTime? callbackDate,
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
    if (callbackDate != null) {
      body['callback_date'] = _dateOnlyString(callbackDate);
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
    final response = await _send('POST', '/api/staff/calls/$callId/retry/');
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<CallRecord> updateCallStatus({
    required String callId,
    required String status,
    String? callbackWindow,
    DateTime? callbackDate,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (callbackWindow != null && callbackWindow.isNotEmpty) {
      body['callback_window'] = callbackWindow;
    }
    if (callbackDate != null) {
      body['callback_date'] = _dateOnlyString(callbackDate);
    }
    final response = await _send(
      'POST',
      '/api/staff/calls/$callId/status/',
      body: body,
    );
    return CallRecord.fromJson(_decodeMap(response.body));
  }

  Future<InterestedLeadDetail> submitInterestedLeadDetail({
    required String callId,
    required String customerName,
    required String customerPhone,
    required String productEnquired,
    required String enquiryNotes,
    required String preferredCallTime,
  }) async {
    final response = await _send(
      'POST',
      '/api/staff/calls/$callId/interested-detail/',
      body: {
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'product_enquired': productEnquired,
        'enquiry_notes': enquiryNotes,
        'preferred_call_time': preferredCallTime,
      },
    );
    return InterestedLeadDetail.fromJson(_decodeMap(response.body));
  }

  Future<void> _persistTokens() async {
    _preferences ??= await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await _secureStorage.write(key: _accessKey, value: _accessToken!);
      await _preferences!.remove(_accessKey);
    }
    if (_refreshToken != null) {
      await _secureStorage.write(key: _refreshKey, value: _refreshToken!);
      await _preferences!.remove(_refreshKey);
    }
  }

  Future<void> _migrateLegacyStoredSession() async {
    _preferences ??= await SharedPreferences.getInstance();
    final legacyAccessToken = _preferences!.getString(_accessKey);
    final legacyRefreshToken = _preferences!.getString(_refreshKey);
    if (legacyAccessToken == null || legacyRefreshToken == null) {
      return;
    }
    _accessToken = legacyAccessToken;
    _refreshToken = legacyRefreshToken;
    await _secureStorage.write(key: _accessKey, value: legacyAccessToken);
    await _secureStorage.write(key: _refreshKey, value: legacyRefreshToken);
    await _preferences!.remove(_accessKey);
    await _preferences!.remove(_refreshKey);
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
    ApiException? lastNetworkError;
    for (final candidateBaseUrl in _candidateBaseUrls) {
      try {
        return await _sendToBaseUrl(
          candidateBaseUrl,
          method,
          path,
          body: body,
          requiresAuth: requiresAuth,
          retryOnAuthFailure: retryOnAuthFailure,
        );
      } on ApiException catch (error) {
        if (error.code != 'network_error') {
          rethrow;
        }
        lastNetworkError = error;
      }
    }
    throw lastNetworkError ??
        const ApiException(
          'Network connection lost.',
          statusCode: 0,
          code: 'network_error',
        );
  }

  Future<http.Response> _sendMultipart(
    String method,
    String path, {
    required Map<String, String> fields,
    Map<String, String>? filePaths,
    bool requiresAuth = true,
    bool retryOnAuthFailure = true,
  }) async {
    ApiException? lastNetworkError;
    for (final candidateBaseUrl in _candidateBaseUrls) {
      try {
        return await _sendMultipartToBaseUrl(
          candidateBaseUrl,
          method,
          path,
          fields: fields,
          filePaths: filePaths,
          requiresAuth: requiresAuth,
          retryOnAuthFailure: retryOnAuthFailure,
        );
      } on ApiException catch (error) {
        if (error.code != 'network_error') {
          rethrow;
        }
        lastNetworkError = error;
      }
    }
    throw lastNetworkError ??
        const ApiException(
          'Network connection lost.',
          statusCode: 0,
          code: 'network_error',
        );
  }

  List<String> get _candidateBaseUrls {
    final seen = <String>{};
    return [baseUrl, ...fallbackBaseUrls]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList(growable: false);
  }

  Future<http.Response> _sendToBaseUrl(
    String candidateBaseUrl,
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool requiresAuth,
    required bool retryOnAuthFailure,
  }) async {
    final uri = Uri.parse('$candidateBaseUrl$path');
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
        case 'PATCH':
          response = await _client.patch(
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
      final code = payload?['code']?.toString();
      final message = _errorMessageFromPayload(payload);
      throw ApiException(message, statusCode: response.statusCode, code: code);
    }

    return response;
  }

  Future<http.Response> _sendMultipartToBaseUrl(
    String candidateBaseUrl,
    String method,
    String path, {
    required Map<String, String> fields,
    Map<String, String>? filePaths,
    required bool requiresAuth,
    required bool retryOnAuthFailure,
  }) async {
    final uri = Uri.parse('$candidateBaseUrl$path');
    final request = http.MultipartRequest(method, uri);
    request.headers['Accept'] = 'application/json';
    if (requiresAuth && _accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }
    request.fields.addAll(fields);
    if (filePaths != null) {
      for (final entry in filePaths.entries) {
        if (entry.value.isEmpty) {
          continue;
        }
        request.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value),
        );
      }
    }

    late http.Response response;
    try {
      final streamed = await _client.send(request);
      response = await http.Response.fromStream(streamed);
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
      return _sendMultipart(
        method,
        path,
        fields: fields,
        filePaths: filePaths,
        requiresAuth: requiresAuth,
        retryOnAuthFailure: false,
      );
    }

    if (response.statusCode >= 400) {
      final payload = _tryDecodeMap(response.body);
      final code = payload?['code']?.toString();
      final message = _errorMessageFromPayload(payload);
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

  String _errorMessageFromPayload(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) {
      return 'Request failed.';
    }
    final detail = payload['detail']?.toString();
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    for (final entry in payload.entries) {
      final message = _flattenErrorValue(entry.value);
      if (message.isNotEmpty) {
        return '${entry.key}: $message';
      }
    }
    return 'Request failed.';
  }

  String _flattenErrorValue(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    if (value is List) {
      return value
          .map(_flattenErrorValue)
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final message = _flattenErrorValue(entry.value);
        if (message.isNotEmpty) {
          return '${entry.key}: $message';
        }
      }
    }
    return value.toString();
  }
}
