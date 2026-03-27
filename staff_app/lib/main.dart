import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

import 'api_client.dart';
import 'app_models.dart';

const String kBrandName = 'HEAVENECTION';
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

const Color kPrimary = Color(0xFF4D5C90);
const Color kPrimaryDark = Color(0xFF2E385E);
const Color kSoft = Color(0xFFE9ECF7);
const Color kBg = Color(0xFFF6F7FC);
const Color kGreen = Color(0xFF2D9D68);
const Color kOrange = Color(0xFFF0A53A);
const Color kRed = Color(0xFFD76666);
const Duration kHeartbeatInterval = Duration(seconds: 45);
const Duration kIdleMonitorInterval = Duration(seconds: 15);
const Duration kIdleWarningAfter = Duration(minutes: 5);
const Duration kIdleWarningGrace = Duration(minutes: 5);
const Duration kBackgroundSessionTimeout = Duration(minutes: 10);
const int kCallLogSyncAttempts = 6;
const Duration kCallLogSyncRetryDelay = Duration(seconds: 2);

void main() => runApp(const HeavenectionApp());

class HeavenectionApp extends StatelessWidget {
  const HeavenectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kBrandName,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          primary: kPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: kPrimaryDark,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: kPrimaryDark,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: const HeavenectionHome(),
    );
  }
}

class HeavenectionHome extends StatefulWidget {
  const HeavenectionHome({super.key});

  @override
  State<HeavenectionHome> createState() => _HeavenectionHomeState();
}

