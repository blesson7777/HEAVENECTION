import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
const Duration kBackgroundSessionTimeout = Duration(minutes: 5);
const Duration kShortCallReviewThreshold = Duration(seconds: 10);
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
  final _profileNameController = TextEditingController();
  final _profilePhoneController = TextEditingController();
  final _profileEmailController = TextEditingController();
  final _bankAccountNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  final _bankIfscController = TextEditingController();
  final _aadharNumberController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ApiClient _apiClient = ApiClient(baseUrl: kApiBaseUrl);
  static const MethodChannel _updaterChannel = MethodChannel(
    'heavenection/updater',
  );

  StaffUser? _user;
  StaffProfile? _profile;
  DailySummary _summary = DailySummary.empty();
  LearningSummary _learningSummary = LearningSummary.empty();
  List<LeadItem> _leads = const [];
  List<TrainingLesson> _lessons = const [];

  bool _isBootstrapping = true;
  bool _isLoggingIn = false;
  bool _isLoadingData = false;
  bool _isProfileLoading = false;
  bool _isProfileSaving = false;
  bool _isSessionBusy = false;
  bool _isTrainingPromptVisible = false;
  bool _isNetworkErrorVisible = false;
  int _tab = 0;
  int _lastLoadedTab = 0;
  int _leadIndex = 0;
  String _callStatus = 'Follow Up';
  String _learningQuery = '';
  String? _loginErrorText;
  String _networkErrorMessage = 'Network connection lost.';
  String? _activeCallId;
  String? _activeCallLeadId;
  PendingDialerCall? _pendingDialerCall;
  String? _pendingStatusCallId;
  String? _pendingStatusLeadId;
  String _pendingStatusLeadName = '';
  String _pendingStatusLeadPhone = '';
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;
  Timer? _heartbeatTimer;
  Timer? _idleMonitorTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _lastInteractionAt;
  DateTime? _lastCallActivityAt;
  DateTime? _backgroundedAt;
  BuildContext? _idleWarningDialogContext;
  BuildContext? _callStatusDialogContext;
  bool _isIdleWarningVisible = false;
  bool _isHeartbeatRequestInFlight = false;
  bool _isSyncingCallLog = false;
  bool _isCallStatusPromptVisible = false;
  bool _isCheckingForUpdate = false;
  bool _isUpdateDialogVisible = false;
  bool _isDownloadingUpdate = false;
  bool _hasCheckedAppUpdate = false;
  int _currentVersionCode = 0;
  String _currentVersionName = '';
  AppUpdateInfo? _pendingAppUpdate;
  File? _selectedAadharPhoto;
  bool _removeAadharPhoto = false;

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
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _profileEmailController.dispose();
    _bankAccountNameController.dispose();
    _bankNameController.dispose();
    _bankAccountNumberController.dispose();
    _bankIfscController.dispose();
    _aadharNumberController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
      if (_hasActiveCustomerCall) {
        _backgroundedAt = null;
      } else {
        _backgroundedAt ??= DateTime.now();
      }
      _dismissIdleWarning();
      if (!_hasActiveCustomerCall) {
        unawaited(_sendHeartbeat('background', source: 'lifecycle'));
      }
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

  bool get _hasActiveCustomerCall =>
      _activeCallId != null && _pendingDialerCall != null;

  List<TrainingLesson> get _filteredLessons {
    final query = _learningQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _lessons;
    }
    return _lessons
        .where((lesson) => lesson.searchableText.contains(query))
        .toList();
  }

  void _applyProfile(StaffProfile profile) {
    _profile = profile;
    _user = StaffUser(
      id: profile.id,
      name: profile.name,
      phone: profile.phone,
      role: profile.role,
    );
    _profileNameController.text = profile.name;
    _profilePhoneController.text = profile.phone;
    _profileEmailController.text = profile.email;
    _bankAccountNameController.text = profile.bankAccountName;
    _bankNameController.text = profile.bankName;
    _bankAccountNumberController.text = profile.bankAccountNumber;
    _bankIfscController.text = profile.bankIfscCode;
    _aadharNumberController.text = profile.aadharNumber;
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _selectedAadharPhoto = null;
    _removeAadharPhoto = false;
  }

  void _applyLearningPayload(LearningCenterPayload payload) {
    _learningSummary = payload.summary;
    _lessons = payload.lessons;
  }

  void _syncPendingCallStatusFromSummary() {
    if (_summary.pendingCallStatusRequired && _summary.pendingCallId.isNotEmpty) {
      _pendingStatusCallId = _summary.pendingCallId;
      _pendingStatusLeadId = _summary.pendingCallLeadId;
      _pendingStatusLeadName = _summary.pendingCallLeadName;
      _pendingStatusLeadPhone = _summary.pendingCallLeadPhone;
      return;
    }
    _clearPendingCallStatus();
  }

  void _clearPendingCallStatus() {
    _pendingStatusCallId = null;
    _pendingStatusLeadId = null;
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

  Future<void> _retryPendingCustomerCall() async {
    final callId = _pendingStatusCallId;
    final leadPhone = _pendingStatusLeadPhone;
    if (callId == null || callId.isEmpty || leadPhone.isEmpty) {
      _schedulePendingCallStatusPrompt();
      return;
    }

    final canReadCallLog = await _ensureCallLogAccess();
    if (!canReadCallLog) {
      return;
    }

    if (!_summary.workingNow) {
      await _startWork();
      if (!_summary.workingNow) {
        return;
      }
    }

    final dialStartedAt = DateTime.now();
    try {
      final call = await _apiClient.retryPendingCall(callId: callId);
      final launched = await FlutterPhoneDirectCaller.callNumber(leadPhone);
      if (launched != true) {
        await _apiClient.endCall(
          callId: call.id,
          durationSeconds: 0,
          endedAt: dialStartedAt,
          source: 'retry_direct_call_failed',
        );
        _showMessage('Unable to place the recent customer call.', isError: true);
        return;
      }

      _callTimer?.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeCallId = call.id;
        _activeCallLeadId = _pendingStatusLeadId;
        _pendingDialerCall = PendingDialerCall(
          callId: call.id,
          leadId: _pendingStatusLeadId ?? '',
          phone: leadPhone,
          startedAt: dialStartedAt,
        );
        _lastCallActivityAt = dialStartedAt;
        _elapsed = Duration.zero;
      });
      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError('Connection lost while retrying the recent customer.');
        return;
      }
      _showMessage(error.message, isError: true);
    }
  }

  Future<bool> _showPendingCallGuardPrompt(LeadItem? attemptedLead) async {
    if (!mounted || !_hasPendingCallStatus) {
      return true;
    }

    final attemptedLeadName = attemptedLead?.name ?? 'the next lead';
    final action = await showDialog<_PendingCallAction>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Previous Call Needs Action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Before calling $attemptedLeadName, finish the recent customer action below.',
              ),
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
                    const SizedBox(height: 8),
                    const Text(
                      'You can either call this recent customer again or mark the result now.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_PendingCallAction.cancel);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_PendingCallAction.markStatus);
              },
              child: const Text('Mark Status'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_PendingCallAction.callRecent);
              },
              child: const Text('Call Recent Customer'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _PendingCallAction.markStatus:
        await _showPendingCallStatusPrompt();
        return !_hasPendingCallStatus;
      case _PendingCallAction.callRecent:
        await _retryPendingCustomerCall();
        return false;
      case _PendingCallAction.cancel:
      case null:
        return false;
    }
  }

  Future<bool> _ensurePendingCallStatusResolved([LeadItem? attemptedLead]) async {
    if (!_hasPendingCallStatus) {
      return true;
    }
    return _showPendingCallGuardPrompt(attemptedLead);
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
          await _loadProfile(showLoader: false);
        }
      } else {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        if (_tab == 3 || _profile == null) {
          await _loadProfile(showLoader: false);
        }
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
            : (_lastLoadedTab > 3 ? 3 : _lastLoadedTab);
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
        await _loadProfile(showLoader: false);
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
        await _handleEntryPrompts();
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



  Future<void> _handleEntryPrompts() async {
    final update = await _checkForAvailableUpdate();
    if (!mounted) {
      return;
    }
    if (update != null) {
      await _showAppUpdatePrompt(update);
      if (!mounted || update.isMandatory) {
        return;
      }
    }
    _maybePromptMandatoryTraining();
  }

  Future<AppVersionInfo> _readCurrentVersionInfo() async {
    try {
      final payload = await _updaterChannel.invokeMapMethod<String, dynamic>(
            'getVersionInfo',
          ) ??
          const <String, dynamic>{};
      return AppVersionInfo.fromJson(Map<String, dynamic>.from(payload));
    } on MissingPluginException {
      return const AppVersionInfo(
        versionName: '',
        versionCode: 0,
        packageName: '',
        canInstallPackages: false,
      );
    } on PlatformException {
      return const AppVersionInfo(
        versionName: '',
        versionCode: 0,
        packageName: '',
        canInstallPackages: false,
      );
    }
  }

  Future<AppUpdateInfo?> _checkForAvailableUpdate({bool force = false}) async {
    if (_user == null) {
      return null;
    }
    if (_isCheckingForUpdate) {
      return _pendingAppUpdate;
    }
    if (_hasCheckedAppUpdate && !force) {
      return _pendingAppUpdate;
    }

    _isCheckingForUpdate = true;
    var success = false;
    try {
      final versionInfo = await _readCurrentVersionInfo();
      _currentVersionCode = versionInfo.versionCode;
      _currentVersionName = versionInfo.versionName;
      final update = await _apiClient.fetchAppUpdate(
        versionCode: versionInfo.versionCode,
      );
      success = true;
      if (mounted) {
        setState(() => _pendingAppUpdate = update);
      } else {
        _pendingAppUpdate = update;
      }
      return update;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
      } else if (error.code != 'network_error') {
        _showMessage('Could not check for app updates right now.', isError: true);
      }
      return _pendingAppUpdate;
    } finally {
      _isCheckingForUpdate = false;
      if (success) {
        _hasCheckedAppUpdate = true;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openAvailableAppUpdatePrompt() async {
    final update = _pendingAppUpdate ??
        await _checkForAvailableUpdate(force: true);
    if (update == null) {
      _showMessage('This device is already on the latest version.');
      return;
    }
    await _showAppUpdatePrompt(update);
  }

  Future<void> _showAppUpdatePrompt(AppUpdateInfo update) async {
    if (!mounted || _isUpdateDialogVisible) {
      return;
    }

    _isUpdateDialogVisible = true;
    final action = await showDialog<_AppUpdateAction>(
      context: context,
      barrierDismissible: !update.isMandatory,
      builder: (dialogContext) {
        return PopScope(
          canPop: !update.isMandatory,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              update.isMandatory ? 'Update Required' : 'App Update Available',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version ${update.versionName} is ready for HEAVENECTION.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      StatusPill(
                        label: update.isMandatory ? 'Mandatory' : 'Optional',
                      ),
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
                          update.fileSizeLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kPrimaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _currentVersionName.isEmpty
                        ? 'Current build: ${_currentVersionCode == 0 ? '--' : _currentVersionCode}'
                        : 'Current build: $_currentVersionName ($_currentVersionCode)',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'New build code: ${update.versionCode}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (update.minimumSupportedVersionCode > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Minimum supported build: ${update.minimumSupportedVersionCode}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Release notes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      update.releaseNotes.trim().isEmpty
                          ? 'A new HEAVENECTION update is ready to install.'
                          : update.releaseNotes,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    update.isMandatory
                        ? 'Download and install this update before continuing in the app.'
                        : 'Download the new APK now, or continue and install it later.',
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!update.isMandatory)
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(_AppUpdateAction.later);
                  },
                  child: const Text('Later'),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop(_AppUpdateAction.download);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download Update'),
              ),
            ],
          ),
        );
      },
    );
    _isUpdateDialogVisible = false;

    if (!mounted) {
      return;
    }

    if (action == _AppUpdateAction.download) {
      final started = await _downloadAppUpdate(update);
      if (!started && update.isMandatory) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showAppUpdatePrompt(update));
          }
        });
      }
    }
  }

  Future<bool> _downloadAppUpdate(AppUpdateInfo update) async {
    if (_isDownloadingUpdate) {
      return true;
    }

    _registerInteraction(syncServer: false);
    _isDownloadingUpdate = true;
    try {
      final response = await _updaterChannel.invokeMapMethod<String, dynamic>(
            'downloadAppUpdate',
            <String, dynamic>{
              'url': update.downloadUrl,
              'fileName': update.fileName,
              'title': 'HEAVENECTION ${update.versionName}',
              'description': 'Downloading the latest HEAVENECTION update.',
            },
          ) ??
          const <String, dynamic>{};
      final status = response['status']?.toString() ?? 'error';
      final message = response['message']?.toString() ??
          'Android will install the update after the download completes.';
      if (status == 'started') {
        _showMessage(message);
        return true;
      }
      _showMessage(message, isError: true);
      return false;
    } on MissingPluginException {
      _showMessage(
        'This device cannot start the in-app updater right now.',
        isError: true,
      );
      return false;
    } on PlatformException catch (error) {
      _showMessage(
        error.message ?? 'Could not start the update download.',
        isError: true,
      );
      return false;
    } finally {
      _isDownloadingUpdate = false;
    }
  }

  Future<void> _loadProfile({bool showLoader = true}) async {
    if (_isProfileLoading) {
      return;
    }

    if (showLoader && mounted) {
      setState(() => _isProfileLoading = true);
    } else {
      _isProfileLoading = true;
    }

    try {
      final profile = await _apiClient.fetchStaffProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _applyProfile(profile);
        _isNetworkErrorVisible = false;
      });
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to load the profile right now. Reconnect and try again.',
        );
        return;
      }
      _showMessage(error.message, isError: true);
    } finally {
      _isProfileLoading = false;
      if (mounted) {
        setState(() {});
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
      await _loadProfile(showLoader: false);
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
      _profile = null;
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
      _lastCallActivityAt = null;
      _backgroundedAt = null;
      _clearPendingCallStatus();
      _selectedAadharPhoto = null;
      _removeAadharPhoto = false;
      _pendingAppUpdate = null;
      _currentVersionCode = 0;
      _currentVersionName = '';
      _hasCheckedAppUpdate = false;
      _isDownloadingUpdate = false;
      _isUpdateDialogVisible = false;
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
      _profile = null;
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
      _lastCallActivityAt = null;
      _backgroundedAt = null;
      _clearPendingCallStatus();
      _selectedAadharPhoto = null;
      _removeAadharPhoto = false;
      _pendingAppUpdate = null;
      _currentVersionCode = 0;
      _currentVersionName = '';
      _hasCheckedAppUpdate = false;
      _isDownloadingUpdate = false;
      _isUpdateDialogVisible = false;
    });
    _updatePreferredOrientations();
  }

  Future<void> _pickAadharPhoto() async {
    _registerInteraction(syncServer: false);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null || !mounted) {
        return;
      }
      setState(() {
        _selectedAadharPhoto = File(image.path);
        _removeAadharPhoto = false;
      });
    } catch (_) {
      _showMessage('Could not open the photo picker.', isError: true);
    }
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (_isProfileSaving) {
      return;
    }
    if (_profileNameController.text.trim().isEmpty ||
        _profilePhoneController.text.trim().isEmpty) {
      _showMessage('Name and phone number are required.', isError: true);
      return;
    }
    if (_newPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text != _newPasswordController.text) {
      _showMessage('New password and confirm password must match.', isError: true);
      return;
    }
    if (_newPasswordController.text.isNotEmpty &&
        _currentPasswordController.text.isEmpty) {
      _showMessage(
        'Enter the current password before changing it.',
        isError: true,
      );
      return;
    }

    setState(() => _isProfileSaving = true);
    try {
      final profile = await _apiClient.updateStaffProfile(
        name: _profileNameController.text.trim(),
        phone: _profilePhoneController.text.trim(),
        email: _profileEmailController.text.trim(),
        bankAccountName: _bankAccountNameController.text.trim(),
        bankName: _bankNameController.text.trim(),
        bankAccountNumber: _bankAccountNumberController.text.trim(),
        bankIfscCode: _bankIfscController.text.trim(),
        aadharNumber: _aadharNumberController.text.trim(),
        currentPassword: _currentPasswordController.text.trim().isEmpty
            ? null
            : _currentPasswordController.text,
        newPassword: _newPasswordController.text.trim().isEmpty
            ? null
            : _newPasswordController.text,
        aadharPhoto: _selectedAadharPhoto,
        removeAadharPhoto: _removeAadharPhoto,
      );
      if (!mounted) {
        return;
      }
      setState(() => _applyProfile(profile));
      _showMessage('Profile updated successfully.');
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to save the profile because the network is unavailable.',
        );
        return;
      }
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isProfileSaving = false);
      }
    }
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
        _lastCallActivityAt = DateTime.now();
        _backgroundedAt = null;
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
        status: 'no_answer',
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
      _lastCallActivityAt = dialStartedAt;
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
    final lead = _leads[_safeLeadIndex];
    if (!await _ensurePendingCallStatusResolved(lead)) {
      return;
    }
    if (!_summary.workingNow) {
      await _startWork();
      if (!_summary.workingNow) {
        return;
      }
    }
    if (_activeCallId != null) {
      _showMessage(
        'Finish the current call before starting another.',
        isError: true,
      );
      return;
    }
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

  Future<ShortCallDecision?> _askShortCallDecision(int durationSeconds) async {
    if (!mounted) {
      return null;
    }

    final isNoResponse = durationSeconds <= 0;
    final title = isNoResponse ? 'No Response?' : 'Short Call Warning';
    final message = isNoResponse
        ? 'The customer did not attend the call. Call again, or mark it as No Response or Rejected.'
        : 'This call lasted less than 10 seconds. Call the customer again, or if the outcome is confirmed, mark No Response or Rejected.';

    return showDialog<ShortCallDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(ShortCallDecision.markNoResponse);
              },
              child: const Text('Mark No Response'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(ShortCallDecision.markRejected);
              },
              child: const Text('Mark Rejected'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(ShortCallDecision.callAgain);
              },
              child: const Text('Call Again'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _completeShortCallDecision(
    PendingDialerCall pendingCall,
    DateTime endedAt, {
    required int durationSeconds,
    required ShortCallDecision decision,
  }) async {
    final status = switch (decision) {
      ShortCallDecision.markRejected => 'not_interested',
      _ => 'no_answer',
    };
    final call = await _apiClient.endCall(
      callId: pendingCall.callId,
      status: status,
      durationSeconds: durationSeconds,
      endedAt: endedAt,
      source: decision == ShortCallDecision.callAgain
          ? 'call_log_short_recall'
          : 'call_log_short_resolution',
    );

    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    setState(() {
      _callStatus = decision == ShortCallDecision.markRejected
          ? 'Rejected'
          : 'No Response';
    });
    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (decision == ShortCallDecision.callAgain) {
      _showMessage('Short call detected. Marked as No Response and calling again.');
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
      _showMessage('Call marked as No Response.');
    } else if (call.status == 'not_interested') {
      _showMessage('Call marked as Rejected.');
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

    if (durationSeconds < kShortCallReviewThreshold.inSeconds) {
      final decision = await _askShortCallDecision(durationSeconds);
      if (decision == null) {
        return;
      }
      await _completeShortCallDecision(
        pendingCall,
        endedAt,
        durationSeconds: durationSeconds,
        decision: decision,
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
      _lastCallActivityAt = endedAt;
      if (call.status == 'started') {
        _pendingStatusCallId = call.id;
        _pendingStatusLeadId = pendingCall.leadId;
        _pendingStatusLeadName = lead?.name ?? '';
        _pendingStatusLeadPhone = lead?.phone ?? pendingCall.phone;
        _callStatus = 'Follow Up';
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
      _lastCallActivityAt = DateTime.now();
      if (call.status == 'started') {
        _pendingStatusCallId = call.id;
        _pendingStatusLeadId = leadId;
        _pendingStatusLeadName = lead?.name ?? '';
        _pendingStatusLeadPhone = lead?.phone ?? '';
        _callStatus = 'Follow Up';
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
    if (_pendingDialerCall != null) {
      await _syncCallFromLog(
        allowManualFallback: false,
        showMissingMessage: false,
      );
    }

    if (!_summary.workingNow) {
      return;
    }

    if (_summary.currentState == 'offline' && !_hasActiveCustomerCall) {
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >=
              kBackgroundSessionTimeout) {
        _showMessage(
          'Marked offline after 5 minutes away from the app. Start calling to return online.',
          isError: true,
        );
      }
      return;
    }

    _lastInteractionAt = DateTime.now();
    await _sendHeartbeat('foreground', interaction: true, source: 'lifecycle');
  }

  void _evaluateIdleState() {
    if (!mounted ||
        !_summary.workingNow ||
        _isBackgroundState(_lifecycleState) ||
        _hasActiveCustomerCall) {
      return;
    }

    final now = DateTime.now();
    if (_summary.currentState == 'offline') {
      return;
    }

    final lastInteractionAt = _lastInteractionAt ?? now;
    final lastCallActivityAt = _lastCallActivityAt ?? lastInteractionAt;
    if (now.difference(lastCallActivityAt) >= kIdleWarningAfter) {
      unawaited(_markOfflineFromInactivity());
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
    await _sendHeartbeat('warning', source: 'idle_warning');
    if (!mounted || !_summary.workingNow) {
      _isIdleWarningVisible = false;
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
                  await _endWork();
                },
                child: const Text('End Work'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  _isIdleWarningVisible = false;
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
      _showMessage(
        'Marked offline due to no call activity. Start calling to go back online.',
        isError: true,
      );
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

  Future<bool> _submitPendingCallStatus(
    String label, {
    String callbackWindow = '',
    String callbackWindowLabel = '',
  }) async {
    final callId = _pendingStatusCallId;
    if (callId == null || callId.isEmpty) {
      return true;
    }

    try {
      await _apiClient.updateCallStatus(
        callId: callId,
        status: _statusValue(label),
        callbackWindow: callbackWindow,
      );
      if (!mounted) {
        return true;
      }

      setState(() {
        _callStatus = label;
        _lastCallActivityAt = DateTime.now();
        _clearPendingCallStatus();
      });
      await _loadDashboardData(showLoader: false, promptTrainingGate: true);
      if (mounted) {
        if (label == 'Call Back' && callbackWindowLabel.isNotEmpty) {
          _showMessage('Call Back scheduled for $callbackWindowLabel.');
        } else {
          _showMessage('Call result saved as $label.');
        }
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
      'Rejected',
      'Follow Up',
      'Call Back',
      'No Response',
    ];
    const callbackChoices = ['Noon', 'Evening', 'Night'];

    _isCallStatusPromptVisible = true;
    var selectedStatus = choices.contains(_callStatus) ? _callStatus : 'Follow Up';
    var selectedCallbackWindow = '';

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
                                      setDialogState(() {
                                        selectedStatus = item;
                                        if (item != 'Call Back') {
                                          selectedCallbackWindow = '';
                                        }
                                      });
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
                    if (selectedStatus == 'Call Back') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Choose the callback time window',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: callbackChoices
                            .map(
                              (item) => ChoiceChip(
                                selected: selectedCallbackWindow == item,
                                onSelected: isSaving
                                    ? null
                                    : (_) {
                                        setDialogState(
                                          () => selectedCallbackWindow = item,
                                        );
                                      },
                                selectedColor: kPrimary,
                                backgroundColor: Colors.white,
                                label: Text(
                                  item,
                                  style: TextStyle(
                                    color: selectedCallbackWindow == item
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
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: isSaving ||
                            (selectedStatus == 'Call Back' &&
                                selectedCallbackWindow.isEmpty)
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            final saved = await _submitPendingCallStatus(
                              selectedStatus,
                              callbackWindow: _callbackWindowValue(
                                selectedCallbackWindow,
                              ),
                              callbackWindowLabel: selectedCallbackWindow,
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

  Future<void> _recoverPendingCallStatusPrompt() async {
    _registerInteraction(syncServer: false);
    _callStatusDialogContext = null;
    _isCallStatusPromptVisible = false;

    await _loadDashboardData(showLoader: false, promptTrainingGate: false);
    if (!mounted) {
      return;
    }
    if (!_hasPendingCallStatus) {
      _showMessage('There is no pending call result to mark right now.');
      return;
    }
    await _showPendingCallStatusPrompt();
  }

  Widget _buildPendingCallStatusBanner() {
    if (!_hasPendingCallStatus) {
      return const SizedBox.shrink();
    }

    final leadSummary = _pendingStatusLeadName.isNotEmpty
        ? _pendingStatusLeadName
        : (_pendingStatusLeadPhone.isNotEmpty
              ? _pendingStatusLeadPhone
              : 'recent customer');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kOrange.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_late, color: kOrange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Call Result Pending',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Finish the result for $leadSummary before moving on to the next customer.',
            style: const TextStyle(fontSize: 15.5, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _recoverPendingCallStatusPrompt,
            icon: const Icon(Icons.assignment_turned_in),
            label: const Text('Mark Call Result'),
          ),
        ],
      ),
    );
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
      'Follow Up' => 'interested',
      'Rejected' => 'not_interested',
      'No Response' => 'no_answer',
      'Call Back' => 'call_back',
      'Converted' => 'converted',
      _ => 'interested',
    };
  }

  String _callbackWindowValue(String label) {
    return switch (label) {
      'Noon' => 'noon',
      'Evening' => 'evening',
      'Night' => 'night',
      _ => '',
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
    final pages = [
      _dashboard(),
      _leadList(),
      _learningCenter(),
      _staffProfilePage(),
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _registerInteraction(syncServer: false),
      child: Scaffold(
        appBar: AppBar(
          title: const BrandWordmark(
            titleSize: 18,
            subtitle: 'CallTrack',
            subtitleSize: 11,
            markSize: 36,
          ),
          actions: [
            if (_pendingAppUpdate != null)
              IconButton(
                onPressed: _openAvailableAppUpdatePrompt,
                icon: const Icon(Icons.system_update_alt),
                tooltip: 'App update',
              ),
            if (_hasPendingCallStatus)
              IconButton(
                onPressed: _recoverPendingCallStatusPrompt,
                icon: const Icon(Icons.assignment_late),
              ),
            IconButton(
              onPressed: _isLoadingData
                  ? null
                  : () {
                      _registerInteraction(syncServer: false);
                      _loadDashboardData(promptTrainingGate: false);
                      if (_tab == 3) {
                        _loadProfile(showLoader: false);
                      }
                    },
              icon: _isLoadingData
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
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
            if (value == 3 && _profile == null) {
              unawaited(_loadProfile());
            }
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
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
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
          if (_hasPendingCallStatus) ...[
            _buildPendingCallStatusBanner(),
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
          if (_hasPendingCallStatus) ...[
            _buildPendingCallStatusBanner(),
            const SizedBox(height: 16),
          ],
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
                              if (_leads[i].callbackWindowLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Call Back: ${_leads[i].callbackWindowLabel}',
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      color: kPrimaryDark,
                                      fontWeight: FontWeight.w700,
                                    ),
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
    if (!await _ensurePendingCallStatusResolved(_leads[index])) {
      return;
    }
    if (!mounted) {
      return;
    }
    _registerInteraction(syncServer: false);
    setState(() {
      _leadIndex = index;
      _callStatus = 'Follow Up';
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
                if (lead.callbackWindowLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Call Back slot: ${lead.callbackWindowLabel}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: kPrimaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
                'After the call ends, the app will ask you to mark the result and schedule any callback slot. The next lead stays blocked until that result is saved.',
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

  Widget _staffProfilePage() {
    final profile = _profile;
    final salarySummary = profile?.salarySummary;
    final salaryHistory = profile?.salaryHistory ?? const <SalaryHistoryItem>[];
    final imageWidget = _selectedAadharPhoto != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.file(
              _selectedAadharPhoto!,
              width: double.infinity,
              height: 190,
              fit: BoxFit.cover,
            ),
          )
        : (_removeAadharPhoto || profile == null || !profile.hasAadharPhoto)
        ? Container(
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              color: kSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.badge_outlined, size: 42, color: kPrimaryDark),
                SizedBox(height: 10),
                Text(
                  'No Aadhaar photo added',
                  style: TextStyle(
                    fontSize: 15.5,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              profile.aadharPhotoUrl,
              width: double.infinity,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: double.infinity,
                  height: 190,
                  decoration: BoxDecoration(
                    color: kSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'Could not load the saved Aadhaar photo.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              },
            ),
          );

    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadProfile();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            profile == null
                ? 'Keep your account, banking, and identity details up to date.'
                : 'Signed in as ${profile.name}. Update personal and payout details here.',
            style: const TextStyle(fontSize: 16.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          if (_isProfileLoading && profile == null)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(child: CircularProgressIndicator()),
            )
          else ...[
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
                          title: 'Role',
                          value: profile?.roleLabel.isNotEmpty == true
                              ? profile!.roleLabel
                              : 'Staff',
                          color: kPrimary,
                          icon: Icons.badge,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InfoCard(
                          title: 'Status',
                          value: profile?.isActive == true ? 'Active' : 'Inactive',
                          color: profile?.isActive == true ? kGreen : kRed,
                          icon: Icons.verified_user,
                        ),
                      ),
                    ],
                  ),
                  if (profile?.lastSeenAt != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'Last seen: ${_formatProfileDate(profile!.lastSeenAt!)}',
                        style: const TextStyle(
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Salary overview',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Track total worked hours, earned salary, paid salary, and the latest transaction details.',
                    style: TextStyle(fontSize: 14.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 150,
                        child: InfoCard(
                          title: 'Hours',
                          value: salarySummary?.totalWorkingHoursLabel ?? '0.0h',
                          color: kPrimary,
                          icon: Icons.timer_outlined,
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: InfoCard(
                          title: 'Earned',
                          value: salarySummary?.totalEarnedAmountLabel ?? 'Rs. 0.00',
                          color: kGreen,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: InfoCard(
                          title: 'Paid',
                          value: salarySummary?.totalPaidAmountLabel ?? 'Rs. 0.00',
                          color: kOrange,
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    ],
                  ),
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
                        const Text(
                          'Latest transaction ID',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          salarySummary?.latestTransactionId.isNotEmpty == true
                              ? salarySummary!.latestTransactionId
                              : 'Transaction ID not added yet',
                          style: const TextStyle(
                            color: kPrimaryDark,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Last payment: ${salarySummary?.latestPaidAtLabel ?? '--'}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
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
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _profileNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _profilePhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _profileEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
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
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bank details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bankAccountNameController,
                    decoration: const InputDecoration(
                      labelText: 'Account Holder Name',
                      prefixIcon: Icon(Icons.account_circle_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bank Name',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankAccountNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Account Number',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankIfscController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'IFSC Code',
                      prefixIcon: Icon(Icons.approval_outlined),
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
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aadhaar details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _aadharNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Aadhaar Number',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  imageWidget,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickAadharPhoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose Photo'),
                      ),
                      if (_selectedAadharPhoto != null ||
                          (profile?.hasAadharPhoto == true && !_removeAadharPhoto))
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedAadharPhoto = null;
                              _removeAadharPhoto = true;
                            });
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove Photo'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change password',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: Icon(Icons.verified_outlined),
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
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Salary history',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Credited salary records will appear here after the admin marks them as paid.',
                    style: TextStyle(fontSize: 14.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  if (salaryHistory.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'No salary credits have been added yet.',
                        style: TextStyle(
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final salary in salaryHistory) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        salary.paidAmountLabel.isNotEmpty
                                            ? salary.paidAmountLabel
                                            : 'Rs. 0.00',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: kPrimaryDark,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        salary.payoutCycleLabel,
                                        style: const TextStyle(
                                          color: kPrimaryDark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  salary.periodLabel.isNotEmpty
                                      ? salary.periodLabel
                                      : 'Salary period',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Paid on ${salary.paidAtLabel} • ${salary.paymentMethodLabel}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Worked ${salary.totalHoursLabel} • Earned ${salary.finalSalaryLabel}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Paid amount: ${salary.paidAmountLabel}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (salary.paymentReference.isNotEmpty &&
                                    salary.paymentReference != '--') ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Transaction ID: ${salary.paymentReference}',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (salary.paymentNote.isNotEmpty &&
                                    salary.paymentNote != '--') ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    salary.paymentNote,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _isProfileSaving ? null : _saveProfile,
              icon: _isProfileSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isProfileSaving ? 'Saving...' : 'Save Profile'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              style: OutlinedButton.styleFrom(foregroundColor: kRed),
              label: const Text('Logout'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatProfileDate(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    final months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}, $hour:$minute $period';
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
  YoutubePlayerController? _youtubeController;
  bool _canComplete = false;
  bool _isCompleting = false;
  bool _hasOpenedFallbackVideo = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _canComplete = widget.lesson.isCompleted || !widget.lesson.hasVideo;
    if (widget.lesson.hasVideo) {
      if (widget.lesson.isYouTubeVideo) {
        _initialiseYoutubeVideo();
      } else {
        _initialiseVideo();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_youtubeController?.close() ?? Future<void>.value());
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

  void _initialiseYoutubeVideo() {
    final videoId = widget.lesson.youtubeVideoId;
    if (videoId.isEmpty) {
      setState(() {
        _videoError =
            'This YouTube link could not be read. Check the lesson URL and try again.';
        _canComplete = true;
      });
      return;
    }

    final controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );

    controller.listen((value) {
      if (!mounted) {
        return;
      }
      if (value.hasError) {
        setState(() {
          _videoError = _youtubeErrorMessage(value.error);
          _canComplete = _hasOpenedFallbackVideo;
        });
        return;
      }
      if (_canComplete) {
        return;
      }
      if (value.playerState == PlayerState.ended) {
        setState(() => _canComplete = true);
      }
    });

    _youtubeController = controller;
  }

  String _youtubeErrorMessage(YoutubeError error) {
    switch (error) {
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
        return 'This shared YouTube video cannot play inside the app player. Open it in YouTube to continue the lesson.';
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
        return 'This YouTube video is no longer available. Check the lesson link in the admin panel.';
      case YoutubeError.html5Error:
        return 'This YouTube video could not start in the in-app player. Open it in YouTube and return after watching.';
      case YoutubeError.invalidParam:
        return 'This YouTube link is not in a valid format. Update the lesson link in the admin panel.';
      case YoutubeError.none:
        return '';
      case YoutubeError.unknown:
        return 'This YouTube video could not be played inside the app. Open it in YouTube to continue the lesson.';
    }
  }

  Uri? get _externalLessonUri {
    final raw = widget.lesson.videoUrl.trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    final videoId = widget.lesson.youtubeVideoId;
    if (videoId.isEmpty) {
      return null;
    }
    return Uri.parse('https://www.youtube.com/watch?v=$videoId');
  }

  Future<void> _openLessonExternally() async {
    final uri = _externalLessonUri;
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This lesson link is not valid yet.'),
        ),
      );
      return;
    }

    final didLaunch = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!mounted) {
      return;
    }

    if (!didLaunch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the lesson video right now.'),
        ),
      );
      return;
    }

    setState(() {
      _hasOpenedFallbackVideo = true;
      if (_videoError != null) {
        _canComplete = true;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'The lesson opened in YouTube. Return here after watching to complete the training.',
        ),
      ),
    );
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
    final videoWidget = !widget.lesson.hasVideo
        ? const _TrainingVideoError(
            message:
                'No video is attached to this lesson. Review the lesson notes and complete it when finished.',
          )
        : widget.lesson.isYouTubeVideo
        ? _buildYoutubeVideoWidget()
        : FutureBuilder<void>(
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
                if (widget.lesson.isYouTubeVideo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'YouTube Video',
                      style: TextStyle(
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
                    Text(
                      widget.lesson.isYouTubeVideo
                          ? 'Watch the YouTube lesson until the end to unlock completion.'
                          : 'Watch the lesson until the end to unlock completion.',
                      style: const TextStyle(
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

  Widget _buildYoutubeVideoWidget() {
    final controller = _youtubeController;
    if (_videoError != null) {
      return _TrainingVideoError(
        message: _videoError!,
        primaryActionLabel: 'Open in YouTube',
        onPrimaryAction: _openLessonExternally,
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: YoutubePlayer(
            controller: controller,
            aspectRatio: 16 / 9,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _openLessonExternally,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in YouTube'),
          ),
        ),
      ],
    );
  }
}

class _TrainingVideoError extends StatelessWidget {
  const _TrainingVideoError({
    required this.message,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final String message;
  final String? primaryActionLabel;
  final Future<void> Function()? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 15.5, color: Colors.black54),
          ),
          if (primaryActionLabel != null && onPrimaryAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onPrimaryAction,
              icon: const Icon(Icons.open_in_new),
              label: Text(primaryActionLabel!),
            ),
          ],
        ],
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

enum ShortCallDecision { markNoResponse, markRejected, callAgain }

enum _PendingCallAction { markStatus, callRecent, cancel }

enum _AppUpdateAction { download, later }

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
      'Follow Up' => kGreen,
      'Call Back' => kOrange,
      'No Response' => kRed,
      'Converted' => kGreen,
      'Rejected' => kRed,
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
