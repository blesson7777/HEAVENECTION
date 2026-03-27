import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:video_player/video_player.dart';

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
  LearningSummary _learningSummary = LearningSummary.empty();
  List<LeadItem> _leads = const [];
  List<TrainingLesson> _lessons = const [];

  bool _isBootstrapping = true;
  bool _isLoggingIn = false;
  bool _isLoadingData = false;
  bool _isSessionBusy = false;
  bool _isTrainingPromptVisible = false;
  bool _isNetworkErrorVisible = false;
  int _tab = 0;
  int _lastLoadedTab = 0;
  int _leadIndex = 0;
  String _callStatus = 'Call Back';
  String _learningQuery = '';
  String? _loginErrorText;
  String _networkErrorMessage = 'Network connection lost.';
  String? _activeCallId;
  String? _activeCallLeadId;
  PendingDialerCall? _pendingDialerCall;
  String? _pendingStatusCallId;
  String _pendingStatusLeadName = '';
  String _pendingStatusLeadPhone = '';
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;
  Timer? _heartbeatTimer;
  Timer? _idleMonitorTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _lastInteractionAt;
  DateTime? _backgroundedAt;
  DateTime? _warningShownAt;
  BuildContext? _idleWarningDialogContext;
  BuildContext? _callStatusDialogContext;
  bool _isIdleWarningVisible = false;
  bool _isHeartbeatRequestInFlight = false;
  bool _isSyncingCallLog = false;
  bool _isCallStatusPromptVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updatePreferredOrientations();
    _watchConnectivity();
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
    _connectivitySubscription?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;

    if (_user == null) {
      return;
    }

    if (!_summary.workingNow) {
      if (state == AppLifecycleState.resumed) {
        unawaited(
          _loadDashboardData(showLoader: false, promptTrainingGate: true),
        );
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

  List<TrainingLesson> get _pendingMandatoryLessons => _lessons
      .where((lesson) => lesson.isMandatory && !lesson.isCompleted)
      .toList();

  bool get _hasPendingMandatoryTraining =>
      _pendingMandatoryLessons.isNotEmpty ||
      _learningSummary.hasPendingMandatory ||
      _summary.trainingRequired;

  bool get _hasPendingCallStatus =>
      _pendingStatusCallId != null && _pendingStatusCallId!.isNotEmpty;

  List<TrainingLesson> get _filteredLessons {
    final query = _learningQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _lessons;
    }
    return _lessons
        .where((lesson) => lesson.searchableText.contains(query))
        .toList();
  }

  void _applyLearningPayload(LearningCenterPayload payload) {
    _learningSummary = payload.summary;
    _lessons = payload.lessons;
  }

  void _syncPendingCallStatusFromSummary() {
    if (_summary.pendingCallStatusRequired && _summary.pendingCallId.isNotEmpty) {
      _pendingStatusCallId = _summary.pendingCallId;
      _pendingStatusLeadName = _summary.pendingCallLeadName;
      _pendingStatusLeadPhone = _summary.pendingCallLeadPhone;
      return;
    }
    _clearPendingCallStatus();
  }

  void _clearPendingCallStatus() {
    _pendingStatusCallId = null;
    _pendingStatusLeadName = '';
    _pendingStatusLeadPhone = '';
  }

  void _dismissPendingCallStatusPrompt() {
    final dialogContext = _callStatusDialogContext;
    _callStatusDialogContext = null;
    _isCallStatusPromptVisible = false;
    if (dialogContext == null) {
      return;
    }
    try {
      final navigator = Navigator.of(dialogContext, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (_) {
      // Ignore stale dialog context during navigation changes.
    }
  }

  void _schedulePendingCallStatusPrompt() {
    if (!mounted || !_hasPendingCallStatus || _isCallStatusPromptVisible) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasPendingCallStatus || _isCallStatusPromptVisible) {
        return;
      }
      unawaited(_showPendingCallStatusPrompt());
    });
  }

  Future<bool> _ensurePendingCallStatusResolved() async {
    if (!_hasPendingCallStatus) {
      return true;
    }
    _showMessage(
      'Mark the previous call result before moving to the next lead.',
      isError: true,
    );
    _schedulePendingCallStatusPrompt();
    return false;
  }

  void _updatePreferredOrientations() {
    if (_user == null) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      return;
    }
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _watchConnectivity() {
    final connectivity = Connectivity();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasConnection) {
        _showNetworkError(
          'You are offline. Check mobile data, Wi-Fi, or your server connection.',
        );
        return;
      }
      if (_isNetworkErrorVisible) {
        unawaited(_recoverFromNetworkError());
      }
    });
  }

  void _showNetworkError(String message) {
    if (!mounted) {
      return;
    }
    try {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (_) {
      // Ignore navigator state issues while surfacing the offline view.
    }
    setState(() {
      _networkErrorMessage = message;
      _isNetworkErrorVisible = true;
      _lastLoadedTab = _tab;
    });
  }

  Future<void> _recoverFromNetworkError() async {
    try {
      if (mounted) {
        setState(() => _isNetworkErrorVisible = false);
      }
      if (_user == null) {
        await _apiClient.loadStoredSession();
        final restoredUser = await _apiClient.restoreSession();
        if (restoredUser != null) {
          _user = restoredUser;
          _updatePreferredOrientations();
          await _loadDashboardData(showLoader: false, promptTrainingGate: true);
        }
      } else {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
      }

      if (!mounted) {
        return;
      }
      if (_isNetworkErrorVisible) {
        return;
      }
      setState(() {
        _isNetworkErrorVisible = false;
        _tab = _lastLoadedTab < 0
            ? 0
            : (_lastLoadedTab > 2 ? 2 : _lastLoadedTab);
      });
    } on ApiException catch (error) {
      if (error.code != 'network_error') {
        _showMessage(error.message, isError: true);
      } else {
        _showNetworkError(
          'Still unable to reconnect. Check internet, Wi-Fi, or server access.',
        );
      }
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _apiClient.loadStoredSession();
      final restoredUser = await _apiClient.restoreSession();
      if (restoredUser != null) {
        _user = restoredUser;
        _updatePreferredOrientations();
        await _loadDashboardData(showLoader: false, promptTrainingGate: true);
      }
    } on ApiException catch (error) {
      if (error.code == 'network_error') {
        _showNetworkError('Unable to reach the server. Reconnect to continue.');
      } else {
        await _apiClient.clearSession();
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
    bool promptTrainingGate = false,
  }) async {
    if (showLoader && mounted) {
      setState(() => _isLoadingData = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        _apiClient.fetchTodaySummary(),
        _apiClient.fetchAssignedLeads(),
        _apiClient.fetchLearningCenter(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = results[0] as DailySummary;
        _leads = results[1] as List<LeadItem>;
        _applyLearningPayload(results[2] as LearningCenterPayload);
        _syncPendingCallStatusFromSummary();
        _isNetworkErrorVisible = false;
        if (_leadIndex >= _leads.length) {
          _leadIndex = _leads.isEmpty ? 0 : _leads.length - 1;
        }
      });
      _syncPresenceMonitoring();
      if (_summary.pendingCallStatusRequired) {
        _schedulePendingCallStatusPrompt();
        return;
      }
      if (_summary.currentState == 'warning' && !_isIdleWarningVisible) {
        unawaited(_showIdleWarning());
      }
      if (promptTrainingGate) {
        _maybePromptMandatoryTraining();
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to refresh the app. Reconnect and the last page will return automatically.',
        );
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
    setState(() => _loginErrorText = null);
    if (phone.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => _loginErrorText = 'Enter phone number and password.');
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
      _updatePreferredOrientations();
      await _loadDashboardData(showLoader: false, promptTrainingGate: true);
    } on ApiException catch (error) {
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to reach the server. Reconnect and the app will restore automatically.',
        );
      } else if (mounted) {
        setState(() => _loginErrorText = error.message);
      }
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
    _dismissPendingCallStatusPrompt();
    await _apiClient.clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _user = null;
      _summary = DailySummary.empty();
      _learningSummary = LearningSummary.empty();
      _leads = const [];
      _lessons = const [];
      _isTrainingPromptVisible = false;
      _tab = 0;
      _leadIndex = 0;
      _learningQuery = '';
      _loginErrorText = null;
      _lastInteractionAt = null;
      _backgroundedAt = null;
      _warningShownAt = null;
      _clearPendingCallStatus();
    });
    _updatePreferredOrientations();
    _showMessage('Session expired. Please sign in again.', isError: true);
  }

  Future<void> _logout() async {
    _resetActiveCallTracking();
    _heartbeatTimer?.cancel();
    _idleMonitorTimer?.cancel();
    _dismissIdleWarning();
    _dismissPendingCallStatusPrompt();
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
      _learningSummary = LearningSummary.empty();
      _leads = const [];
      _lessons = const [];
      _isTrainingPromptVisible = false;
      _tab = 0;
      _leadIndex = 0;
      _learningQuery = '';
      _loginErrorText = null;
      _lastInteractionAt = null;
      _backgroundedAt = null;
      _warningShownAt = null;
      _clearPendingCallStatus();
    });
    _updatePreferredOrientations();
  }

  Future<void> _startWork({bool fromTraining = false}) async {
    if (_isSessionBusy) {
      return;
    }
    if (_hasPendingMandatoryTraining) {
      _showMessage(
        'Complete the required training before starting work.',
        isError: true,
      );
      _maybePromptMandatoryTraining(force: true);
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
      _isTrainingPromptVisible = false;
      _showMessage(
        fromTraining
            ? 'Training completed. Work session started.'
            : 'Work session started.',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to start work because the server is unreachable.',
        );
        return;
      }
      if (error.statusCode == 409 || error.code == 'training_required') {
        await _loadDashboardData(showLoader: false, promptTrainingGate: true);
        return;
      }
      _showMessage(error.message, isError: true);
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
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to end work because the network is unavailable.',
        );
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
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while syncing activity. The app will restore when the network returns.',
        );
        return;
      }
      if (error.statusCode == 409 || error.statusCode == 404) {
        await _loadDashboardData(showLoader: false, promptTrainingGate: true);
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
    if (!await _ensurePendingCallStatusResolved()) {
      return;
    }
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
      if (error.code == 'network_error') {
        _showNetworkError('Connection lost while preparing the call.');
        return;
      }
      if (error.statusCode == 409 && error.code == 'call_status_required') {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
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

    await _syncCallFromLog(allowManualFallback: true, showMissingMessage: true);
  }

  Future<bool> _ensureCallLogAccess() async {
    if (!Platform.isAndroid) {
      _showMessage(
        'Automatic call sync is available on Android only.',
        isError: true,
      );
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
        _showMessage(
          'Lead was updated, but a new call could not be started.',
          isError: true,
        );
      }
      return;
    }

    if (call.status == 'no_answer') {
      _showMessage('Call marked as No Answer.');
    } else {
      _showMessage(
        'Call duration was less than 5 seconds, so it was not counted.',
        isError: true,
      );
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
      durationSeconds: durationSeconds,
      endedAt: endedAt,
      source: 'call_log',
    );

    final lead = _leadById(pendingCall.leadId);
    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    setState(() {
      _elapsed = Duration(seconds: durationSeconds);
      if (call.status == 'started') {
        _pendingStatusCallId = call.id;
        _pendingStatusLeadName = lead?.name ?? '';
        _pendingStatusLeadPhone = lead?.phone ?? pendingCall.phone;
        _callStatus = 'Call Back';
      }
    });

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (call.status == 'invalid_short') {
      _showMessage(
        'Call duration was less than 5 seconds, so it was not counted.',
        isError: true,
      );
    } else if (call.status == 'started') {
      _schedulePendingCallStatusPrompt();
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
      source: source,
    );

    final leadId = _activeCallLeadId;
    final lead = _leadById(leadId);
    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    setState(() {
      if (call.status == 'started') {
        _pendingStatusCallId = call.id;
        _pendingStatusLeadName = lead?.name ?? '';
        _pendingStatusLeadPhone = lead?.phone ?? '';
        _callStatus = 'Call Back';
      }
    });

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (call.status == 'invalid_short') {
      _showMessage(
        'Call duration was less than 5 seconds, so it was not counted.',
        isError: true,
      );
    } else if (call.status == 'started') {
      _schedulePendingCallStatusPrompt();
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
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while syncing the call. The app will return when the network is back.',
        );
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    } catch (_) {
      if (allowManualFallback) {
        await _completeCallManually(source: 'manual_call_log_error');
      } else if (showMissingMessage) {
        _showMessage(
          'Unable to read the phone call log right now.',
          isError: true,
        );
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

    await _loadDashboardData(showLoader: false, promptTrainingGate: true);
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
    await _sendHeartbeat('foreground', interaction: true, source: 'lifecycle');
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

    if (_summary.currentState == 'offline' ||
        _summary.currentState == 'warning') {
      unawaited(
        _sendHeartbeat('foreground', interaction: true, source: 'user_action'),
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

  Future<void> _completeTrainingLesson(TrainingLesson lesson) async {
    try {
      final payload = await _apiClient.completeTrainingLesson(
        lessonId: lesson.id,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _applyLearningPayload(payload);
      });

      if (_hasPendingMandatoryTraining) {
        _showMessage(
          'Training saved. Complete the remaining required lessons.',
        );
        return;
      }

      if (!_summary.workingNow) {
        setState(() => _tab = 0);
        await _startWork(fromTraining: true);
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      _showMessage(error.message, isError: true);
    }
  }

  void _openLearningCenterFromPrompt() {
    if (!mounted) {
      return;
    }
    setState(() {
      _tab = 2;
      _lastLoadedTab = 2;
    });
  }

  void _maybePromptMandatoryTraining({bool force = false}) {
    if (!mounted ||
        _user == null ||
        _summary.workingNow ||
        _isSessionBusy ||
        _isTrainingPromptVisible ||
        (!_hasPendingMandatoryTraining && !force) ||
        _tab == 2) {
      return;
    }

    _isTrainingPromptVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isTrainingPromptVisible = false;
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
              title: const Text('Training Required'),
              content: Text(
                _learningSummary.nextRequiredTitle.isEmpty
                    ? 'Complete the required training lessons before starting work.'
                    : 'Complete the required training lessons before starting work. Next lesson: ${_learningSummary.nextRequiredTitle}.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    _isTrainingPromptVisible = false;
                    await _logout();
                  },
                  child: const Text('Logout'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    _isTrainingPromptVisible = false;
                    _openLearningCenterFromPrompt();
                  },
                  child: const Text('Open Learning Center'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        _isTrainingPromptVisible = false;
      });
    });
  }

  Future<bool> _submitPendingCallStatus(String label) async {
    final callId = _pendingStatusCallId;
    if (callId == null || callId.isEmpty) {
      return true;
    }

    try {
      await _apiClient.updateCallStatus(
        callId: callId,
        status: _statusValue(label),
      );
      if (!mounted) {
        return true;
      }

      setState(() {
        _callStatus = label;
        _clearPendingCallStatus();
      });
      await _loadDashboardData(showLoader: false, promptTrainingGate: true);
      if (mounted) {
        _showMessage('Call result saved as $label.');
      }
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return false;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while saving the call result. Reconnect to continue.',
        );
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    }
  }

  Future<void> _showPendingCallStatusPrompt() async {
    if (!mounted || !_hasPendingCallStatus || _isCallStatusPromptVisible) {
      return;
    }

    const choices = [
      'Interested',
      'Not Interested',
      'No Answer',
      'Call Back',
      'Converted',
    ];

    _isCallStatusPromptVisible = true;
    var selectedStatus = choices.contains(_callStatus) ? _callStatus : 'Call Back';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _callStatusDialogContext = dialogContext;
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text('Mark Call Result'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Complete the previous call result before moving to another lead.',
                    ),
                    if (_pendingStatusLeadName.isNotEmpty ||
                        _pendingStatusLeadPhone.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_pendingStatusLeadName.isNotEmpty)
                              Text(
                                _pendingStatusLeadName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (_pendingStatusLeadPhone.isNotEmpty)
                              Text(
                                _pendingStatusLeadPhone,
                                style: const TextStyle(color: Colors.black54),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: choices
                          .map(
                            (item) => ChoiceChip(
                              selected: selectedStatus == item,
                              onSelected: isSaving
                                  ? null
                                  : (_) {
                                      setDialogState(() => selectedStatus = item);
                                    },
                              selectedColor: kPrimary,
                              backgroundColor: Colors.white,
                              label: Text(
                                item,
                                style: TextStyle(
                                  color: selectedStatus == item
                                      ? Colors.white
                                      : kPrimaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            final saved = await _submitPendingCallStatus(
                              selectedStatus,
                            );
                            if (!mounted) {
                              return;
                            }
                            if (saved && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                              return;
                            }
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                          },
                    child: Text(isSaving ? 'Saving...' : 'Save Status'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _callStatusDialogContext = null;
      _isCallStatusPromptVisible = false;
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

    if (_isNetworkErrorVisible && _user == null) {
      return Scaffold(
        body: NetworkErrorView(
          message: _networkErrorMessage,
          onRetry: _recoverFromNetworkError,
        ),
      );
    }

    if (_user == null) {
      return _login();
    }
    final pages = [_dashboard(), _leadList(), _learningCenter()];

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
                      _loadDashboardData(promptTrainingGate: false);
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
        body: SafeArea(
          child: _isNetworkErrorVisible
              ? NetworkErrorView(
                  message: _networkErrorMessage,
                  onRetry: _recoverFromNetworkError,
                )
              : pages[_tab],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            _registerInteraction(syncServer: false);
            _lastLoadedTab = value;
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
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Learn',
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
                  if (_loginErrorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kRed.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: kRed),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _loginErrorText!,
                              style: const TextStyle(
                                color: kRed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
          if (_hasPendingMandatoryTraining) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kOrange.withValues(alpha: 0.24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.school, color: kOrange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Training pending',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _learningSummary.nextRequiredTitle.isEmpty
                        ? 'Complete the required training lessons to begin work.'
                        : 'Complete ${_learningSummary.pendingMandatoryCount} required lesson(s). Next: ${_learningSummary.nextRequiredTitle}.',
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      _registerInteraction(syncServer: false);
                      setState(() {
                        _tab = 2;
                        _lastLoadedTab = 2;
                      });
                    },
                    icon: const Icon(Icons.play_lesson),
                    label: const Text('Open Learning Center'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_summary.workingNow ||
                          _isSessionBusy ||
                          _hasPendingMandatoryTraining)
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
              setState(() {
                _tab = 1;
                _lastLoadedTab = 1;
              });
            },
            icon: const Icon(Icons.people),
            label: const Text('Open Lead List'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _registerInteraction(syncServer: false);
              setState(() {
                _tab = 2;
                _lastLoadedTab = 2;
              });
            },
            icon: const Icon(Icons.school),
            label: const Text('Open Learning Center'),
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
                      onPressed: () => _openCallScreenForLead(i),
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

  Future<void> _openCallScreenForLead(int index) async {
    if (index < 0 || index >= _leads.length) {
      return;
    }
    if (!await _ensurePendingCallStatusResolved()) {
      return;
    }
    if (!mounted) {
      return;
    }
    _registerInteraction(syncServer: false);
    setState(() {
      _leadIndex = index;
      _callStatus = 'Call Back';
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Call')),
          body: SafeArea(child: _call(_leads[index])),
        ),
      ),
    );
  }

  Widget _call(LeadItem? lead) {
    final hasActiveCallForLead = lead != null && _activeCallLeadId == lead.id;

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
                        onPressed: _summary.workingNow
                            ? () => _startCall()
                            : null,
                        icon: const Icon(Icons.phone_forwarded),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: hasActiveCallForLead
                            ? () => _endCall()
                            : null,
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
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment_turned_in, color: kPrimary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Call completion rule',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'After the call ends, the app will ask you to mark the result. The next lead stays blocked until that result is saved.',
                style: TextStyle(fontSize: 15.5, color: Colors.black54),
              ),
              if (_hasPendingCallStatus) ...[
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _showPendingCallStatusPrompt,
                  icon: const Icon(Icons.assignment_late),
                  label: const Text('Mark Previous Call Result'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _learningCenter() {
    final lessons = _filteredLessons;

    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadDashboardData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Learning Center',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _learningSummary.totalLessons == 0
                ? 'Training lessons published from the admin panel will appear here.'
                : '${_learningSummary.completedCount} of ${_learningSummary.totalLessons} lessons completed.',
            style: const TextStyle(fontSize: 16.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InfoCard(
                        title: 'Pending',
                        value: _learningSummary.pendingMandatoryCount
                            .toString(),
                        color: kOrange,
                        icon: Icons.pending_actions,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InfoCard(
                        title: 'Completed',
                        value: _learningSummary.completedCount.toString(),
                        color: kGreen,
                        icon: Icons.task_alt,
                      ),
                    ),
                  ],
                ),
                if (_hasPendingMandatoryTraining &&
                    _learningSummary.nextRequiredTitle.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'Next required lesson: ${_learningSummary.nextRequiredTitle}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kPrimaryDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) {
              setState(() => _learningQuery = value);
            },
            decoration: const InputDecoration(
              hintText: 'Search lessons, topics, or tags',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 18),
          if (_lessons.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Text(
                'No training lessons are available right now.',
                style: TextStyle(fontSize: 16),
              ),
            )
          else if (lessons.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Text(
                'No lessons matched your search.',
                style: TextStyle(fontSize: 16),
              ),
            )
          else
            for (final lesson in lessons)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TrainingLessonCard(
                  lesson: lesson,
                  onOpen: () async {
                    _registerInteraction(syncServer: false);
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TrainingLessonPage(
                          lesson: lesson,
                          onComplete: () => _completeTrainingLesson(lesson),
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ),
        ],
      ),
    );
  }
}

class _TrainingLessonCard extends StatelessWidget {
  const _TrainingLessonCard({required this.lesson, required this.onOpen});

  final TrainingLesson lesson;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final statusColor = lesson.isCompleted
        ? kGreen
        : (lesson.isMandatory ? kOrange : kPrimary);
    final statusLabel = lesson.isCompleted
        ? 'Completed'
        : (lesson.isMandatory ? 'Mandatory' : 'Optional');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  lesson.hasVideo ? Icons.ondemand_video : Icons.menu_book,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lesson.description.isEmpty
                          ? 'Open the lesson to review the training content.'
                          : lesson.description,
                      style: const TextStyle(
                        fontSize: 15.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StatusPill(label: statusLabel),
              if (lesson.searchKeywords.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lesson.searchKeywords,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kPrimaryDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onOpen,
            icon: Icon(
              lesson.isCompleted ? Icons.replay : Icons.play_circle_fill,
            ),
            label: Text(lesson.isCompleted ? 'Open Again' : 'Open Lesson'),
          ),
        ],
      ),
    );
  }
}

class TrainingLessonPage extends StatefulWidget {
  const TrainingLessonPage({
    super.key,
    required this.lesson,
    required this.onComplete,
  });

  final TrainingLesson lesson;
  final Future<void> Function() onComplete;

  @override
  State<TrainingLessonPage> createState() => _TrainingLessonPageState();
}

class _TrainingLessonPageState extends State<TrainingLessonPage> {
  VideoPlayerController? _controller;
  Future<void>? _videoFuture;
  bool _canComplete = false;
  bool _isCompleting = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _canComplete = widget.lesson.isCompleted || !widget.lesson.hasVideo;
    if (widget.lesson.hasVideo) {
      _initialiseVideo();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _initialiseVideo() {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.lesson.videoUrl),
    );
    controller.addListener(_handleVideoProgress);
    _controller = controller;
    _videoFuture = controller
        .initialize()
        .catchError((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _videoError =
                'Video could not be loaded. Review the lesson notes and complete it manually.';
            _canComplete = true;
          });
        })
        .then((_) {
          if (!mounted || !controller.value.isInitialized) {
            return;
          }
          controller.play();
          setState(() {});
        });
  }

  void _handleVideoProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _canComplete) {
      return;
    }

    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration > Duration.zero &&
        position >= duration - const Duration(seconds: 2)) {
      setState(() => _canComplete = true);
    }
  }

  Future<void> _completeLesson() async {
    if (_isCompleting || widget.lesson.isCompleted || !_canComplete) {
      return;
    }
    setState(() => _isCompleting = true);
    try {
      await widget.onComplete();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoWidget = widget.lesson.hasVideo
        ? FutureBuilder<void>(
            future: _videoFuture,
            builder: (context, snapshot) {
              if (_videoError != null) {
                return _TrainingVideoError(message: _videoError!);
              }
              final controller = _controller;
              if (controller == null ||
                  snapshot.connectionState != ConnectionState.done ||
                  !controller.value.isInitialized) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: VideoPlayer(controller),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton.filled(
                        onPressed: () {
                          if (controller.value.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                          setState(() {});
                        },
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: const VideoProgressColors(
                            playedColor: kPrimary,
                            bufferedColor: kSoft,
                            backgroundColor: Color(0xFFD9DFEF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          )
        : const _TrainingVideoError(
            message:
                'No video is attached to this lesson. Review the lesson notes and complete it when finished.',
          );

    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              widget.lesson.title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatusPill(
                  label: widget.lesson.isCompleted
                      ? 'Completed'
                      : (widget.lesson.isMandatory ? 'Mandatory' : 'Optional'),
                ),
                if (widget.lesson.searchKeywords.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.lesson.searchKeywords,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kPrimaryDark,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lesson overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.lesson.description.isEmpty
                        ? 'Review the training content and complete the lesson when you are done.'
                        : widget.lesson.description,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Training video',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  videoWidget,
                  if (!widget.lesson.isCompleted &&
                      widget.lesson.hasVideo &&
                      !_canComplete) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Watch the lesson until the end to unlock completion.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed:
                  widget.lesson.isCompleted || _isCompleting || !_canComplete
                  ? null
                  : _completeLesson,
              icon: _isCompleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                widget.lesson.isCompleted
                    ? 'Already Completed'
                    : _isCompleting
                    ? 'Saving...'
                    : 'Complete Training',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingVideoError extends StatelessWidget {
  const _TrainingVideoError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 15.5, color: Colors.black54),
      ),
    );
  }
}

class NetworkErrorView extends StatelessWidget {
  const NetworkErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryDark.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    onEnd: () {},
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: 92,
                          height: 92,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
                          ),
                        ),
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: kSoft,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(
                            Icons.cloud_off_rounded,
                            size: 42,
                            color: kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Connection Problem',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kSoft,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Troubleshooting',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: kPrimaryDark,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text('1. Check mobile data or Wi-Fi on the device.'),
                        SizedBox(height: 6),
                        Text('2. Confirm the local or live server is running.'),
                        SizedBox(height: 6),
                        Text(
                          '3. Wait a moment. The app will restore automatically when the connection returns.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

enum NoAnswerDecision { markNoAnswer, callAgain }

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
      'Completed' => kGreen,
      'Mandatory' => kOrange,
      'Optional' => kPrimary,
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