class _HeavenectionHomeState extends State<HeavenectionHome>
    with WidgetsBindingObserver {
  final phone = TextEditingController();
  final password = TextEditingController();
  final ApiClient _apiClient = ApiClient(baseUrl: kApiBaseUrl);

  StaffUser? _user;
  DailySummary _summary = DailySummary.empty();
  List<LeadItem> _leads = const [];

  bool _isBootstrapping = true;
  bool _isLoggingIn = false;
  bool _isLoadingData = false;
  bool _isSessionBusy = false;
  bool _isStartWorkPromptVisible = false;
  int _tab = 0;
  int _leadIndex = 0;
  String _callStatus = 'Call Back';
  String? _activeCallId;
  String? _activeCallLeadId;
  PendingDialerCall? _pendingDialerCall;
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;
  Timer? _heartbeatTimer;
  Timer? _idleMonitorTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _lastInteractionAt;
  DateTime? _backgroundedAt;
  DateTime? _warningShownAt;
  BuildContext? _idleWarningDialogContext;
  bool _isIdleWarningVisible = false;
  bool _isHeartbeatRequestInFlight = false;
  bool _isSyncingCallLog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    phone.dispose();
    password.dispose();
    _callTimer?.cancel();
    _heartbeatTimer?.cancel();
    _idleMonitorTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;

    if (_user == null) {
      if (state == AppLifecycleState.resumed) {
        _maybePromptStartWork();
      }
      return;
    }

    if (!_summary.workingNow) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_loadDashboardData(showLoader: false, promptStartWork: true));
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumeFromBackground());
    } else if (_isBackgroundState(state)) {
      _backgroundedAt ??= DateTime.now();
      _dismissIdleWarning();
      unawaited(_sendHeartbeat('background', source: 'lifecycle'));
    }
  }

  int get _safeLeadIndex {
    if (_leads.isEmpty) {
      return 0;
    }
    return _leadIndex.clamp(0, _leads.length - 1);
  }

  Future<void> _bootstrap() async {
    try {
      await _apiClient.loadStoredSession();
      final restoredUser = await _apiClient.restoreSession();
      if (restoredUser != null) {
        _user = restoredUser;
        await _loadDashboardData(showLoader: false, promptStartWork: true);
      }
    } catch (_) {
      await _apiClient.clearSession();
    } finally {
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    }
  }

  Future<void> _loadDashboardData({
    bool showLoader = true,
    bool promptStartWork = false,
  }) async {
    if (showLoader && mounted) {
      setState(() => _isLoadingData = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        _apiClient.fetchTodaySummary(),
        _apiClient.fetchAssignedLeads(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = results[0] as DailySummary;
        _leads = results[1] as List<LeadItem>;
        if (_leadIndex >= _leads.length) {
          _leadIndex = _leads.isEmpty ? 0 : _leads.length - 1;
        }
      });
      _syncPresenceMonitoring();
      if (_summary.currentState == 'warning' && !_isIdleWarningVisible) {
        unawaited(_showIdleWarning());
      }
      if (promptStartWork) {
        _maybePromptStartWork();
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (phone.text.trim().isEmpty || password.text.isEmpty) {
      _showMessage('Enter phone number and password.', isError: true);
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final user = await _apiClient.login(
        phone: phone.text.trim(),
        password: password.text,
      );
      if (user.role != 'staff') {
        await _apiClient.clearSession();
        _showMessage(
          'Use a staff account to sign in to the mobile app.',
          isError: true,
        );
        return;
      }
      _user = user;
      await _loadDashboardData(showLoader: false, promptStartWork: true);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _handleForcedLogout() async {
    _resetActiveCallTracking();
    _heartbeatTimer?.cancel();
    _idleMonitorTimer?.cancel();
    _dismissIdleWarning();
    await _apiClient.clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _user = null;
      _summary = DailySummary.empty();
      _leads = const [];
      _isStartWorkPromptVisible = false;
      _tab = 0;
      _leadIndex = 0;
      _lastInteractionAt = null;
      _backgroundedAt = null;
      _warningShownAt = null;
    });
    _showMessage('Session expired. Please sign in again.', isError: true);
  }

  Future<void> _logout() async {
    _resetActiveCallTracking();
    _heartbeatTimer?.cancel();
    _idleMonitorTimer?.cancel();
    _dismissIdleWarning();
    try {
      await _apiClient.logout();
    } catch (_) {
      await _apiClient.clearSession();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _user = null;
      _summary = DailySummary.empty();
      _leads = const [];
      _isStartWorkPromptVisible = false;
      _tab = 0;
      _leadIndex = 0;
      _lastInteractionAt = null;
      _backgroundedAt = null;
      _warningShownAt = null;
    });
  }

  Future<void> _startWork() async {
    if (_isSessionBusy) {
      return;
    }
    _registerInteraction(syncServer: false);
    setState(() => _isSessionBusy = true);
    try {
      final response = await _apiClient.startSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = response.summary;
        _lastInteractionAt = DateTime.now();
        _backgroundedAt = null;
        _warningShownAt = null;
      });
      _syncPresenceMonitoring();
      _isStartWorkPromptVisible = false;
      _showMessage('Work session started.');
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      _showMessage(error.message, isError: true);
      _maybePromptStartWork();
    } finally {
      if (mounted) {
        setState(() => _isSessionBusy = false);
      }
    }
  }

  Future<void> _endWork() async {
    if (_isSessionBusy) {
      return;
    }
    _registerInteraction(syncServer: false);
    setState(() => _isSessionBusy = true);
    try {
      final response = await _apiClient.endSession();
      if (!mounted) {
        return;
      }
      _dismissIdleWarning();
      setState(() {
        _summary = response.summary;
        _backgroundedAt = null;
        _warningShownAt = null;
      });
      _syncPresenceMonitoring();
      _showMessage('Work session closed.');
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSessionBusy = false);
      }
    }
  }

  Future<void> _sendHeartbeat(
    String state, {
    bool showErrors = false,
    bool interaction = false,
    String source = 'timer',
  }) async {
    if (_user == null || !_summary.workingNow || _isHeartbeatRequestInFlight) {
      return;
    }

    _isHeartbeatRequestInFlight = true;
    try {
      final response = await _apiClient.sendHeartbeat(
        state: state,
        interaction: interaction,
        source: source,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = response.summary;
        if (interaction) {
          _lastInteractionAt = DateTime.now();
        }
      });
      _syncPresenceMonitoring();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.statusCode == 409 || error.statusCode == 404) {
        await _loadDashboardData(showLoader: false, promptStartWork: true);
        return;
      }
      if (showErrors) {
        _showMessage(error.message, isError: true);
      }
    } finally {
      _isHeartbeatRequestInFlight = false;
    }
  }

  void _resetActiveCallTracking() {
    _callTimer?.cancel();
    _activeCallId = null;
    _activeCallLeadId = null;
    _pendingDialerCall = null;
    _elapsed = Duration.zero;
    _isSyncingCallLog = false;
  }

  LeadItem? _leadById(String? leadId) {
    if (leadId == null) {
      return null;
    }
    for (final lead in _leads) {
      if (lead.id == leadId) {
        return lead;
      }
    }
    return null;
  }

  Future<void> _placeCallForLead(LeadItem lead) async {
    final canReadCallLog = await _ensureCallLogAccess();
    if (!canReadCallLog) {
      return;
    }

    final dialStartedAt = DateTime.now();
    final call = await _apiClient.startCall(leadId: lead.id);
    final launched = await FlutterPhoneDirectCaller.callNumber(lead.phone);
    if (launched != true) {
      await _apiClient.endCall(
        callId: call.id,
        status: _statusValue(_callStatus),
        durationSeconds: 0,
        endedAt: dialStartedAt,
        source: 'direct_call_failed',
      );
      _showMessage('Unable to place the call from the app.', isError: true);
      return;
    }

    _callTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _activeCallId = call.id;
      _activeCallLeadId = lead.id;
      _pendingDialerCall = PendingDialerCall(
        callId: call.id,
        leadId: lead.id,
        phone: lead.phone,
        startedAt: dialStartedAt,
      );
      _elapsed = Duration.zero;
    });
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _startCall() async {
    _registerInteraction(syncServer: false);
    if (_leads.isEmpty) {
      _showMessage('No assigned leads available.', isError: true);
      return;
    }
    if (!_summary.workingNow) {
      _showMessage('Start work before placing calls.', isError: true);
      return;
    }
    if (_activeCallId != null) {
      _showMessage(
        'Finish the current call before starting another.',
        isError: true,
      );
      return;
    }

    final lead = _leads[_safeLeadIndex];
    try {
      await _placeCallForLead(lead);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      _showMessage(error.message, isError: true);
    }
  }

  Future<void> _endCall() async {
    _registerInteraction(syncServer: false);
    if (_activeCallId == null) {
      _showMessage('Start a call before syncing it.', isError: true);
      return;
    }

    await _syncCallFromLog(
      allowManualFallback: true,
      showMissingMessage: true,
    );
  }

  Future<bool> _ensureCallLogAccess() async {
    if (!Platform.isAndroid) {
      _showMessage('Automatic call sync is available on Android only.', isError: true);
      return false;
    }

    try {
      await CallLog.query(
        dateTimeFrom: DateTime.now().subtract(const Duration(minutes: 1)),
        dateTimeTo: DateTime.now(),
        type: CallType.outgoing,
      );
      return true;
    } catch (_) {
      _showMessage(
        'Allow call log access in Android permissions to sync calls automatically.',
        isError: true,
      );
      return false;
    }
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _phoneMatches(String value, String target) {
    final normalizedValue = _normalizePhone(value);
    final normalizedTarget = _normalizePhone(target);
    if (normalizedValue.isEmpty || normalizedTarget.isEmpty) {
      return false;
    }
    return normalizedValue.endsWith(normalizedTarget) ||
        normalizedTarget.endsWith(normalizedValue);
  }

  Future<CallLogEntry?> _findMatchingCallLogEntry(
    PendingDialerCall pendingCall,
  ) async {
    final entries = await CallLog.query(
      dateTimeFrom: pendingCall.startedAt.subtract(const Duration(minutes: 2)),
      dateTimeTo: DateTime.now().add(const Duration(minutes: 1)),
      type: CallType.outgoing,
    );

    final sortedEntries = entries.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

    for (final entry in sortedEntries) {
      final timestamp = entry.timestamp;
      final number = entry.number ?? entry.formattedNumber ?? '';
      if (timestamp == null || !_phoneMatches(number, pendingCall.phone)) {
        continue;
      }

      final startedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (startedAt.isBefore(
        pendingCall.startedAt.subtract(const Duration(minutes: 2)),
      )) {
        continue;
      }
      return entry;
    }

    return null;
  }

  Future<NoAnswerDecision?> _askNoAnswerDecision() async {
    if (!mounted) {
      return null;
    }

    return showDialog<NoAnswerDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('No Answer?'),
          content: const Text(
            'The customer did not attend the call. Mark it as No Answer or call again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(NoAnswerDecision.markNoAnswer);
              },
              child: const Text('Mark No Answer'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(NoAnswerDecision.callAgain);
              },
              child: const Text('Call Again'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _completeNoAnswerCall(
    PendingDialerCall pendingCall,
    DateTime endedAt, {
    required bool callAgain,
  }) async {
    final call = await _apiClient.endCall(
      callId: pendingCall.callId,
      status: 'no_answer',
      durationSeconds: 0,
      endedAt: endedAt,
      source: callAgain ? 'call_log_no_answer_recall' : 'call_log_no_answer',
    );

    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    setState(() => _callStatus = 'No Answer');
    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (callAgain) {
      _showMessage('Marked as No Answer. Calling again.');
      final lead = _leadById(pendingCall.leadId);
      if (lead != null) {
        await _placeCallForLead(lead);
      } else {
        _showMessage('Lead was updated, but a new call could not be started.', isError: true);
      }
      return;
    }

    if (call.status == 'no_answer') {
      _showMessage('Call marked as No Answer.');
    } else {
      _showMessage('Call duration was less than 5 seconds, so it was not counted.', isError: true);
    }
  }

  Future<void> _completeCallSync(
    PendingDialerCall pendingCall,
    CallLogEntry entry,
  ) async {
    final durationSeconds = entry.duration ?? 0;
    final startedAt = DateTime.fromMillisecondsSinceEpoch(
      entry.timestamp ?? pendingCall.startedAt.millisecondsSinceEpoch,
    );
    final endedAt = startedAt.add(Duration(seconds: durationSeconds));

    if (durationSeconds == 0) {
      final decision = await _askNoAnswerDecision();
      if (decision == null) {
        return;
      }
      await _completeNoAnswerCall(
        pendingCall,
        endedAt,
        callAgain: decision == NoAnswerDecision.callAgain,
      );
      return;
    }

    final call = await _apiClient.endCall(
      callId: pendingCall.callId,
      status: _statusValue(_callStatus),
      durationSeconds: durationSeconds,
      endedAt: endedAt,
      source: 'call_log',
    );

    _callTimer?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _elapsed = Duration(seconds: durationSeconds);
      _activeCallId = null;
      _activeCallLeadId = null;
      _pendingDialerCall = null;
    });

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

      if (call.status == 'invalid_short') {
      _showMessage('Call duration was less than 5 seconds, so it was not counted.', isError: true);
      } else {
        _showMessage('Call synced from phone log.');
      }
  }

  Future<void> _completeCallManually({required String source}) async {
    if (_activeCallId == null) {
      return;
    }

    final call = await _apiClient.endCall(
      callId: _activeCallId!,
      status: _statusValue(_callStatus),
      source: source,
    );

    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (call.status == 'invalid_short') {
      _showMessage('Call duration was less than 5 seconds, so it was not counted.', isError: true);
    } else {
      _showMessage('Call ended without phone log sync.', isError: true);
    }
  }

  Future<bool> _syncCallFromLog({
    required bool allowManualFallback,
    bool showMissingMessage = false,
  }) async {
    final pendingCall = _pendingDialerCall;
    if (pendingCall == null || _isSyncingCallLog) {
      return false;
    }

    final canReadCallLog = await _ensureCallLogAccess();
    if (!canReadCallLog) {
      if (allowManualFallback) {
        await _completeCallManually(source: 'manual_no_call_log');
      }
      return false;
    }

    _isSyncingCallLog = true;
    try {
      for (var attempt = 0; attempt < kCallLogSyncAttempts; attempt++) {
        final entry = await _findMatchingCallLogEntry(pendingCall);
        if (entry != null) {
          await _completeCallSync(pendingCall, entry);
          return true;
        }

        if (attempt < kCallLogSyncAttempts - 1) {
          await Future<void>.delayed(kCallLogSyncRetryDelay);
        }
      }

      if (allowManualFallback) {
        await _completeCallManually(source: 'manual_call_log_miss');
      } else if (showMissingMessage) {
        _showMessage(
          'No matching phone call log was found yet. Open the app again after the call ends.',
          isError: true,
        );
      }
      return false;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    } catch (_) {
      if (allowManualFallback) {
        await _completeCallManually(source: 'manual_call_log_error');
      } else if (showMissingMessage) {
        _showMessage('Unable to read the phone call log right now.', isError: true);
      }
      return false;
    } finally {
      _isSyncingCallLog = false;
    }
  }

  bool _isBackgroundState(AppLifecycleState state) {
    return state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
  }

  void _syncPresenceMonitoring() {
    _heartbeatTimer?.cancel();
    _idleMonitorTimer?.cancel();
    if (!_summary.workingNow) {
      _lastInteractionAt = null;
      _backgroundedAt = null;
      _warningShownAt = null;
      _dismissIdleWarning();
      return;
    }

    _lastInteractionAt ??= DateTime.now();
    _heartbeatTimer = Timer.periodic(kHeartbeatInterval, (_) {
      if (_lifecycleState == AppLifecycleState.resumed &&
          !_isIdleWarningVisible &&
          _summary.currentState != 'offline') {
        unawaited(_sendHeartbeat('foreground', source: 'timer'));
      }
    });
    _idleMonitorTimer = Timer.periodic(kIdleMonitorInterval, (_) {
      _evaluateIdleState();
    });
  }

  Future<void> _handleResumeFromBackground() async {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    await _loadDashboardData(showLoader: false, promptStartWork: true);
    if (!_summary.workingNow) {
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >=
              kBackgroundSessionTimeout) {
        _showMessage(
          'Work session stopped after 10 minutes in background.',
          isError: true,
        );
      }
      return;
    }

    _lastInteractionAt = DateTime.now();
    await _sendHeartbeat(
      'foreground',
      interaction: true,
      source: 'lifecycle',
    );
    if (_pendingDialerCall != null) {
      await _syncCallFromLog(
        allowManualFallback: false,
        showMissingMessage: false,
      );
    }
  }

  void _evaluateIdleState() {
    if (!mounted ||
        !_summary.workingNow ||
        _isBackgroundState(_lifecycleState)) {
      return;
    }

    final now = DateTime.now();
    final warningShownAt = _warningShownAt;
    if (warningShownAt != null) {
      if (now.difference(warningShownAt) >= kIdleWarningGrace) {
        unawaited(_markOfflineFromInactivity());
      }
      return;
    }

    if (_summary.currentState == 'offline') {
      return;
    }

    final lastInteractionAt = _lastInteractionAt ?? now;
    if (now.difference(lastInteractionAt) >= kIdleWarningAfter) {
      unawaited(_showIdleWarning());
    }
  }

  void _registerInteraction({bool syncServer = true}) {
    _lastInteractionAt = DateTime.now();
    if (!syncServer ||
        !_summary.workingNow ||
        _isIdleWarningVisible ||
        _isHeartbeatRequestInFlight) {
      return;
    }

    if (_summary.currentState == 'offline' || _summary.currentState == 'warning') {
      unawaited(
        _sendHeartbeat(
          'foreground',
          interaction: true,
          source: 'user_action',
        ),
      );
    }
  }

  void _dismissIdleWarning() {
    final dialogContext = _idleWarningDialogContext;
    _idleWarningDialogContext = null;
    _warningShownAt = null;
    _isIdleWarningVisible = false;
    if (dialogContext == null) {
      return;
    }
    try {
      final navigator = Navigator.of(dialogContext, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (_) {
      // Ignore stale dialog context during lifecycle changes.
    }
  }

  Future<void> _showIdleWarning() async {
    if (!mounted ||
        !_summary.workingNow ||
        _isIdleWarningVisible ||
        _isBackgroundState(_lifecycleState)) {
      return;
    }

    _isIdleWarningVisible = true;
    _warningShownAt = DateTime.now();
    await _sendHeartbeat('warning', source: 'idle_warning');
    if (!mounted || !_summary.workingNow) {
      _isIdleWarningVisible = false;
      _warningShownAt = null;
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _idleWarningDialogContext = dialogContext;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('Still Working?'),
            content: const Text(
              'No activity was detected. Respond within 5 minutes to stay online.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  _isIdleWarningVisible = false;
                  _warningShownAt = null;
                  await _endWork();
                },
                child: const Text('End Work'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  _isIdleWarningVisible = false;
                  _warningShownAt = null;
                  await _acknowledgeIdleWarning();
                },
                child: const Text("I'm Here"),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _idleWarningDialogContext = null;
      _isIdleWarningVisible = false;
    });
  }

  Future<void> _acknowledgeIdleWarning() async {
    _lastInteractionAt = DateTime.now();
    await _sendHeartbeat(
      'foreground',
      interaction: true,
      source: 'warning_acknowledged',
      showErrors: true,
    );
    if (mounted && _summary.workingNow) {
      _showMessage('You are back online.');
    }
  }

  Future<void> _markOfflineFromInactivity() async {
    if (!_summary.workingNow || _summary.currentState == 'offline') {
      return;
    }

    _dismissIdleWarning();
    await _sendHeartbeat('offline', source: 'idle_timeout');
    if (mounted && _summary.workingNow) {
      _showMessage('Marked offline due to inactivity.', isError: true);
    }
  }

  void _maybePromptStartWork() {
    if (!mounted ||
        _user == null ||
        _summary.workingNow ||
        _isSessionBusy ||
        _isStartWorkPromptVisible) {
      return;
    }

    _isStartWorkPromptVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isStartWorkPromptVisible = false;
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Start Work'),
              content: const Text(
                'Start your work session to continue to the dashboard.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    _isStartWorkPromptVisible = false;
                    await _logout();
                  },
                  child: const Text('Logout'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    _isStartWorkPromptVisible = false;
                    await _startWork();
                  },
                  child: const Text('Start Work'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        _isStartWorkPromptVisible = false;
      });
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kRed : kPrimaryDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _statusValue(String label) {
    return switch (label) {
      'Interested' => 'interested',
      'Not Interested' => 'not_interested',
      'No Answer' => 'no_answer',
      'Call Back' => 'call_back',
      'Converted' => 'converted',
      _ => 'call_back',
    };
  }

  String _formatTimer(Duration duration) {
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return _login();
    }

    final lead = _leads.isEmpty ? null : _leads[_safeLeadIndex];
    final pages = [_dashboard(), _leadList(), _call(lead)];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _registerInteraction(),
      child: Scaffold(
        appBar: AppBar(
          title: const BrandWordmark(
            titleSize: 18,
            subtitle: 'CallTrack',
            subtitleSize: 11,
            markSize: 36,
          ),
          actions: [
            IconButton(
              onPressed: _isLoadingData
                  ? null
                  : () {
                      _registerInteraction(syncServer: false);
                      _loadDashboardData();
                    },
              icon: _isLoadingData
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            IconButton(
              onPressed: () {
                _registerInteraction(syncServer: false);
                _logout();
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(child: pages[_tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            _registerInteraction(syncServer: false);
            setState(() => _tab = value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Leads',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call),
              label: 'Call',
            ),
          ],
        ),
      ),
    );
  }

  Widget _login() {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kSoft, Colors.white, kSoft.withValues(alpha: 0.45)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: BrandWordmark(
                      centered: true,
                      titleSize: 30,
                      subtitle: 'CallTrack',
                      subtitleSize: 14,
                      markSize: 90,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in with your assigned phone number and password.',
                    style: TextStyle(fontSize: 17, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _isLoggingIn ? null : _handleLogin,
                    icon: _isLoggingIn
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isLoggingIn ? 'Signing In...' : 'Login'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'API: $kApiBaseUrl',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadDashboardData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimaryDark, kPrimary]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandWordmark(
                  titleSize: 22,
                  subtitle: 'Daily Overview',
                  subtitleSize: 12,
                  markSize: 48,
                  onDark: true,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _summary.statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Today at a glance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Logged in as ${_user?.name ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_summary.workingNow || _isSessionBusy)
                      ? null
                      : () => _startWork(),
                  icon: const Icon(Icons.play_circle_fill),
                  label: const Text('Start Work'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!_summary.workingNow || _isSessionBusy)
                      ? null
                      : () => _endWork(),
                  style: ElevatedButton.styleFrom(backgroundColor: kRed),
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('End Work'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Today summary',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InfoCard(
                  title: 'Hours',
                  value: _summary.activeLabel,
                  color: kPrimary,
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoCard(
                  title: 'Calls',
                  value: _summary.callsCount.toString(),
                  color: kOrange,
                  icon: Icons.call,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoCard(
                  title: 'Status',
                  value: _summary.statusLabel,
                  color: kGreen,
                  icon: Icons.trending_up,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Progress',
            value: _summary.resultLabel,
            color: kPrimaryDark,
            icon: Icons.analytics_outlined,
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () {
              _registerInteraction(syncServer: false);
              setState(() => _tab = 1);
            },
            icon: const Icon(Icons.people),
            label: const Text('Open Lead List'),
          ),
        ],
      ),
    );
  }

  Widget _leadList() {
    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadDashboardData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Assigned leads',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_leads.length} leads assigned for follow-up.',
            style: const TextStyle(fontSize: 16.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          if (_leads.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'No assigned leads available right now.',
                style: TextStyle(fontSize: 16),
              ),
            ),
          for (var i = 0; i < _leads.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: kSoft,
                          foregroundColor: kPrimary,
                          child: Text(_leads[i].name.characters.first),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _leads[i].name,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _leads[i].phone,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(label: _leads[i].statusLabel),
                      ],
                    ),
                    if (_leads[i].notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _leads[i].notes,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        _registerInteraction(syncServer: false);
                        setState(() {
                          _leadIndex = i;
                          _callStatus = _leads[i].statusLabel == 'Interested'
                              ? 'Interested'
                              : 'Call Back';
                          _tab = 2;
                        });
                      },
                      icon: const Icon(Icons.call),
                      label: const Text('Open Call Screen'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _call(LeadItem? lead) {
    final hasActiveCallForLead = lead != null && _activeCallLeadId == lead.id;
    const choices = [
      'Interested',
      'Not Interested',
      'No Answer',
      'Call Back',
      'Converted',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'Call screen',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Calls start directly from the app and sync from the Android phone log when the call ends.',
          style: TextStyle(fontSize: 16.5, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (lead == null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Text(
              'Choose a lead from the list to begin calling.',
              style: TextStyle(fontSize: 16),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lead.phone,
                  style: const TextStyle(fontSize: 17, color: Colors.black54),
                ),
                if (lead.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(lead.notes, style: const TextStyle(fontSize: 16)),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: kSoft,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Synced timer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTimer(
                          hasActiveCallForLead ? _elapsed : Duration.zero,
                        ),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _summary.workingNow ? () => _startCall() : null,
                        icon: const Icon(Icons.phone_forwarded),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: hasActiveCallForLead ? () => _endCall() : null,
                        style: ElevatedButton.styleFrom(backgroundColor: kRed),
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync Call'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'Call result',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: choices
              .map(
                (item) => ChoiceChip(
                  selected: _callStatus == item,
                  onSelected: (_) {
                    _registerInteraction(syncServer: false);
                    setState(() => _callStatus = item);
                  },
                  selectedColor: kPrimary,
                  backgroundColor: Colors.white,
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        color: _callStatus == item
                            ? Colors.white
                            : kPrimaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class PendingDialerCall {
  const PendingDialerCall({
    required this.callId,
    required this.leadId,
    required this.phone,
    required this.startedAt,
  });

  final String callId;
  final String leadId;
  final String phone;
  final DateTime startedAt;
}

enum NoAnswerDecision {
  markNoAnswer,
  callAgain,
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    required this.titleSize,
    required this.subtitle,
    required this.subtitleSize,
    required this.markSize,
    this.centered = false,
    this.onDark = false,
  });

  final double titleSize;
  final String subtitle;
  final double subtitleSize;
  final double markSize;
  final bool centered;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : kPrimaryDark;
    final subtitleColor = onDark ? Colors.white70 : Colors.black54;

    return Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/heavenection_mark.png',
          width: markSize,
          height: markSize,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                kBrandName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Interested' => kGreen,
      'Call Back' => kOrange,
      'No Answer' => kRed,
      'Converted' => kGreen,
      'Not Interested' => kRed,
      _ => kPrimary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
