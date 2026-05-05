import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'api_client.dart';
import 'app_models.dart';

const String kBrandName = 'HEAVENECTION';
const List<String> kMalayalamFontFallback = [
  'Noto Sans Malayalam',
  'Noto Sans Malayalam UI',
  'Noto Sans',
  'Nirmala UI',
  'Roboto',
];
const TextStyle kMalayalamFallbackStyle = TextStyle(
  fontFamilyFallback: kMalayalamFontFallback,
);
const String kLegacyApiBaseUrl =
    'https://heavenection-production.up.railway.app';
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.heavenection.com',
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
const Duration kShortCallReviewThreshold = Duration(seconds: 15);
const Duration kMinimumQualifyingCallDuration = Duration(seconds: 5);
const int kCallLogSyncAttempts = 15;
const Duration kCallLogSyncRetryDelay = Duration(seconds: 2);
const Duration kCallLogMatchLookback = Duration(minutes: 5);
const Duration kCallLogMatchLookahead = Duration(minutes: 2);
const Duration kNetworkErrorDelay = Duration(seconds: 3);
const Duration kActiveCallAutoCheckInterval = Duration(seconds: 3);
const Duration kSyncSolveCountdownTick = Duration(seconds: 1);

String _formatCallbackDateLabel(DateTime value) {
  const months = [
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
  return '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]} ${value.year}';
}

String _formatCallbackScheduleLabel(String dateLabel, String windowLabel) {
  final parts = <String>[
    if (dateLabel.trim().isNotEmpty) dateLabel.trim(),
    if (windowLabel.trim().isNotEmpty) windowLabel.trim(),
  ];
  return parts.join(' • ');
}

void main() => runApp(const HeavenectionApp());

class HeavenectionApp extends StatelessWidget {
  const HeavenectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.light().textTheme;
    final malayalamTextTheme = GoogleFonts.notoSansMalayalamTextTheme(
      baseTextTheme,
    );

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
        textTheme: malayalamTextTheme,
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
  final ApiClient _apiClient = ApiClient(
    baseUrl: kApiBaseUrl,
    fallbackBaseUrls: const [kLegacyApiBaseUrl],
  );
  static const MethodChannel _updaterChannel = MethodChannel(
    'heavenection/updater',
  );

  StaffUser? _user;
  StaffProfile? _profile;
  DailySummary _summary = DailySummary.empty();
  LearningSummary _learningSummary = LearningSummary.empty();
  List<LeadItem> _leads = const [];
  List<LeadItem> _followups = const [];
  List<TrainingLesson> _lessons = const [];

  bool _isBootstrapping = true;
  bool _isLoggingIn = false;
  bool _isLoadingData = false;
  bool _isFollowupsLoading = false;
  bool _isProfileLoading = false;
  bool _isProfileSaving = false;
  bool _isSessionBusy = false;
  bool _isTrainingPromptVisible = false;
  bool _isNetworkErrorVisible = false;
  bool _isRecoveringFromNetworkError = false;
  int _tab = 0;
  int _lastLoadedTab = 0;
  int _leadIndex = 0;
  String _callStatus = 'Interested';
  String _learningQuery = '';
  String? _loginErrorText;
  String _networkErrorMessage = 'Connection interrupted.';
  String? _activeCallId;
  String? _activeCallLeadId;
  bool _activeCallFromFollowup = false;
  PendingDialerCall? _pendingDialerCall;
  String? _pendingStatusCallId;
  String? _pendingStatusLeadId;
  String _pendingStatusLeadName = '';
  String _pendingStatusLeadPhone = '';
  bool _pendingStatusFromFollowup = false;
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
  bool _isCallScreenOpen = false;
  bool _isExitDialogVisible = false;
  Timer? _syncSolveCountdownTimer;
  int? _syncSolveCountdownSeconds;
  bool _isCheckingForUpdate = false;
  bool _isUpdateDialogVisible = false;
  bool _isDownloadingUpdate = false;
  bool _hasCheckedAppUpdate = false;
  bool _hasConnection = true;
  bool _isLoginPasswordVisible = false;
  Timer? _networkErrorTimer;
  DateTime? _lastActiveCallAutoCheckAt;
  String? _pendingNetworkErrorMessage;
  AppUpdateInfo? _pendingAppUpdate;
  File? _selectedAadharPhoto;
  File? _selectedPassbookPhoto;
  bool _removeAadharPhoto = false;
  bool _removePassbookPhoto = false;
  Map<String, dynamic> _requiredPermissionStatus = const <String, dynamic>{};
  bool? _requiredPermissionsGranted;
  bool _isRefreshingRequiredPermissions = false;
  bool _isRequiredPermissionDialogVisible = false;

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
    _syncSolveCountdownTimer?.cancel();
    _networkErrorTimer?.cancel();
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

    if (state == AppLifecycleState.resumed) {
      if (_pendingNetworkErrorMessage != null && !_hasConnection) {
        _scheduleNetworkError(_pendingNetworkErrorMessage!);
      }
      unawaited(_handleResumeState());
    } else if (_isBackgroundState(state)) {
      if (!_summary.workingNow) {
        return;
      }
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

  bool get _hasRecoverableCustomerCall =>
      !_hasPendingCallStatus &&
      _summary.recoverableCallRequired &&
      _summary.recoverableCallId.isNotEmpty;

  bool get _hasActiveCustomerCall =>
      _activeCallId != null && _pendingDialerCall != null;

  bool get _needsRequiredPermissionGate =>
      _user != null && _requiredPermissionsGranted == false;

  bool get _isResolvingRequiredPermissions =>
      _user != null &&
      (_requiredPermissionsGranted == null || _isRefreshingRequiredPermissions);

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
    _selectedPassbookPhoto = null;
    _removeAadharPhoto = false;
    _removePassbookPhoto = false;
  }

  void _applyLearningPayload(LearningCenterPayload payload) {
    _learningSummary = payload.summary;
    _lessons = payload.lessons;
  }

  void _syncPendingCallStatusFromSummary() {
    if (_summary.pendingCallStatusRequired &&
        _summary.pendingCallId.isNotEmpty) {
      _pendingStatusCallId = _summary.pendingCallId;
      _pendingStatusLeadId = _summary.pendingCallLeadId;
      _pendingStatusLeadName = _summary.pendingCallLeadName;
      _pendingStatusLeadPhone = _summary.pendingCallLeadPhone;
      return;
    }
    _clearPendingCallStatus();
  }

  void _applySummarySnapshot(
    DailySummary summary, {
    bool updateBlockedCallTab = true,
  }) {
    _summary = summary;
    _syncPendingCallStatusFromSummary();
    if (_summary.pendingCallStatusRequired) {
      _resetActiveCallTracking();
    } else if (_summary.recoverableCallRequired) {
      _syncRecoverableCallFromSummary();
    } else {
      _resetActiveCallTracking();
    }
    if (updateBlockedCallTab &&
        (_summary.pendingCallStatusRequired ||
            _summary.recoverableCallRequired)) {
      _tab = 1;
      _lastLoadedTab = 1;
    }
  }

  void _clearPendingCallStatus() {
    _pendingStatusCallId = null;
    _pendingStatusLeadId = null;
    _pendingStatusLeadName = '';
    _pendingStatusLeadPhone = '';
    _pendingStatusFromFollowup = false;
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

  void _ensureActiveCallTimerRunning() {
    if (_callTimer != null) {
      return;
    }
    _lastActiveCallAutoCheckAt = null;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_hasActiveCustomerCall) {
        _callTimer?.cancel();
        _callTimer = null;
        _lastActiveCallAutoCheckAt = null;
        return;
      }
      setState(() => _elapsed += const Duration(seconds: 1));
      final now = DateTime.now();
      final shouldAutoCheck =
          _lifecycleState == AppLifecycleState.resumed &&
          !_isSyncingCallLog &&
          (_lastActiveCallAutoCheckAt == null ||
              now.difference(_lastActiveCallAutoCheckAt!) >=
                  kActiveCallAutoCheckInterval);
      if (!shouldAutoCheck) {
        return;
      }
      _lastActiveCallAutoCheckAt = now;
      unawaited(_maybeAutoSyncEndedCall(showMissingMessage: false));
    });
  }

  void _setCallLogSyncing(bool value) {
    if (_isSyncingCallLog == value) {
      return;
    }
    if (value) {
      _startSyncSolveCountdown();
    } else {
      _stopSyncSolveCountdown();
    }
    if (!mounted) {
      _isSyncingCallLog = value;
      return;
    }
    setState(() => _isSyncingCallLog = value);
  }

  void _startSyncSolveCountdown() {
    final totalSeconds =
        kCallLogSyncAttempts * kCallLogSyncRetryDelay.inSeconds;
    _syncSolveCountdownTimer?.cancel();
    _syncSolveCountdownSeconds = totalSeconds;
    _syncSolveCountdownTimer = Timer.periodic(kSyncSolveCountdownTick, (_) {
      final remaining = _syncSolveCountdownSeconds;
      if (remaining == null || remaining <= 0) {
        _syncSolveCountdownTimer?.cancel();
        _syncSolveCountdownTimer = null;
        return;
      }
      final next = remaining - 1;
      if (!mounted) {
        _syncSolveCountdownSeconds = next;
        return;
      }
      setState(() {
        _syncSolveCountdownSeconds = next;
      });
    });
  }

  void _stopSyncSolveCountdown() {
    _syncSolveCountdownTimer?.cancel();
    _syncSolveCountdownTimer = null;
    _syncSolveCountdownSeconds = null;
  }

  String _formatSecondsAsTimer(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final seconds = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _openPendingCustomerPage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _tab = 1;
      _lastLoadedTab = 1;
    });
  }

  void _syncRecoverableCallFromSummary() {
    if (_summary.pendingCallStatusRequired ||
        !_summary.recoverableCallRequired ||
        _summary.recoverableCallId.isEmpty) {
      return;
    }

    final startedAt = _summary.recoverableCallStartedAt ?? DateTime.now();
    final hasSameCall =
        _pendingDialerCall?.callId == _summary.recoverableCallId;
    _activeCallId = _summary.recoverableCallId;
    _activeCallLeadId = _summary.recoverableCallLeadId;
    _pendingDialerCall = PendingDialerCall(
      callId: _summary.recoverableCallId,
      leadId: _summary.recoverableCallLeadId,
      phone: _summary.recoverableCallLeadPhone,
      startedAt: startedAt,
    );
    _lastCallActivityAt = startedAt;
    if (!hasSameCall) {
      final elapsed = DateTime.now().difference(startedAt);
      _elapsed = elapsed.isNegative ? Duration.zero : elapsed;
    }
    _ensureActiveCallTimerRunning();
  }

  Future<void> _focusLeadWorkflowAfterCallResultSaved() async {
    if (!mounted) {
      return;
    }
    _openPendingCustomerPage();
    if (_isCallScreenOpen) {
      try {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      } catch (_) {
        // Ignore navigation state races while the route tree settles.
      }
    }
  }

  Future<void> _showCallScreenForLead(
    LeadItem lead, {
    int? index,
    bool fromFollowup = false,
  }) async {
    if (!mounted) {
      return;
    }

    final isFollowupLead = fromFollowup || _isFollowupLeadItem(lead);
    _registerInteraction(syncServer: false);
    setState(() {
      if (index != null) {
        _leadIndex = index;
      } else {
        final resolvedIndex = _leads.indexWhere((item) => item.id == lead.id);
        if (resolvedIndex >= 0) {
          _leadIndex = resolvedIndex;
        }
      }
      _callStatus = isFollowupLead ? 'Follow Up' : 'Interested';
    });

    if (_isCallScreenOpen) {
      return;
    }

    _isCallScreenOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Call')),
            body: SafeArea(child: _call(lead)),
          ),
        ),
      );
    } finally {
      _isCallScreenOpen = false;
    }
  }

  Future<void> _openCurrentCallScreen({String? notice}) async {
    if (_hasPendingCallStatus) {
      _openPendingCustomerPage();
      await _recoverPendingCallStatusPrompt();
      return;
    }

    if (_hasRecoverableCustomerCall && _pendingDialerCall != null) {
      if (notice != null && notice.isNotEmpty) {
        _showMessage(notice, isError: true);
      }
      final didResolve = await _waitForCallEndThenSync(
        allowManualFallback: true,
        showMissingMessage: true,
      );
      if (didResolve ||
          !mounted ||
          _hasPendingCallStatus ||
          !_hasRecoverableCustomerCall) {
        return;
      }
    }

    final activeLeadId = _activeCallLeadId ?? _pendingDialerCall?.leadId;
    final activeLead = _leadById(activeLeadId);
    if (activeLead == null) {
      if (_hasRecoverableCustomerCall ||
          (_pendingDialerCall != null &&
              (_pendingDialerCall?.leadId ?? '').isNotEmpty)) {
        final fallbackLeadId = activeLeadId ?? _summary.recoverableCallLeadId;
        final fallbackLeadName = _summary.recoverableCallLeadName.isNotEmpty
            ? _summary.recoverableCallLeadName
            : (_summary.recoverableCallLeadPhone.isNotEmpty
                  ? _summary.recoverableCallLeadPhone
                  : 'Recent customer');
        final fallbackLeadPhone = _summary.recoverableCallLeadPhone.isNotEmpty
            ? _summary.recoverableCallLeadPhone
            : (_pendingDialerCall?.phone ?? _pendingStatusLeadPhone);

        if (fallbackLeadId.isNotEmpty) {
          final placeholderLead = LeadItem(
            id: fallbackLeadId,
            name: fallbackLeadName,
            phone: fallbackLeadPhone,
            status: 'new',
            statusLabel: 'New',
            callbackWindow: '',
            callbackWindowLabel: '',
            callbackDate: null,
            callbackDateLabel: '',
            callbackScheduleLabel: '',
            notes: '',
          );
          await _showCallScreenForLead(
            placeholderLead,
            fromFollowup:
                _activeCallFromFollowup || _isFollowupLeadItem(placeholderLead),
          );
          return;
        }
      }

      if (notice != null && notice.isNotEmpty) {
        _showMessage(notice, isError: true);
      } else {
        _showMessage(
          'Finish the current customer call before moving to another lead.',
          isError: true,
        );
      }
      return;
    }

    if (notice != null && notice.isNotEmpty) {
      _showMessage(notice, isError: true);
    }
    await _showCallScreenForLead(
      activeLead,
      fromFollowup: _activeCallFromFollowup || _isFollowupLeadItem(activeLead),
    );
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
    final canReadPhoneState = await _ensurePhoneStateAccess();
    if (!canReadPhoneState) {
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
        _showMessage(
          'Unable to place the recent customer call.',
          isError: true,
        );
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
      _ensureActiveCallTimerRunning();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while retrying the recent customer.',
        );
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

  Future<bool> _ensurePendingCallStatusResolved([
    LeadItem? attemptedLead,
  ]) async {
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

  void _markRequiredPermissionsPending() {
    _requiredPermissionsGranted = null;
    _isRefreshingRequiredPermissions = true;
  }

  void _applyRequiredPermissionStatus(Map<String, dynamic> status) {
    final allGranted = status['allGranted'] == true;
    if (!mounted) {
      _requiredPermissionStatus = status;
      _requiredPermissionsGranted = allGranted;
      _isRefreshingRequiredPermissions = false;
      return;
    }
    setState(() {
      _requiredPermissionStatus = status;
      _requiredPermissionsGranted = allGranted;
      _isRefreshingRequiredPermissions = false;
    });
  }

  Future<Map<String, dynamic>> _readRequiredPermissionStatus() async {
    if (!Platform.isAndroid) {
      return const <String, dynamic>{
        'callPhoneGranted': false,
        'callLogGranted': false,
        'phoneStateGranted': false,
        'allGranted': false,
      };
    }

    try {
      return Map<String, dynamic>.from(
        await _updaterChannel.invokeMapMethod<String, dynamic>(
              'getRequiredPermissionStatus',
            ) ??
            const <String, dynamic>{},
      );
    } on MissingPluginException {
      return const <String, dynamic>{
        'callPhoneGranted': false,
        'callLogGranted': false,
        'phoneStateGranted': false,
        'allGranted': false,
      };
    } on PlatformException {
      return const <String, dynamic>{
        'callPhoneGranted': false,
        'callLogGranted': false,
        'phoneStateGranted': false,
        'allGranted': false,
      };
    }
  }

  Future<bool> _refreshRequiredPermissionState({
    bool showDialogIfMissing = false,
  }) async {
    if (_user == null) {
      _requiredPermissionStatus = const <String, dynamic>{};
      _requiredPermissionsGranted = null;
      _isRefreshingRequiredPermissions = false;
      return true;
    }

    if (mounted) {
      setState(() => _isRefreshingRequiredPermissions = true);
    } else {
      _isRefreshingRequiredPermissions = true;
    }

    final status = await _readRequiredPermissionStatus();
    _applyRequiredPermissionStatus(status);
    final allGranted = status['allGranted'] == true;
    if (allGranted) {
      _handlePermissionReadyPrompts();
    } else if (showDialogIfMissing) {
      _scheduleRequiredPermissionDialog();
    }
    return allGranted;
  }

  Future<bool> _requestRequiredPermissions({
    bool showMissingMessage = true,
  }) async {
    if (!Platform.isAndroid) {
      if (showMissingMessage) {
        _showMessage(
          'This app needs Android phone permissions to work correctly.',
          isError: true,
        );
      }
      return false;
    }

    try {
      final status = Map<String, dynamic>.from(
        await _updaterChannel.invokeMapMethod<String, dynamic>(
              'requestRequiredPermissions',
            ) ??
            const <String, dynamic>{},
      );
      _applyRequiredPermissionStatus(status);
      final allGranted = status['allGranted'] == true;
      if (allGranted) {
        _handlePermissionReadyPrompts();
      } else if (showMissingMessage) {
        _showMessage(
          'Allow all required Android permissions to continue working in the app.',
          isError: true,
        );
      }
      return allGranted;
    } on MissingPluginException {
      if (showMissingMessage) {
        _showMessage(
          'This device cannot open the Android permission flow right now.',
          isError: true,
        );
      }
      return false;
    } on PlatformException catch (error) {
      if (showMissingMessage) {
        _showMessage(
          error.message ??
              'Could not open the Android permission flow right now.',
          isError: true,
        );
      }
      return false;
    }
  }

  Future<void> _openAppPermissionSettings() async {
    if (!Platform.isAndroid) {
      _showMessage(
        'This app needs Android phone permissions to work correctly.',
        isError: true,
      );
      return;
    }
    try {
      await _updaterChannel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      _showMessage(
        'Could not open Android app settings on this device.',
        isError: true,
      );
    } on PlatformException catch (error) {
      _showMessage(
        error.message ?? 'Could not open Android app settings right now.',
        isError: true,
      );
    }
  }

  Future<bool> _ensureRequiredPermissionsReady({
    bool requestIfMissing = false,
    bool showDialogIfMissing = false,
  }) async {
    final alreadyGranted = await _refreshRequiredPermissionState(
      showDialogIfMissing: showDialogIfMissing,
    );
    if (alreadyGranted) {
      return true;
    }
    if (!requestIfMissing) {
      return false;
    }

    final granted = await _requestRequiredPermissions();
    if (!granted && showDialogIfMissing) {
      _scheduleRequiredPermissionDialog();
    }
    return granted;
  }

  void _scheduleRequiredPermissionDialog() {
    if (!mounted ||
        _user == null ||
        _requiredPermissionsGranted != false ||
        _isRequiredPermissionDialogVisible ||
        _isNetworkErrorVisible) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _user == null ||
          _requiredPermissionsGranted != false ||
          _isRequiredPermissionDialogVisible ||
          _isNetworkErrorVisible) {
        return;
      }
      unawaited(_showRequiredPermissionDialog());
    });
  }

  void _handlePermissionReadyPrompts() {
    if (_summary.pendingCallStatusRequired) {
      _schedulePendingCallStatusPrompt();
      return;
    }
    if (_summary.currentState == 'warning' && !_isIdleWarningVisible) {
      unawaited(_showIdleWarning());
    }
    _maybePromptMandatoryTraining();
  }

  Future<void> _showRequiredPermissionDialog() async {
    if (!mounted ||
        _user == null ||
        _requiredPermissionsGranted != false ||
        _isRequiredPermissionDialogVisible) {
      return;
    }

    _isRequiredPermissionDialogVisible = true;
    final action = await showDialog<_PermissionDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('Allow Required Access'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'This app needs phone call access, call history access, and phone status access before staff can work.',
                ),
                SizedBox(height: 12),
                Text(
                  'Without these permissions, call tracking and work-hour calculation will not run correctly.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PermissionDialogAction.openSettings),
                child: const Text('Open Settings'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PermissionDialogAction.allowNow),
                child: const Text('Allow Now'),
              ),
            ],
          ),
        );
      },
    );
    _isRequiredPermissionDialogVisible = false;

    if (!mounted || _user == null) {
      return;
    }
    if (action == _PermissionDialogAction.allowNow) {
      await _requestRequiredPermissions();
    } else if (action == _PermissionDialogAction.openSettings) {
      await _openAppPermissionSettings();
    }
  }

  Widget _permissionRequirementRow({
    required IconData icon,
    required String title,
    required String description,
    required bool granted,
  }) {
    final accent = granted ? kGreen : kRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            granted ? Icons.check_circle_rounded : Icons.error_rounded,
            color: accent,
          ),
        ],
      ),
    );
  }

  Widget _requiredPermissionGatePage() {
    final callPhoneGranted =
        _requiredPermissionStatus['callPhoneGranted'] == true;
    final callLogGranted = _requiredPermissionStatus['callLogGranted'] == true;
    final phoneStateGranted =
        _requiredPermissionStatus['phoneStateGranted'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Allow Access')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimaryDark, kPrimary],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Required access is missing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Staff calling cannot continue until all required Android permissions are allowed.',
                    style: TextStyle(color: Colors.white70, fontSize: 15.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _permissionRequirementRow(
              icon: Icons.call_rounded,
              title: 'Phone Call Access',
              description:
                  'Needed to place the customer call directly from the app.',
              granted: callPhoneGranted,
            ),
            const SizedBox(height: 12),
            _permissionRequirementRow(
              icon: Icons.history_toggle_off_rounded,
              title: 'Call History Access',
              description:
                  'Needed to confirm the finished customer call from the phone record.',
              granted: callLogGranted,
            ),
            const SizedBox(height: 12),
            _permissionRequirementRow(
              icon: Icons.phone_in_talk_rounded,
              title: 'Phone Status Access',
              description:
                  'Needed to detect when a live customer call ends and open the correct remark flow.',
              granted: phoneStateGranted,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final granted = await _requestRequiredPermissions();
                  if (!granted) {
                    _scheduleRequiredPermissionDialog();
                  }
                },
                icon: const Icon(Icons.security_rounded),
                label: const Text('Allow Permissions'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openAppPermissionSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 12),
            const Text(
              'If you denied any permission earlier, open Android settings and allow every required access there.',
              style: TextStyle(color: Colors.black54, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  void _watchConnectivity() {
    final connectivity = Connectivity();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      _hasConnection = hasConnection;
      if (!hasConnection) {
        _scheduleNetworkError(
          'You are offline. Check mobile data or Wi-Fi and try again.',
        );
        return;
      }
      _pendingNetworkErrorMessage = null;
      _networkErrorTimer?.cancel();
      if (_isNetworkErrorVisible) {
        unawaited(_recoverFromNetworkError());
      }
    });
  }

  void _scheduleNetworkError(String message) {
    _pendingNetworkErrorMessage = message;
    _networkErrorTimer?.cancel();
    if (_lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _networkErrorTimer = Timer(kNetworkErrorDelay, () {
      if (!mounted || _hasConnection || _isNetworkErrorVisible) {
        return;
      }
      _showNetworkError(message);
    });
  }

  void _showNetworkError(String message) {
    if (!mounted) {
      return;
    }
    if (_lifecycleState != AppLifecycleState.resumed) {
      _pendingNetworkErrorMessage = message;
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
      _isRecoveringFromNetworkError = false;
      _lastLoadedTab = _tab;
    });
  }

  Future<void> _recoverFromNetworkError() async {
    if (_isRecoveringFromNetworkError) {
      return;
    }
    try {
      if (mounted) {
        setState(() => _isRecoveringFromNetworkError = true);
      }
      if (_user == null) {
        await _apiClient.loadStoredSession();
        final restoredUser = await _apiClient.restoreSession();
        if (restoredUser != null) {
          _user = restoredUser;
          _markRequiredPermissionsPending();
          _updatePreferredOrientations();
          await _loadDashboardData(showLoader: false, promptTrainingGate: true);
          await _maybeAutoSyncEndedCall(showMissingMessage: false);
          await _loadProfile(showLoader: false);
          await _refreshRequiredPermissionState(showDialogIfMissing: true);
        }
      } else {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        await _maybeAutoSyncEndedCall(showMissingMessage: false);
        if (_tab == 3 || _profile == null) {
          await _loadProfile(showLoader: false);
        }
        await _refreshRequiredPermissionState(showDialogIfMissing: true);
      }

      if (!mounted) {
        return;
      }
      if (_isNetworkErrorVisible) {
        return;
      }
      final preferredTab =
          (_summary.pendingCallStatusRequired ||
              _summary.recoverableCallRequired)
          ? 1
          : (_lastLoadedTab < 0
                ? 0
                : (_lastLoadedTab > 3 ? 3 : _lastLoadedTab));
      setState(() {
        _isNetworkErrorVisible = false;
        _isRecoveringFromNetworkError = false;
        _tab = preferredTab;
        _lastLoadedTab = preferredTab;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _isRecoveringFromNetworkError = false);
      }
      if (error.code != 'network_error') {
        _showMessage(error.message, isError: true);
      } else {
        _showNetworkError(
          'Still unable to reconnect. Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted &&
          _isRecoveringFromNetworkError &&
          !_isNetworkErrorVisible) {
        setState(() => _isRecoveringFromNetworkError = false);
      }
    }
  }

  Future<void> _runDeferredStartupWarmup({
    bool promptTrainingGate = true,
  }) async {
    if (_user == null) {
      return;
    }

    await _refreshRequiredPermissionState(showDialogIfMissing: true);
    if (_user == null) {
      return;
    }

    await _maybeAutoSyncEndedCall(showMissingMessage: false);
    if (_user == null) {
      return;
    }

    if (_profile == null || _tab == 3) {
      await _loadProfile(showLoader: false);
    }

    if (_user == null || !promptTrainingGate) {
      return;
    }

    if (_requiredPermissionsGranted == true) {
      await _handleEntryPrompts();
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _apiClient.loadStoredSession();
      final restoredUser = await _apiClient.restoreSession();
      if (restoredUser != null) {
        _user = restoredUser;
        _markRequiredPermissionsPending();
        _updatePreferredOrientations();
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        unawaited(_runDeferredStartupWarmup(promptTrainingGate: true));
      }
    } on ApiException catch (error) {
      if (error.code == 'network_error') {
        _showNetworkError('Unable to connect right now. Please try again.');
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
      setState(() {
        _isLoadingData = true;
        _isFollowupsLoading = true;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _apiClient.fetchTodaySummary(),
        _apiClient.fetchAssignedLeads(),
        _apiClient.fetchFollowups(),
        _apiClient.fetchLearningCenter(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _applySummarySnapshot(results[0] as DailySummary);
        _leads = results[1] as List<LeadItem>;
        _followups = results[2] as List<LeadItem>;
        _applyLearningPayload(results[3] as LearningCenterPayload);
        _isNetworkErrorVisible = false;
        if (_leadIndex >= _leads.length) {
          _leadIndex = _leads.isEmpty ? 0 : _leads.length - 1;
        }
      });
      _syncPresenceMonitoring();
      if (_summary.pendingCallStatusRequired) {
        if (_requiredPermissionsGranted == true) {
          _schedulePendingCallStatusPrompt();
        }
        return;
      }
      if (_requiredPermissionsGranted == true &&
          _summary.currentState == 'warning' &&
          !_isIdleWarningVisible) {
        unawaited(_showIdleWarning());
      }
      if (promptTrainingGate && _requiredPermissionsGranted == true) {
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
        setState(() {
          _isLoadingData = false;
          _isFollowupsLoading = false;
        });
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
      final payload =
          await _updaterChannel.invokeMapMethod<String, dynamic>(
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
        _showMessage(
          'Could not check for app updates right now.',
          isError: true,
        );
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
    final update =
        _pendingAppUpdate ?? await _checkForAvailableUpdate(force: true);
    if (update == null) {
      _showMessage('Your app is up to date.');
      return;
    }
    await _showAppUpdatePrompt(update);
  }

  Future<bool> _hasDownloadedAppUpdate(AppUpdateInfo update) async {
    try {
      final payload =
          await _updaterChannel.invokeMapMethod<String, dynamic>(
            'getDownloadedUpdateStatus',
            <String, dynamic>{'versionCode': update.versionCode},
          ) ??
          const <String, dynamic>{};
      return payload['isDownloaded'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _installDownloadedAppUpdate(AppUpdateInfo update) async {
    try {
      final response =
          await _updaterChannel.invokeMapMethod<String, dynamic>(
            'installDownloadedUpdate',
            <String, dynamic>{'versionCode': update.versionCode},
          ) ??
          const <String, dynamic>{};
      final status = response['status']?.toString() ?? 'error';
      final message =
          response['message']?.toString() ??
          'Android is opening the installer for the downloaded update.';
      if (status == 'started' || status == 'up_to_date') {
        _showMessage(message);
        return true;
      }
      _showMessage(message, isError: true);
      return false;
    } on MissingPluginException {
      _showMessage(
        'This device cannot open the downloaded update right now.',
        isError: true,
      );
      return false;
    } on PlatformException catch (error) {
      _showMessage(
        error.message ?? 'Could not open the downloaded update.',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _showAppUpdatePrompt(AppUpdateInfo update) async {
    if (!mounted || _isUpdateDialogVisible) {
      return;
    }

    final hasDownloadedUpdate = await _hasDownloadedAppUpdate(update);
    if (!mounted) {
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
              update.isMandatory ? 'Update Required' : 'New Update Ready',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasDownloadedUpdate
                        ? 'The downloaded HEAVENECTION update is ready to install.'
                        : 'A new HEAVENECTION update is ready.',
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
                        label: update.isMandatory ? 'Required' : 'Optional',
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
                      if (hasDownloadedUpdate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: kGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Downloaded',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: kGreen,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(height: 16),
                  const Text(
                    "What's New",
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
                          ? 'A new HEAVENECTION update is ready.'
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
                    hasDownloadedUpdate
                        ? 'Install the downloaded package to finish updating.'
                        : update.isMandatory
                        ? 'Please complete this update before continuing.'
                        : 'You can update now or continue and do it later.',
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
                  Navigator.of(dialogContext).pop(
                    hasDownloadedUpdate
                        ? _AppUpdateAction.install
                        : _AppUpdateAction.download,
                  );
                },
                icon: Icon(
                  hasDownloadedUpdate
                      ? Icons.install_mobile_rounded
                      : Icons.download_rounded,
                ),
                label: Text(
                  hasDownloadedUpdate ? 'Install Update' : 'Update Now',
                ),
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
    } else if (action == _AppUpdateAction.install) {
      final started = await _installDownloadedAppUpdate(update);
      if (!started && update.isMandatory) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showAppUpdatePrompt(update));
          }
        });
      }
    }
  }

  Future<Map<String, dynamic>> _readPhoneCallState() async {
    try {
      return Map<String, dynamic>.from(
        await _updaterChannel.invokeMapMethod<String, dynamic>(
              'isCallInProgress',
            ) ??
            const <String, dynamic>{},
      );
    } on MissingPluginException {
      return const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{};
    }
  }

  Future<bool> _ensurePhoneStateAccess({
    bool showMessageOnDenied = true,
  }) async {
    final permissionsReady = await _ensureRequiredPermissionsReady(
      requestIfMissing: true,
      showDialogIfMissing: true,
    );
    if (!permissionsReady) {
      return false;
    }

    final callState = await _readPhoneCallState();
    if (callState['permissionGranted'] == true) {
      return true;
    }
    if (showMessageOnDenied) {
      _showMessage(
        'Allow all required Android permissions so the app can detect when a customer call ends.',
        isError: true,
      );
    }
    return false;
  }

  Future<bool> _downloadAppUpdate(AppUpdateInfo update) async {
    if (_isDownloadingUpdate) {
      return true;
    }

    _registerInteraction(syncServer: false);
    _isDownloadingUpdate = true;
    try {
      final response =
          await _updaterChannel.invokeMapMethod<String, dynamic>(
            'downloadAppUpdate',
            <String, dynamic>{
              'url': update.downloadUrl,
              'fileName': update.fileName,
              'versionCode': update.versionCode,
              'title': 'HEAVENECTION ${update.versionName}',
              'description': 'Downloading the latest HEAVENECTION update.',
            },
          ) ??
          const <String, dynamic>{};
      final status = response['status']?.toString() ?? 'error';
      final message =
          response['message']?.toString() ??
          'Your phone will guide you through the update once the file is ready.';
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

  Future<void> _openSalaryDetailsPage() async {
    _registerInteraction(syncServer: false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffSalaryDetailsPage(
          apiClient: _apiClient,
          initialSummary: _profile?.salarySummary,
        ),
      ),
    );
  }

  Future<List<LeadItem>> _searchCustomerHistory(String query) async {
    try {
      return await _apiClient.searchCustomerHistory(query: query);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return const [];
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to search previous customers right now. Reconnect and try again.',
        );
        return const [];
      }
      _showMessage(error.message, isError: true);
      return const [];
    }
  }

  Future<RecoveredLeadResult?> _recoverCustomerLead(
    LeadItem lead, {
    required String statusLabel,
    String callbackWindow = '',
    String callbackScheduleLabel = '',
    DateTime? callbackDate,
    InterestedLeadCaptureInput? interestedDetail,
  }) async {
    try {
      final updatedLead = await _apiClient.recoverCustomerLead(
        leadId: lead.id,
        status: _statusValue(statusLabel),
        callbackWindow: callbackWindow,
        callbackDate: callbackDate,
        customerName: interestedDetail?.customerName,
        customerPhone: interestedDetail?.customerPhone,
        productEnquired: interestedDetail?.productEnquired,
        enquiryNotes: interestedDetail?.enquiryNotes,
        preferredCallTime: interestedDetail?.preferredCallTime,
      );
      return RecoveredLeadResult(
        leadId: updatedLead.id,
        leadName: updatedLead.name.isNotEmpty ? updatedLead.name : lead.name,
        statusLabel: statusLabel,
        callbackScheduleLabel: updatedLead.callbackScheduleLabel.isNotEmpty
            ? updatedLead.callbackScheduleLabel
            : callbackScheduleLabel,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return null;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to restore this customer right now. Reconnect and try again.',
        );
        return null;
      }
      _showMessage(error.message, isError: true);
      return null;
    }
  }

  Future<void> _openCustomerRecoveryPage() async {
    _registerInteraction(syncServer: false);
    final result = await Navigator.of(context).push<RecoveredLeadResult>(
      MaterialPageRoute(
        builder: (_) => CustomerRecoveryPage(
          staffName: _user?.name ?? '',
          onSearch: _searchCustomerHistory,
          onRecover: _recoverCustomerLead,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    await _loadDashboardData(showLoader: false, promptTrainingGate: false);
    if (!mounted) {
      return;
    }

    if (result.statusLabel == 'Follow Up' &&
        result.callbackScheduleLabel.isNotEmpty) {
      _showMessage(
        '${result.leadName} moved back to your list for ${result.callbackScheduleLabel}.',
      );
      return;
    }

    _showMessage('${result.leadName} moved to admin Interested review.');
  }

  Future<void> _openFollowupQueuePage() async {
    _registerInteraction(syncServer: false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowupQueuePage(
          apiClient: _apiClient,
          onCall: (lead) async {
            _registerInteraction(syncServer: false);
            await _showCallScreenForLead(lead, fromFollowup: true);
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadDashboardData(showLoader: false, promptTrainingGate: false);
  }

  Future<bool> _submitInterestedLeadDetail({
    required String callId,
    required String customerName,
    required String customerPhone,
    required String productEnquired,
    required String enquiryNotes,
    required String preferredCallTime,
  }) async {
    try {
      await _apiClient.submitInterestedLeadDetail(
        callId: callId,
        customerName: customerName,
        customerPhone: customerPhone,
        productEnquired: productEnquired,
        enquiryNotes: enquiryNotes,
        preferredCallTime: preferredCallTime,
      );
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return false;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while saving the interested customer details.',
        );
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    }
  }

  Future<bool> _openInterestedLeadCapturePage(
    LeadItem? lead, {
    required String callId,
  }) async {
    if (!mounted) {
      return false;
    }
    final customerLead =
        lead ??
        LeadItem(
          id: _pendingStatusLeadId ?? '',
          name: _pendingStatusLeadName.isNotEmpty
              ? _pendingStatusLeadName
              : 'Customer',
          phone: _pendingStatusLeadPhone,
          status: 'interested',
          statusLabel: 'Interested',
          callbackWindow: '',
          callbackWindowLabel: '',
          callbackDate: null,
          callbackDateLabel: '',
          callbackScheduleLabel: '',
          notes: '',
        );
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InterestedLeadCapturePage(
          lead: customerLead,
          onSubmit:
              ({
                required customerName,
                required customerPhone,
                required productEnquired,
                required enquiryNotes,
                required preferredCallTime,
              }) => _submitInterestedLeadDetail(
                callId: callId,
                customerName: customerName,
                customerPhone: customerPhone,
                productEnquired: productEnquired,
                enquiryNotes: enquiryNotes,
                preferredCallTime: preferredCallTime,
              ),
        ),
      ),
    );
    if (submitted == true) {
      await _loadDashboardData(showLoader: false, promptTrainingGate: false);
      if (mounted) {
        _showMessage('Interested customer details saved.');
      }
      return true;
    }
    return false;
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _loginErrorText = null);
    if (phone.text.trim().isEmpty || password.text.isEmpty) {
      setState(
        () =>
            _loginErrorText = 'Enter your phone number or email and password.',
      );
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final user = await _apiClient.login(
        identifier: phone.text.trim(),
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
      _markRequiredPermissionsPending();
      _updatePreferredOrientations();
      await _loadDashboardData(showLoader: false, promptTrainingGate: false);
      unawaited(_runDeferredStartupWarmup(promptTrainingGate: true));
    } on ApiException catch (error) {
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to connect right now. The app will recover automatically when service returns.',
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
      _selectedPassbookPhoto = null;
      _removeAadharPhoto = false;
      _removePassbookPhoto = false;
      _pendingAppUpdate = null;
      _hasCheckedAppUpdate = false;
      _isDownloadingUpdate = false;
      _isUpdateDialogVisible = false;
      _requiredPermissionStatus = const <String, dynamic>{};
      _requiredPermissionsGranted = null;
      _isRefreshingRequiredPermissions = false;
      _isRequiredPermissionDialogVisible = false;
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
      _selectedPassbookPhoto = null;
      _removeAadharPhoto = false;
      _removePassbookPhoto = false;
      _pendingAppUpdate = null;
      _hasCheckedAppUpdate = false;
      _isDownloadingUpdate = false;
      _isUpdateDialogVisible = false;
      _requiredPermissionStatus = const <String, dynamic>{};
      _requiredPermissionsGranted = null;
      _isRefreshingRequiredPermissions = false;
      _isRequiredPermissionDialogVisible = false;
    });
    _updatePreferredOrientations();
  }

  Future<void> _confirmLogout() async {
    if (!mounted) {
      return;
    }

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Confirm Logout'),
          content: const Text('Do you want to log out from HEAVENECTION now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  Future<ImageSource?> _showDocumentSourcePicker(String documentLabel) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add $documentLabel',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose how you want to add the document image.',
                  style: TextStyle(fontSize: 14.5, color: Colors.black54),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: kSoft,
                    child: Icon(Icons.camera_alt_outlined, color: kPrimaryDark),
                  ),
                  title: const Text(
                    'Use Camera',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Take a fresh photo now'),
                  onTap: () {
                    Navigator.of(sheetContext).pop(ImageSource.camera);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: kSoft,
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: kPrimaryDark,
                    ),
                  ),
                  title: const Text(
                    'Choose From Gallery',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Select an existing image'),
                  onTap: () {
                    Navigator.of(sheetContext).pop(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDocumentPhoto(_ProfileDocument document) async {
    _registerInteraction(syncServer: false);
    try {
      final source = await _showDocumentSourcePicker(
        document == _ProfileDocument.aadhar ? 'Aadhaar' : 'Passbook',
      );
      if (source == null) {
        return;
      }
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null || !mounted) {
        return;
      }
      setState(() {
        if (document == _ProfileDocument.aadhar) {
          _selectedAadharPhoto = File(image.path);
          _removeAadharPhoto = false;
        } else {
          _selectedPassbookPhoto = File(image.path);
          _removePassbookPhoto = false;
        }
      });
    } catch (_) {
      _showMessage('Could not open the document picker.', isError: true);
    }
  }

  Future<void> _pickAadharPhoto() =>
      _pickDocumentPhoto(_ProfileDocument.aadhar);

  Future<void> _pickPassbookPhoto() =>
      _pickDocumentPhoto(_ProfileDocument.passbook);

  Future<void> _confirmDocumentRemoval(_ProfileDocument document) async {
    final profile = _profile;
    final isAadhar = document == _ProfileDocument.aadhar;
    final selectedFile = isAadhar
        ? _selectedAadharPhoto
        : _selectedPassbookPhoto;
    final hasSavedDocument = isAadhar
        ? (profile?.hasAadharPhoto ?? false)
        : (profile?.hasPassbookPhoto ?? false);
    final documentLabel = isAadhar ? 'Aadhaar photo' : 'passbook photo';

    if (selectedFile == null && !hasSavedDocument) {
      return;
    }

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text('Remove $documentLabel'),
          content: Text(
            hasSavedDocument
                ? 'Do you want to remove the saved $documentLabel from your profile?'
                : 'Do you want to discard the selected $documentLabel before saving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true || !mounted) {
      return;
    }

    if (selectedFile != null && !hasSavedDocument) {
      setState(() {
        if (isAadhar) {
          _selectedAadharPhoto = null;
          _removeAadharPhoto = false;
        } else {
          _selectedPassbookPhoto = null;
          _removePassbookPhoto = false;
        }
      });
      _showMessage(
        isAadhar
            ? 'Selected Aadhaar photo removed.'
            : 'Selected passbook photo removed.',
      );
      return;
    }

    setState(() => _isProfileSaving = true);
    try {
      final updatedProfile = await _apiClient.removeStaffDocument(
        removeAadharPhoto: isAadhar,
        removePassbookPhoto: !isAadhar,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = updatedProfile;
        _user = StaffUser(
          id: updatedProfile.id,
          name: updatedProfile.name,
          phone: updatedProfile.phone,
          role: updatedProfile.role,
        );
        if (isAadhar) {
          _selectedAadharPhoto = null;
          _removeAadharPhoto = false;
        } else {
          _selectedPassbookPhoto = null;
          _removePassbookPhoto = false;
        }
      });
      _showMessage(
        isAadhar
            ? 'Aadhaar photo removed successfully.'
            : 'Passbook photo removed successfully.',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to remove the document right now. Please try again shortly.',
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

  Future<bool> _saveProfile({
    String? currentPassword,
    String? newPassword,
    bool showSuccessMessage = true,
  }) async {
    FocusScope.of(context).unfocus();
    if (_isProfileSaving) {
      return false;
    }
    if (_profileNameController.text.trim().isEmpty ||
        _profilePhoneController.text.trim().isEmpty) {
      _showMessage('Name and phone number are required.', isError: true);
      return false;
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
        passbookPhoto: _selectedPassbookPhoto,
        currentPassword: currentPassword,
        newPassword: newPassword,
        aadharPhoto: _selectedAadharPhoto,
        removeAadharPhoto: _removeAadharPhoto,
        removePassbookPhoto: _removePassbookPhoto,
      );
      if (!mounted) {
        return false;
      }
      setState(() => _applyProfile(profile));
      if (showSuccessMessage) {
        _showMessage('Profile updated successfully.');
      }
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return false;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Unable to save right now. Please check your connection and try again.',
        );
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isProfileSaving = false);
      }
    }
  }

  Future<void> _openEditProfilePage() async {
    final originalProfile = _profile;
    if (originalProfile == null || !mounted) {
      return;
    }

    setState(() => _applyProfile(originalProfile));
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Edit Profile')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
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
                        'Identity documents',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add clear document images for Aadhaar and passbook from the camera or your gallery.',
                        style: TextStyle(fontSize: 14.5, color: Colors.black54),
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
                      _buildDocumentPreview(
                        selectedFile: _selectedAadharPhoto,
                        removeDocument: _removeAadharPhoto,
                        existingUrl: originalProfile.aadharPhotoUrl,
                        documentName: originalProfile.aadharPhotoName,
                        emptyLabel: 'No Aadhaar photo added',
                        icon: Icons.badge_outlined,
                        networkErrorLabel: 'Could not load the saved Aadhaar photo.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickAadharPhoto,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Add Aadhaar'),
                          ),
                          if (_selectedAadharPhoto != null ||
                              (originalProfile.hasAadharPhoto && !_removeAadharPhoto))
                            OutlinedButton.icon(
                              onPressed: _isProfileSaving
                                  ? null
                                  : () => _confirmDocumentRemoval(_ProfileDocument.aadhar),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove Photo'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Passbook image',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      _buildDocumentPreview(
                        selectedFile: _selectedPassbookPhoto,
                        removeDocument: _removePassbookPhoto,
                        existingUrl: originalProfile.passbookPhotoUrl,
                        documentName: originalProfile.passbookPhotoName,
                        emptyLabel: 'No passbook photo added',
                        icon: Icons.menu_book_outlined,
                        networkErrorLabel: 'Could not load the saved passbook photo.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickPassbookPhoto,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Add Passbook'),
                          ),
                          if (_selectedPassbookPhoto != null ||
                              (originalProfile.hasPassbookPhoto && !_removePassbookPhoto))
                            OutlinedButton.icon(
                              onPressed: _isProfileSaving
                                  ? null
                                  : () => _confirmDocumentRemoval(_ProfileDocument.passbook),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove Passbook'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _isProfileSaving
                      ? null
                      : () async {
                          final savedProfile = await _saveProfile();
                          if (savedProfile && mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
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
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true && mounted) {
      setState(() => _applyProfile(originalProfile));
    }
  }

  Future<void> _openChangePasswordDialog() async {
    final profile = _profile;
    if (profile == null || !mounted) {
      return;
    }

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? errorText;
    var isSubmitting = false;
    var isCurrentPasswordVisible = false;
    var isNewPasswordVisible = false;
    var isConfirmPasswordVisible = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitPassword() async {
              final currentPassword = currentPasswordController.text.trim();
              final newPassword = newPasswordController.text.trim();
              final confirmPassword = confirmPasswordController.text.trim();

              if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter the current, new, and confirm password.';
                });
                return;
              }
              if (newPassword != confirmPassword) {
                setDialogState(() {
                  errorText = 'New password and confirm password must match.';
                });
                return;
              }

              setDialogState(() {
                errorText = null;
                isSubmitting = true;
              });

              final changed = await _saveProfile(
                currentPassword: currentPassword,
                newPassword: newPassword,
                showSuccessMessage: false,
              );

              if (!mounted) {
                return;
              }
              if (!dialogContext.mounted) {
                return;
              }

              setDialogState(() => isSubmitting = false);
              if (!changed) {
                return;
              }

              Navigator.of(dialogContext).pop();
              await showDialog<void>(
                context: context,
                builder: (successContext) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    title: const Text('Password Updated'),
                    content: const Text('Your password was changed successfully.'),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(successContext).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter your current password and choose a new one.',
                      style: TextStyle(fontSize: 14.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: currentPasswordController,
                      obscureText: !isCurrentPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              isCurrentPasswordVisible =
                                  !isCurrentPasswordVisible;
                            });
                          },
                          icon: Icon(
                            isCurrentPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: !isNewPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              isNewPasswordVisible = !isNewPasswordVisible;
                            });
                          },
                          icon: Icon(
                            isNewPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: !isConfirmPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.verified_outlined),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              isConfirmPasswordVisible =
                                  !isConfirmPasswordVisible;
                            });
                          },
                          icon: Icon(
                            isConfirmPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: kRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submitPassword,
                  child: Text(isSubmitting ? 'Updating...' : 'Change Password'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _openReferralDialog() async {
    final profile = _profile;
    if (profile == null || !profile.referralProgramEnabled || !mounted) {
      return;
    }

    final referredNameController = TextEditingController();
    final referredPhoneController = TextEditingController();
    String? errorText;
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitReferral() async {
              final referredName = referredNameController.text.trim();
              final referredPhone = referredPhoneController.text.trim();
              if (referredName.isEmpty || referredPhone.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter your friend\'s name and phone number.';
                });
                return;
              }
              setDialogState(() {
                errorText = null;
                isSubmitting = true;
              });
              try {
                await _apiClient.submitReferral(
                  referredName: referredName,
                  referredPhone: referredPhone,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showMessage('Referral submitted successfully.');
              } on ApiException catch (error) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    errorText = error.message;
                    isSubmitting = false;
                  });
                }
                if (error.statusCode == 401) {
                  await _handleForcedLogout();
                } else if (error.code == 'network_error') {
                  _showNetworkError(
                    'Unable to submit the referral right now. Please try again when the connection is stable.',
                  );
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Earn more? Refer a friend'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refer a friend to the team. When they complete ${profile.referralRequiredHoursLabel}, you can earn ${profile.referralRewardAmountLabel}.',
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: referredNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Friend Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: referredPhoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: kRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submitReferral,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Referral'),
                ),
              ],
            );
          },
        );
      },
    );

    referredNameController.dispose();
    referredPhoneController.dispose();
  }

  Future<void> _startWork({bool fromTraining = false}) async {
    if (_isSessionBusy) {
      return;
    }
    if (_hasPendingMandatoryTraining) {
      _showMessage(
        'Complete the required training before calling customers.',
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
        _applySummarySnapshot(response.summary);
        _lastInteractionAt = DateTime.now();
        _lastCallActivityAt = DateTime.now();
        _backgroundedAt = null;
      });
      _syncPresenceMonitoring();
      _isTrainingPromptVisible = false;
      _showMessage(
        fromTraining
            ? 'Training completed. You can start calling customers now.'
            : 'Call session started automatically.',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError('Unable to start right now. Please try again.');
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
        _applySummarySnapshot(response.summary);
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
          'Unable to finish right now. Please check your connection and try again.',
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
        _applySummarySnapshot(response.summary);
        if (interaction) {
          _lastInteractionAt = DateTime.now();
        }
      });
      if (_summary.pendingCallStatusRequired &&
          _requiredPermissionsGranted == true) {
        _schedulePendingCallStatusPrompt();
      }
      _syncPresenceMonitoring();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection interrupted. The app will restore automatically when service returns.',
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
    _callTimer = null;
    _lastActiveCallAutoCheckAt = null;
    _stopSyncSolveCountdown();
    _activeCallId = null;
    _activeCallLeadId = null;
    _activeCallFromFollowup = false;
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
    for (final lead in _followups) {
      if (lead.id == leadId) {
        return lead;
      }
    }
    return null;
  }

  LeadItem? _pendingStatusLeadPlaceholder() {
    final leadId = _pendingStatusLeadId;
    if (leadId == null || leadId.isEmpty) {
      return null;
    }
    final existingLead = _leadById(leadId);
    if (existingLead != null) {
      return existingLead;
    }
    final fallbackName = _pendingStatusLeadName.isNotEmpty
        ? _pendingStatusLeadName
        : (_pendingStatusLeadPhone.isNotEmpty
              ? _pendingStatusLeadPhone
              : 'Recent customer');
    final fallbackPhone = _pendingStatusLeadPhone.isNotEmpty
        ? _pendingStatusLeadPhone
        : '';
    return LeadItem(
      id: leadId,
      name: fallbackName,
      phone: fallbackPhone,
      status: _pendingStatusFromFollowup ? 'call_back' : 'new',
      statusLabel: _pendingStatusFromFollowup ? 'Follow Up' : 'New',
      callbackWindow: '',
      callbackWindowLabel: '',
      callbackDate: null,
      callbackDateLabel: '',
      callbackScheduleLabel: '',
      notes: '',
    );
  }

  bool _isFollowupLeadItem(LeadItem? lead) {
    if (lead == null) {
      return false;
    }
    final status = lead.status.toLowerCase();
    final statusLabel = lead.statusLabel.toLowerCase();
    return status == 'call_back' ||
        status == 'interested' ||
        statusLabel == 'follow up';
  }

  bool _isFollowupLeadContext(LeadItem? lead) {
    return _pendingStatusFromFollowup ||
        _activeCallFromFollowup ||
        _isFollowupLeadItem(lead);
  }

  Future<void> _placeCallForLead(LeadItem lead) async {
    final canReadCallLog = await _ensureCallLogAccess();
    if (!canReadCallLog) {
      return;
    }
    final canReadPhoneState = await _ensurePhoneStateAccess();
    if (!canReadPhoneState) {
      return;
    }

    final dialStartedAt = DateTime.now();
    final isFollowupLead = _activeCallFromFollowup || _isFollowupLeadItem(lead);
    final call = await _apiClient.startCall(
      leadId: lead.id,
      fromFollowupMenu: isFollowupLead,
    );
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
      _activeCallFromFollowup = isFollowupLead;
      _pendingDialerCall = PendingDialerCall(
        callId: call.id,
        leadId: lead.id,
        phone: lead.phone,
        startedAt: dialStartedAt,
      );
      _lastCallActivityAt = dialStartedAt;
      _elapsed = Duration.zero;
    });
    _ensureActiveCallTimerRunning();
  }

  Future<void> _startCall({LeadItem? selectedLead}) async {
    _registerInteraction(syncServer: false);
    final lead =
        selectedLead ?? (_leads.isNotEmpty ? _leads[_safeLeadIndex] : null);
    if (lead == null) {
      _showMessage('No assigned leads available.', isError: true);
      return;
    }
    final hasPendingStatusForSameLead =
        _hasPendingCallStatus && _pendingStatusLeadId == lead.id;
    if (!hasPendingStatusForSameLead &&
        !await _ensurePendingCallStatusResolved(lead)) {
      return;
    }
    if (!_summary.workingNow) {
      await _startWork();
      if (!_summary.workingNow) {
        return;
      }
    }
    if (hasPendingStatusForSameLead) {
      await _retryPendingCustomerCall();
      return;
    }
    final hasRecoverableCallForSameLead =
        _hasRecoverableCustomerCall &&
        _summary.recoverableCallLeadId == lead.id;
    if (hasRecoverableCallForSameLead) {
      await _openCurrentCallScreen(
        notice:
            'Solving the current customer call first, then calling the same customer again.',
      );
      if (!mounted) {
        return;
      }
      if (_hasPendingCallStatus && _pendingStatusLeadId == lead.id) {
        await _retryPendingCustomerCall();
        return;
      }
      if (_hasRecoverableCustomerCall || _hasActiveCustomerCall) {
        return;
      }
    }
    if (_activeCallId != null) {
      if (_activeCallLeadId == lead.id) {
        await _waitForCallEndThenSync(
          allowManualFallback: true,
          showMissingMessage: true,
        );
        if (!mounted) {
          return;
        }
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        if (!mounted) {
          return;
        }
        if (_hasPendingCallStatus && _pendingStatusLeadId == lead.id) {
          await _retryPendingCustomerCall();
        }
        return;
      }
      await _openCurrentCallScreen(
        notice: 'Finish the current customer call before starting another.',
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
      if (error.statusCode == 409 && error.code == 'call_recovery_required') {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        await _openCurrentCallScreen(
          notice: 'Sync the current customer call before starting another one.',
        );
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

    await _waitForCallEndThenSync(
      allowManualFallback: true,
      showMissingMessage: true,
    );
  }

  Future<void> _solveSyncIssue({String? notice}) async {
    _registerInteraction(syncServer: false);
    await _openCurrentCallScreen(
      notice:
          notice ??
          'Solve the current call sync issue before moving to another customer.',
    );
  }

  Future<void> _escapeSyncIssueCall() async {
    _registerInteraction(syncServer: false);
    if (_activeCallId == null ||
        _pendingDialerCall == null ||
        _isSyncingCallLog) {
      return;
    }

    final shouldEscape = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Close Sync Issue Call?'),
          content: const Text(
            'Use this only if the customer call cannot be synced from the phone. The call will be closed without phone-log verification and no work hours will be added.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Close Without Sync'),
            ),
          ],
        );
      },
    );

    if (shouldEscape != true) {
      return;
    }

    await _completeCallManually(source: 'manual_sync_escape');
  }

  Future<bool> _ensureCallLogAccess() async {
    final permissionsReady = await _ensureRequiredPermissionsReady(
      requestIfMissing: true,
      showDialogIfMissing: true,
    );
    if (!permissionsReady) {
      return false;
    }

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
      await _refreshRequiredPermissionState(showDialogIfMissing: true);
      _showMessage(
        'Allow all required Android permissions to sync calls automatically.',
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
      dateTimeFrom: pendingCall.startedAt.subtract(kCallLogMatchLookback),
      dateTimeTo: DateTime.now().add(kCallLogMatchLookahead),
      type: CallType.outgoing,
    );

    final matchingEntries = <CallLogEntry>[];

    for (final entry in entries) {
      final timestamp = entry.timestamp;
      final number = entry.number ?? entry.formattedNumber ?? '';
      if (timestamp == null || !_phoneMatches(number, pendingCall.phone)) {
        continue;
      }

      final startedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (startedAt.isBefore(
        pendingCall.startedAt.subtract(kCallLogMatchLookback),
      )) {
        continue;
      }
      matchingEntries.add(entry);
    }

    if (matchingEntries.isEmpty) {
      return null;
    }

    matchingEntries.sort((a, b) {
      final aTimestamp = a.timestamp ?? 0;
      final bTimestamp = b.timestamp ?? 0;
      final aDiff = (aTimestamp - pendingCall.startedAt.millisecondsSinceEpoch)
          .abs();
      final bDiff = (bTimestamp - pendingCall.startedAt.millisecondsSinceEpoch)
          .abs();
      if (aDiff != bDiff) {
        return aDiff.compareTo(bDiff);
      }

      final aDuration = a.duration ?? 0;
      final bDuration = b.duration ?? 0;
      if (aDuration != bDuration) {
        return bDuration.compareTo(aDuration);
      }

      return bTimestamp.compareTo(aTimestamp);
    });

    return matchingEntries.first;
  }

  Future<_CallRemarkDialogResult?> _showCallRemarkDialog({
    required String title,
    required String message,
    required List<String> choices,
    required String saveButtonLabel,
    String initialStatus = '',
    bool allowRetryAction = false,
    String retryButtonLabel = 'Call Again',
    bool trackPendingPrompt = false,
    bool allowUnscheduledFollowup = false,
    String unscheduledFollowupTitle = 'Keep Follow Up Without Schedule?',
    String unscheduledFollowupMessage =
        'This follow-up will stay in the Follow Ups menu without a date or time. Continue?',
  }) async {
    if (!mounted) {
      return null;
    }

    const callbackChoices = ['Noon', 'Evening', 'Night'];
    var selectedStatus = choices.contains(initialStatus)
        ? initialStatus
        : choices.first;
    var selectedCallbackWindow = '';
    DateTime? selectedCallbackDate;

    return showDialog<_CallRemarkDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (trackPendingPrompt) {
          _callStatusDialogContext = dialogContext;
        }
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: Text(title),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message),
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
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ...choices.map((item) {
                          final isSelected = selectedStatus == item;
                          final color = _remarkColor(item);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: isSaving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedStatus = item;
                                        if (item != 'Follow Up') {
                                          selectedCallbackWindow = '';
                                          selectedCallbackDate = null;
                                        }
                                      });
                                    },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withValues(alpha: 0.12)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? color : Colors.black12,
                                    width: isSelected ? 1.6 : 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? color
                                            : color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        _remarkIcon(item),
                                        color: isSelected
                                            ? Colors.white
                                            : color,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item,
                                            style: TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected
                                                  ? color
                                                  : kPrimaryDark,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _remarkDescription(item),
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              color: Colors.black54,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        if (selectedStatus == 'Follow Up') ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Choose the follow-up date and time requested by the customer',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: isSaving
                                ? null
                                : () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate:
                                          selectedCallbackDate ??
                                          DateTime(
                                            now.year,
                                            now.month,
                                            now.day,
                                          ),
                                      firstDate: DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      ),
                                      lastDate: DateTime(
                                        now.year + 1,
                                        now.month,
                                        now.day,
                                      ),
                                    );
                                    if (picked == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => selectedCallbackDate = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                      ),
                                    );
                                  },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selectedCallbackDate != null
                                      ? kPrimary
                                      : Colors.black12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_month_rounded,
                                    color: kPrimaryDark,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedCallbackDate == null
                                          ? 'Choose callback date'
                                          : _formatCallbackDateLabel(
                                              selectedCallbackDate!,
                                            ),
                                      style: TextStyle(
                                        color: selectedCallbackDate == null
                                            ? Colors.black54
                                            : kPrimaryDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                              () =>
                                                  selectedCallbackWindow = item,
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
                  ),
                ),
                actions: [
                  if (allowRetryAction)
                    TextButton(
                      onPressed: isSaving
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop(
                                const _CallRemarkDialogResult(retryCall: true),
                              );
                            },
                      child: Text(retryButtonLabel),
                    ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (selectedStatus == 'Follow Up' &&
                                (selectedCallbackWindow.isEmpty ||
                                    selectedCallbackDate == null) &&
                                !allowUnscheduledFollowup) {
                              return;
                            }
                            if (selectedStatus == 'Follow Up' &&
                                (selectedCallbackWindow.isEmpty ||
                                    selectedCallbackDate == null) &&
                                allowUnscheduledFollowup) {
                              final shouldContinue =
                                  await _confirmUnscheduledFollowup(
                                    title: unscheduledFollowupTitle,
                                    message: unscheduledFollowupMessage,
                                  );
                              if (!shouldContinue) {
                                return;
                              }
                              if (!dialogContext.mounted) {
                                return;
                              }
                            }
                            setDialogState(() => isSaving = true);
                            final callbackDateLabel =
                                selectedCallbackDate == null
                                ? ''
                                : _formatCallbackDateLabel(
                                    selectedCallbackDate!,
                                  );
                            Navigator.of(dialogContext).pop(
                              _CallRemarkDialogResult(
                                statusLabel: selectedStatus,
                                callbackWindow: _callbackWindowValue(
                                  selectedCallbackWindow,
                                ),
                                callbackWindowLabel: selectedCallbackWindow,
                                callbackDate: selectedCallbackDate,
                                callbackDateLabel: callbackDateLabel,
                                callbackScheduleLabel:
                                    _formatCallbackScheduleLabel(
                                      callbackDateLabel,
                                      selectedCallbackWindow,
                                    ),
                              ),
                            );
                          },
                    child: Text(isSaving ? 'Saving...' : saveButtonLabel),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<ShortCallDecision?> _askShortCallDecision(
    int durationSeconds, {
    LeadItem? lead,
  }) async {
    if (_isFollowupLeadContext(lead)) {
      final followupLead =
          lead ??
          _pendingStatusLeadPlaceholder() ??
          LeadItem(
            id: _pendingStatusLeadId ?? '',
            name: _pendingStatusLeadName.isNotEmpty
                ? _pendingStatusLeadName
                : 'Follow Up Customer',
            phone: _pendingStatusLeadPhone,
            status: 'call_back',
            statusLabel: 'Follow Up',
            callbackWindow: '',
            callbackWindowLabel: '',
            callbackDate: null,
            callbackDateLabel: '',
            callbackScheduleLabel: '',
            notes: '',
          );
      return _showFollowupNoResponseDialog(followupLead, durationSeconds);
    }
    final isNoResponse = durationSeconds <= 0;
    final result = await _showCallRemarkDialog(
      title: 'Select Customer Remark',
      message: isNoResponse
          ? 'The call did not connect. Mark it as No Response or call the customer again.'
          : 'This call lasted less than 15 seconds. If the discussion was not complete, call the customer again. Otherwise mark No Response or Rejected.',
      choices: isNoResponse
          ? const ['No Response']
          : const ['No Response', 'Rejected'],
      saveButtonLabel: 'Save Remark',
      initialStatus: 'No Response',
      allowRetryAction: true,
    );
    if (result == null) {
      return null;
    }
    if (result.retryCall) {
      return ShortCallDecision.callAgain;
    }
    if (result.statusLabel == 'Rejected') {
      return ShortCallDecision.markRejected;
    }
    return ShortCallDecision.markNoResponse;
  }

  Future<void> _completeShortCallDecision(
    PendingDialerCall pendingCall,
    DateTime endedAt, {
    required int durationSeconds,
    required ShortCallDecision decision,
  }) async {
    final lead = _leadById(pendingCall.leadId);
    final isFollowupLead = _isFollowupLeadContext(lead);
    final status = switch (decision) {
      ShortCallDecision.markRejected => 'not_interested',
      ShortCallDecision.markNoResponse => 'no_answer',
      ShortCallDecision.callAgain => isFollowupLead ? 'no_answer' : null,
    };
    final call = await _apiClient.endCall(
      callId: pendingCall.callId,
      status: status,
      durationSeconds: durationSeconds,
      endedAt: endedAt,
      source: decision == ShortCallDecision.callAgain && !isFollowupLead
          ? 'call_log_short_recall'
          : 'call_log_short_resolution',
    );

    final wasFollowupLead = isFollowupLead;
    _resetActiveCallTracking();
    if (!mounted) {
      return;
    }

    setState(() {
      _callStatus = decision == ShortCallDecision.markRejected
          ? 'Rejected'
          : (wasFollowupLead && decision == ShortCallDecision.callAgain)
          ? 'Follow Up'
          : 'No Response';
    });
    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    if (decision == ShortCallDecision.callAgain) {
      _showMessage('Follow-up try saved. Calling the customer again.');
      final refreshedLead = _leadById(pendingCall.leadId);
      if (refreshedLead != null) {
        _activeCallFromFollowup = true;
        _pendingStatusFromFollowup = true;
        await _placeCallForLead(refreshedLead);
      } else {
        _showMessage(
          'Lead was updated, but a new call could not be started.',
          isError: true,
        );
      }
      return;
    }

    if (call.status == 'no_answer' && wasFollowupLead) {
      final refreshedLead = _leadById(pendingCall.leadId);
      if (refreshedLead != null && _isFollowupLeadItem(refreshedLead)) {
        _showMessage(
          'Follow-up try saved. Keep contacting this customer from the Follow Ups menu.',
        );
        setState(() {
          _tab = 0;
          _lastLoadedTab = 0;
        });
        return;
      }
    }

    if (call.status == 'no_answer') {
      _showMessage('Call marked as No Response.');
    } else if (call.status == 'not_interested') {
      _showMessage('Call marked as Rejected.');
    } else {
      _showMessage('Call sync completed successfully.', isSuccess: true);
      return;
    }

    await _focusLeadWorkflowAfterCallResultSaved();
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
    final lead = _leadById(pendingCall.leadId);

    if (durationSeconds < kShortCallReviewThreshold.inSeconds) {
      final decision = await _askShortCallDecision(durationSeconds, lead: lead);
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
        _pendingStatusFromFollowup =
            _activeCallFromFollowup || _isFollowupLeadItem(lead);
        _callStatus = 'Interested';
      }
    });

    if (call.status == 'started') {
      _schedulePendingCallStatusPrompt();
      return;
    }

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    _showMessage('Call sync completed successfully.', isSuccess: true);
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
        _pendingStatusFromFollowup =
            _activeCallFromFollowup || _isFollowupLeadItem(lead);
        _callStatus = 'Interested';
      }
    });

    if (call.status == 'started') {
      _showMessage(
        'Call result is still pending. No work hours were added because the phone log could not verify this call.',
        isError: true,
      );
      _schedulePendingCallStatusPrompt();
      return;
    }

    await _loadDashboardData(showLoader: false);
    if (!mounted) {
      return;
    }

    await _focusLeadWorkflowAfterCallResultSaved();
    if (!mounted) {
      return;
    }

    _showMessage('Call sync completed successfully.', isSuccess: true);
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
      await _completeCallManually(source: 'sync_issue_no_log_access_skip');
      return false;
    }

    _setCallLogSyncing(true);
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

      await _completeCallManually(source: 'sync_issue_no_log_match_skip');
      return false;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return false;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection interrupted while saving the call. The app will recover automatically when service returns.',
        );
        return false;
      }
      _showMessage(error.message, isError: true);
      return false;
    } catch (_) {
      await _completeCallManually(source: 'sync_issue_read_error_skip');
      return false;
    } finally {
      _setCallLogSyncing(false);
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

  Future<void> _handleResumeState() async {
    final permissionsReady = await _refreshRequiredPermissionState(
      showDialogIfMissing: true,
    );
    if (!permissionsReady) {
      return;
    }

    if (!_summary.workingNow) {
      await _loadDashboardData(showLoader: false, promptTrainingGate: true);
      return;
    }

    await _handleResumeFromBackground();
  }

  Future<void> _handleResumeFromBackground() async {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    if (await _maybeAutoSyncEndedCall()) {
      return;
    }

    await _loadDashboardData(showLoader: false, promptTrainingGate: true);
    if (await _maybeAutoSyncEndedCall(showMissingMessage: false)) {
      return;
    }
    if (_tab == 3) {
      await _loadProfile(showLoader: false);
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

  Future<bool> _maybeAutoSyncEndedCall({bool showMissingMessage = true}) async {
    if (_pendingDialerCall == null || _isSyncingCallLog) {
      return false;
    }

    final callState = await _readPhoneCallState();
    if (callState['permissionGranted'] != true) {
      return false;
    }
    if (callState['isInCall'] == true) {
      return false;
    }

    return _syncCallFromLog(
      allowManualFallback: false,
      showMissingMessage: showMissingMessage,
    );
  }

  Future<bool> _waitForCallToEnd({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final callState = await _readPhoneCallState();
      if (callState['permissionGranted'] != true) {
        return false;
      }
      if (callState['isInCall'] != true) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final confirmedState = await _readPhoneCallState();
        return confirmedState['permissionGranted'] == true &&
            confirmedState['isInCall'] != true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<bool> _waitForCallEndThenSync({
    required bool allowManualFallback,
    bool showMissingMessage = false,
  }) async {
    final canReadPhoneState = await _ensurePhoneStateAccess(
      showMessageOnDenied: true,
    );
    if (!canReadPhoneState) {
      return false;
    }

    final initialCallState = await _readPhoneCallState();
    if (initialCallState['permissionGranted'] != true) {
      _showMessage(
        'Allow all required Android permissions so the app can detect when a customer call ends.',
        isError: true,
      );
      return false;
    }

    final wasInCall = initialCallState['isInCall'] == true;
    if (wasInCall) {
      _showMessage(
        'Waiting for the customer call to end. The app will check the final phone log automatically.',
      );
      final didEnd = await _waitForCallToEnd();
      if (!didEnd) {
        _showMessage(
          'End the customer call first so the app can check the final phone log.',
          isError: true,
        );
        return false;
      }
    }

    return _syncCallFromLog(
      allowManualFallback: allowManualFallback,
      showMissingMessage: showMissingMessage,
    );
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

  Future<void> _markOfflineBeforeExit() async {
    if (_user == null || !_summary.workingNow) {
      return;
    }

    try {
      final response = await _apiClient.sendHeartbeat(
        state: 'offline',
        source: 'app_exit',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applySummarySnapshot(response.summary);
      });
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _apiClient.clearSession();
      }
    } catch (_) {
      // Best-effort only. The app should still be allowed to exit.
    }
  }

  Future<void> _handleRootBackNavigation() async {
    if (!mounted) {
      return;
    }

    if (_user != null && _tab != 0) {
      _registerInteraction(syncServer: false);
      setState(() {
        _tab = 0;
        _lastLoadedTab = 0;
      });
      return;
    }

    if (_isExitDialogVisible) {
      return;
    }

    _isExitDialogVisible = true;
    final message = _activeCallId != null
        ? 'A customer call is still active. If you exit now, you will be marked offline immediately and work-hour counting will stop.'
        : _hasPendingCallStatus
        ? 'A recent call result is still pending. If you exit now, you will be marked offline immediately and work-hour counting will stop.'
        : _summary.workingNow
        ? 'If you exit the app now, you will be marked offline immediately and work-hour counting will stop.'
        : 'Do you want to exit the app?';

    final shouldExit =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Exit App?'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: kRed),
                  child: const Text('Exit'),
                ),
              ],
            );
          },
        ) ??
        false;
    _isExitDialogVisible = false;

    if (!shouldExit) {
      return;
    }

    await _markOfflineBeforeExit();
    await SystemNavigator.pop();
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
      _showMessage('Training completed. You can start calling customers now.');
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
                    ? 'Complete the required training lessons before calling customers.'
                    : 'Complete the required training lessons before calling customers. Next lesson: ${_learningSummary.nextRequiredTitle}.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    _isTrainingPromptVisible = false;
                    await _confirmLogout();
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

  Future<CallRecord?> _submitPendingCallStatus(
    String label, {
    String callbackWindow = '',
    DateTime? callbackDate,
    String callbackScheduleLabel = '',
  }) async {
    final callId = _pendingStatusCallId;
    if (callId == null || callId.isEmpty) {
      return null;
    }

    try {
      final savedCall = await _apiClient.updateCallStatus(
        callId: callId,
        status: _statusValue(label),
        callbackWindow: callbackWindow,
        callbackDate: callbackDate,
      );
      final savedLabel = _statusLabelFromValue(savedCall.status);
      if (!mounted) {
        return savedCall;
      }

      setState(() {
        _callStatus = savedLabel;
        _lastCallActivityAt = DateTime.now();
        _clearPendingCallStatus();
        _tab = 1;
        _lastLoadedTab = 1;
      });
      await _loadDashboardData(showLoader: false, promptTrainingGate: false);
      if (mounted) {
        if (savedLabel == 'Follow Up' && callbackScheduleLabel.isNotEmpty) {
          _showMessage('Follow Up scheduled for $callbackScheduleLabel.');
        } else if (savedLabel == 'Interested') {
          // The interested detail form opens next, so skip the interim toast.
        } else if (label == 'Rejected' && savedLabel != label) {
          _showMessage(
            'No real connected call was found, so the remark was saved as $savedLabel.',
          );
        } else {
          _showMessage('Remark saved as $savedLabel.');
        }
      }
      return savedCall;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _handleForcedLogout();
        return null;
      }
      if (error.code == 'network_error') {
        _showNetworkError(
          'Connection lost while saving the call result. Reconnect to continue.',
        );
        return null;
      }
      _showMessage(error.message, isError: true);
      return null;
    }
  }

  Future<void> _showPendingCallStatusPrompt() async {
    if (!mounted || !_hasPendingCallStatus || _isCallStatusPromptVisible) {
      return;
    }

    _isCallStatusPromptVisible = true;
    final pendingLead = _pendingStatusLeadPlaceholder();
    final isFollowupLead = _isFollowupLeadContext(pendingLead);
    final selection = await _showCallRemarkDialog(
      title: isFollowupLead ? 'Update Follow Up' : 'Select Customer Remark',
      message: isFollowupLead
          ? 'Choose the next step for this follow-up customer. Use Follow Up to reschedule, Rejected if the customer declined, or Interested if you are ready to move them forward.'
          : 'Choose one simple remark before moving to the next customer.',
      choices: isFollowupLead
          ? const ['Interested', 'Follow Up', 'Rejected']
          : const ['Rejected', 'Interested', 'Follow Up', 'No Response'],
      saveButtonLabel: isFollowupLead ? 'Save Follow Up' : 'Save Remark',
      initialStatus: isFollowupLead ? 'Interested' : _callStatus,
      trackPendingPrompt: true,
      allowRetryAction: !isFollowupLead,
      retryButtonLabel: 'Call Again',
      allowUnscheduledFollowup: true,
      unscheduledFollowupTitle: 'Save Follow Up Without Schedule?',
      unscheduledFollowupMessage:
          'This customer will stay in your Follow Ups menu without a date or time. Continue?',
    );
    _callStatusDialogContext = null;
    _isCallStatusPromptVisible = false;
    if (selection == null || selection.retryCall) {
      if (selection?.retryCall == true) {
        final lead = _pendingStatusLeadPlaceholder();
        if (lead == null) {
          _showMessage(
            'Unable to reopen the recent customer. Refresh and try again.',
            isError: true,
          );
          return;
        }
        final savedCall = await _submitPendingCallStatus('No Response');
        if (savedCall == null) {
          return;
        }
        _showMessage('Calling the customer again.');
        await _placeCallForLead(lead);
      }
      return;
    }
    final savedCall = await _submitPendingCallStatus(
      selection.statusLabel,
      callbackWindow: selection.callbackWindow,
      callbackDate: selection.callbackDate,
      callbackScheduleLabel: selection.callbackScheduleLabel,
    );
    if (savedCall != null) {
      if (selection.statusLabel == 'Interested') {
        final didSubmitInterestedDetail = await _openInterestedLeadCapturePage(
          pendingLead ?? _pendingStatusLeadPlaceholder(),
          callId: savedCall.id,
        );
        if (!didSubmitInterestedDetail) {
          return;
        }
        if (mounted) {
          _showMessage('Submitted to admin Interested review.');
        }
      }
      if (isFollowupLead && selection.statusLabel != 'Interested') {
        await _loadDashboardData(showLoader: false, promptTrainingGate: false);
        if (!mounted) {
          return;
        }
        setState(() {
          _tab = 1;
          _lastLoadedTab = 1;
        });
        return;
      }
      await _focusLeadWorkflowAfterCallResultSaved();
    }
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

  void _showMessage(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? kRed
            : (isSuccess ? kGreen : kPrimaryDark),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _statusValue(String label) {
    return switch (label) {
      'Interested' => 'interested',
      'Rejected' => 'not_interested',
      'No Response' => 'no_answer',
      'Follow Up' => 'call_back',
      'Converted' => 'converted',
      _ => 'interested',
    };
  }

  String _statusLabelFromValue(String value) {
    return switch (value) {
      'interested' => 'Interested',
      'not_interested' => 'Rejected',
      'no_answer' => 'No Response',
      'call_back' => 'Follow Up',
      'converted' => 'Converted',
      _ => 'Interested',
    };
  }

  IconData _remarkIcon(String label) {
    return switch (label) {
      'Interested' => Icons.trending_up_rounded,
      'Follow Up' => Icons.schedule_rounded,
      'Rejected' => Icons.block_rounded,
      'No Response' => Icons.phone_missed_rounded,
      _ => Icons.assignment_turned_in_rounded,
    };
  }

  Color _remarkColor(String label) {
    return switch (label) {
      'Interested' => kGreen,
      'Follow Up' => kOrange,
      'Rejected' => kRed,
      'No Response' => kPrimaryDark,
      _ => kPrimary,
    };
  }

  String _remarkDescription(String label) {
    return switch (label) {
      'Interested' => 'Customer spoke and is interested in the next step.',
      'Follow Up' =>
        'Customer asked for a scheduled follow-up to discuss later.',
      'Rejected' => 'Customer clearly said they are not interested.',
      'No Response' =>
        'No useful discussion happened or the customer did not respond.',
      _ => '',
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
    late final Widget screen;
    if (_isBootstrapping) {
      screen = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_isNetworkErrorVisible && _user == null) {
      screen = Scaffold(
        body: NetworkErrorView(
          message: _networkErrorMessage,
          onRetry: _recoverFromNetworkError,
          isRetrying: _isRecoveringFromNetworkError,
        ),
      );
    } else if (_user == null) {
      screen = _login();
    } else if (_isResolvingRequiredPermissions) {
      screen = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_needsRequiredPermissionGate) {
      screen = _requiredPermissionGatePage();
    } else {
      final pages = [
        _dashboard(),
        _leadList(),
        _learningCenter(),
        _staffProfilePage(),
      ];

      screen = Listener(
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
                      isRetrying: _isRecoveringFromNetworkError,
                    )
                  : pages[_tab],
            ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) {
              _registerInteraction(syncServer: false);
              _lastLoadedTab = value;
              setState(() => _tab = value);
              if (value == 3) {
                unawaited(_loadProfile(showLoader: _profile == null));
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

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleRootBackNavigation());
      },
      child: screen,
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
                    'Sign in with your assigned phone number or email and password.',
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
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number or Email',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: !_isLoginPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        onPressed: _isLoggingIn
                            ? null
                            : () {
                                setState(() {
                                  _isLoginPasswordVisible =
                                      !_isLoginPasswordVisible;
                                });
                              },
                        icon: Icon(
                          _isLoginPasswordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
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
                  const SizedBox.shrink(),
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
                        ? 'Complete the required training lessons to begin calling.'
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
          ] else if (_hasRecoverableCustomerCall) ...[
            _buildRecoverableCallBanner(),
            const SizedBox(height: 18),
          ],
          if (_summary.workingNow)
            ElevatedButton.icon(
              onPressed: _isSessionBusy ? null : () => _endWork(),
              style: ElevatedButton.styleFrom(backgroundColor: kRed),
              icon: const Icon(Icons.stop_circle),
              label: const Text('End Work'),
            )
          else
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  Icon(Icons.phone_in_talk, color: kPrimary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Work tracking starts automatically when you place a customer call.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
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
          const SizedBox(height: 12),
          InfoCard(
            title: 'Follow Ups',
            value: _isFollowupsLoading
                ? 'Loading...'
                : _followups.length.toString(),
            color: kOrange,
            icon: Icons.calendar_today_outlined,
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
            onPressed: _openFollowupQueuePage,
            icon: const Icon(Icons.calendar_today_outlined),
            label: const Text('Open Follow Ups'),
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
    if (_hasPendingCallStatus) {
      return _pendingCustomerCallPage();
    }

    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadDashboardData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Customers ready to call',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_leads.length} customer(s) are ready right now. Scheduled follow-ups appear here only on their requested date and time.',
            style: const TextStyle(fontSize: 16.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          if (_hasPendingCallStatus) ...[
            _buildPendingCallStatusBanner(),
            const SizedBox(height: 16),
          ] else if (_hasRecoverableCustomerCall) ...[
            _buildRecoverableCallBanner(),
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
                  color: _leads[i].isPriorityCallback
                      ? const Color(0xFFFFF6EA)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: _leads[i].isPriorityCallback
                      ? Border.all(color: kOrange.withValues(alpha: 0.32))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_leads[i].isPriorityCallback) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kOrange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Priority follow-up',
                          style: TextStyle(
                            color: kOrange,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                              if (_leads[i].callbackScheduleLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Follow Up: ${_leads[i].callbackScheduleLabel}',
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
          const SizedBox(height: 4),
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
                    Icon(Icons.manage_search, color: kPrimary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Previous customers',
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
                  'If a customer returns later, search here and move them back to Interested or schedule a Follow Up only when they ask for a timed discussion.',
                  style: TextStyle(fontSize: 15.5, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _openCustomerRecoveryPage,
                  icon: const Icon(Icons.person_search),
                  label: const Text('Find Previous Customer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecoverableCallBanner() {
    if (!_hasRecoverableCustomerCall) {
      return const SizedBox.shrink();
    }

    final leadSummary = _summary.recoverableCallLeadName.isNotEmpty
        ? _summary.recoverableCallLeadName
        : (_summary.recoverableCallLeadPhone.isNotEmpty
              ? _summary.recoverableCallLeadPhone
              : 'recent customer');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1A34B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFB96B17)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Call Sync Issue Detected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The recent customer call for $leadSummary still needs to be solved before another call can start.',
            style: const TextStyle(fontSize: 15.5, color: Color(0xFF6F4A16)),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_outlined, color: Color(0xFFB96B17)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'New customer calls stay locked until this sync issue is solved.',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6F4A16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => _solveSyncIssue(
              notice:
                  'Solve the current customer call sync issue before starting another one.',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB96B17),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.build_circle_outlined),
            label: Text(
              _isSyncingCallLog && _syncSolveCountdownSeconds != null
                  ? 'Solving ${_formatSecondsAsTimer(_syncSolveCountdownSeconds!)}'
                  : 'Solve Sync Issue',
            ),
          ),
          if (_isSyncingCallLog && _syncSolveCountdownSeconds != null) ...[
            const SizedBox(height: 10),
            Text(
              'Solving sync issue... ${_formatSecondsAsTimer(_syncSolveCountdownSeconds!)} remaining',
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF6F4A16),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSyncingCallLog ? null : _escapeSyncIssueCall,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Close Without Sync'),
          ),
        ],
      ),
    );
  }

  Widget _pendingCustomerCallPage() {
    final leadSummary = _pendingStatusLeadName.isNotEmpty
        ? _pendingStatusLeadName
        : 'Recent customer';
    final hasPhone = _pendingStatusLeadPhone.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () {
        _registerInteraction(syncServer: false);
        return _loadDashboardData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Pending customer call',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Finish the latest customer action before the lead list opens.',
            style: TextStyle(fontSize: 16.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phone_in_talk, color: kOrange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recent customer needs an update',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  leadSummary,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasPhone) ...[
                  const SizedBox(height: 6),
                  Text(
                    _pendingStatusLeadPhone,
                    style: const TextStyle(fontSize: 17, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'You can call this customer again or save the result now. The rest of the lead list stays locked until this is completed.',
                  style: TextStyle(fontSize: 15.5, color: Colors.black54),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _recoverPendingCallStatusPrompt,
                  icon: const Icon(Icons.assignment_turned_in),
                  label: const Text('Mark Call Result'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _retryPendingCustomerCall,
                  icon: const Icon(Icons.call),
                  label: const Text('Call Recent Customer'),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_clock, color: kPrimary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lead list is waiting',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Once the customer result is saved, the normal lead list will open automatically.',
                  style: TextStyle(fontSize: 15.5, color: Colors.black54),
                ),
              ],
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
    if (_hasActiveCustomerCall && _activeCallLeadId != _leads[index].id) {
      await _openCurrentCallScreen(
        notice:
            'Finish the current customer call before moving to another lead.',
      );
      return;
    }
    if (!await _ensurePendingCallStatusResolved(_leads[index])) {
      return;
    }
    await _showCallScreenForLead(_leads[index], index: index);
  }

  Widget _call(LeadItem? lead) {
    final hasActiveCallForLead = lead != null && _activeCallLeadId == lead.id;
    final hasPendingCallForLead =
        lead != null &&
        _hasPendingCallStatus &&
        _pendingStatusLeadId == lead.id;
    final hasRecoverableCallForLead =
        lead != null &&
        _hasRecoverableCustomerCall &&
        _summary.recoverableCallLeadId == lead.id;
    final callButtonLabel =
        hasActiveCallForLead || hasPendingCallForLead || hasRecoverableCallForLead
        ? 'Call Again'
        : 'Call';
    final syncSolveLabel =
        _isSyncingCallLog && _syncSolveCountdownSeconds != null
        ? 'Solving ${_formatSecondsAsTimer(_syncSolveCountdownSeconds!)}'
        : 'Solving...';

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
                if (lead.callbackScheduleLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Scheduled follow-up: ${lead.callbackScheduleLabel}',
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
                        onPressed: _isSyncingCallLog
                            ? null
                            : () => _startCall(selectedLead: lead),
                        icon: const Icon(Icons.phone_forwarded),
                        label: Text(callButtonLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: hasActiveCallForLead && !_isSyncingCallLog
                            ? () => _endCall()
                            : null,
                        style: ElevatedButton.styleFrom(backgroundColor: kRed),
                        icon: Icon(
                          _isSyncingCallLog
                              ? Icons.hourglass_top
                              : Icons.build_circle_outlined,
                        ),
                        label: Text(
                          _isSyncingCallLog
                              ? syncSolveLabel
                              : 'Solve Sync Issue',
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasActiveCallForLead) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6EC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF1A34B)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFB96B17),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isSyncingCallLog &&
                                    _syncSolveCountdownSeconds != null
                                ? 'Call sync issue is being solved. Estimated time remaining: ${_formatSecondsAsTimer(_syncSolveCountdownSeconds!)}.'
                                : 'Call sync issue is active. Tap "Solve Sync Issue" to finish this customer call before moving on.',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6F4A16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSyncingCallLog
                          ? null
                          : _escapeSyncIssueCall,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close Without Sync'),
                    ),
                  ),
                ],
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
                'After the call ends, mark one simple remark. Choose Follow Up only when the customer specifically asks for a scheduled follow-up. The next lead stays blocked until the remark is saved.',
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

    return DefaultTextStyle.merge(
      style: kMalayalamFallbackStyle,
      child: RefreshIndicator(
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
      ),
    );
  }

  Future<bool> _confirmUnscheduledFollowup({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
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
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Go Back'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<ShortCallDecision?> _showFollowupNoResponseDialog(
    LeadItem lead,
    int durationSeconds,
  ) async {
    final canCloseAsNoResponse = lead.canMarkFollowupNoResponse;
    final attemptNumber = lead.followupAttemptCount + 1;
    final message = durationSeconds <= 0
        ? canCloseAsNoResponse
              ? 'The customer did not attend this follow-up call. This is try $attemptNumber, so you can now move it to No Response.'
              : 'The customer did not attend this follow-up call. Save this try and call again until 3 proper tries are completed on different dates and times.'
        : canCloseAsNoResponse
        ? 'The follow-up call was too short to confirm a real discussion. This is try $attemptNumber, so you can now move it to No Response.'
        : 'The follow-up call was too short to confirm a real discussion. Save this try and call again until 3 proper tries are completed on different dates and times.';

    return await showDialog<ShortCallDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Follow Up Result'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Saved tries: ${lead.followupAttemptCount}/3',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (!canCloseAsNoResponse)
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(ShortCallDecision.markNoResponse),
                child: const Text('Save This Try'),
              ),
            if (!canCloseAsNoResponse)
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(ShortCallDecision.callAgain),
                child: const Text('Call Again'),
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(ShortCallDecision.markNoResponse),
                child: const Text('Mark No Response'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDocumentPreview({
    required File? selectedFile,
    required bool removeDocument,
    required String existingUrl,
    required String documentName,
    required String emptyLabel,
    required IconData icon,
    required String networkErrorLabel,
  }) {
    if (selectedFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(
          selectedFile,
          width: double.infinity,
          height: 190,
          fit: BoxFit.cover,
        ),
      );
    }

    if (removeDocument || existingUrl.isEmpty) {
      return Container(
        width: double.infinity,
        height: 190,
        decoration: BoxDecoration(
          color: kSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: kPrimaryDark),
            const SizedBox(height: 10),
            Text(
              emptyLabel,
              style: const TextStyle(
                fontSize: 15.5,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        existingUrl,
        headers: _apiClient.authenticatedDocumentHeaders,
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
            child: Center(
              child: Text(
                documentName.isNotEmpty
                    ? '$networkErrorLabel\n$documentName'
                    : networkErrorLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _staffProfilePage() {
    final profile = _profile;
    final salarySummary = profile?.salarySummary;
    final salaryHistory = profile?.salaryHistory ?? const <SalaryHistoryItem>[];
    final aadharWidget = _buildDocumentPreview(
      selectedFile: _selectedAadharPhoto,
      removeDocument: _removeAadharPhoto,
      existingUrl: profile?.aadharPhotoUrl ?? '',
      documentName: profile?.aadharPhotoName ?? '',
      emptyLabel: 'No Aadhaar photo added',
      icon: Icons.badge_outlined,
      networkErrorLabel: 'Could not load the saved Aadhaar photo.',
    );
    final passbookWidget = _buildDocumentPreview(
      selectedFile: _selectedPassbookPhoto,
      removeDocument: _removePassbookPhoto,
      existingUrl: profile?.passbookPhotoUrl ?? '',
      documentName: profile?.passbookPhotoName ?? '',
      emptyLabel: 'No passbook photo added',
      icon: Icons.menu_book_outlined,
      networkErrorLabel: 'Could not load the saved passbook photo.',
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
                ? 'View your account, payout, and work details here.'
                : 'Signed in as ${profile.name}. Review your account, salary, and work details here.',
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
                          value: profile?.isActive == true
                              ? 'Active'
                              : 'Inactive',
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openEditProfilePage,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openChangePasswordDialog,
                    icon: const Icon(Icons.lock_reset_outlined),
                    label: const Text('Change Password'),
                  ),
                ),
              ],
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
                    'Work summary',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'See your current worked hours and earned amount here, and open the full salary page when needed.',
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
                          value:
                              salarySummary?.totalWorkingHoursLabel ?? '0.0h',
                          color: kPrimary,
                          icon: Icons.timer_outlined,
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: InfoCard(
                          title: 'Earned',
                          value:
                              salarySummary?.totalEarnedAmountLabel ??
                              'Rs. 0.00',
                          color: kGreen,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openSalaryDetailsPage,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Salary Details'),
                    ),
                  ),
                  if (profile?.referralProgramEnabled == true) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Earn more?',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kPrimaryDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Refer a friend. When they complete ${profile!.referralRequiredHoursLabel}, you can earn ${profile.referralRewardAmountLabel}.',
                            style: const TextStyle(
                              fontSize: 14.5,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openReferralDialog,
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Refer a Friend'),
                            ),
                          ),
                        ],
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
                    'Account details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your main login and contact details are shown here.',
                    style: TextStyle(fontSize: 14.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  _buildProfileDetailRow(
                    icon: Icons.person_outline,
                    label: 'Full Name',
                    value: profile?.name.trim().isNotEmpty == true
                        ? profile!.name.trim()
                        : '--',
                  ),
                  const SizedBox(height: 12),
                  _buildProfileDetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone Number',
                    value: profile?.phone.trim().isNotEmpty == true
                        ? profile!.phone.trim()
                        : '--',
                  ),
                  const SizedBox(height: 12),
                  _buildProfileDetailRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: profile?.email.trim().isNotEmpty == true
                        ? profile!.email.trim()
                        : '--',
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
                    'Payout account',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your bank account details before salary is paid.',
                    style: TextStyle(fontSize: 14.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  _buildProfileDetailRow(
                    icon: Icons.account_circle_outlined,
                    label: 'Account Holder Name',
                    value: profile?.bankAccountName.trim().isNotEmpty == true
                        ? profile!.bankAccountName.trim()
                        : '--',
                  ),
                  const SizedBox(height: 12),
                  _buildProfileDetailRow(
                    icon: Icons.account_balance_outlined,
                    label: 'Bank Name',
                    value: profile?.bankName.trim().isNotEmpty == true
                        ? profile!.bankName.trim()
                        : '--',
                  ),
                  const SizedBox(height: 12),
                  _buildProfileDetailRow(
                    icon: Icons.numbers_outlined,
                    label: 'Account Number',
                    value: profile?.bankAccountNumber.trim().isNotEmpty == true
                        ? profile!.bankAccountNumber.trim()
                        : '--',
                  ),
                  const SizedBox(height: 12),
                  _buildProfileDetailRow(
                    icon: Icons.approval_outlined,
                    label: 'IFSC Code',
                    value: profile?.bankIfscCode.trim().isNotEmpty == true
                        ? profile!.bankIfscCode.trim()
                        : '--',
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
                    'Identity documents',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep your identity and payout proof ready for verification.',
                    style: TextStyle(fontSize: 14.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  _buildProfileDetailRow(
                    icon: Icons.badge_outlined,
                    label: 'Aadhaar Number',
                    value: profile?.aadharNumber.trim().isNotEmpty == true
                        ? profile!.aadharNumber.trim()
                        : '--',
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Aadhaar photo',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  aadharWidget,
                  const SizedBox(height: 22),
                  const Text(
                    'Passbook image',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  passbookWidget,
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
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout),
              style: OutlinedButton.styleFrom(foregroundColor: kRed),
              label: const Text('Logout'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: kPrimaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
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
        : (lesson.isMandatory ? 'Required' : 'Optional');

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
        const SnackBar(content: Text('This lesson link is not valid yet.')),
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
      appBar: AppBar(
        title: Text(widget.lesson.title, style: kMalayalamFallbackStyle),
      ),
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: kMalayalamFallbackStyle,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                widget.lesson.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  StatusPill(
                    label: widget.lesson.isCompleted
                        ? 'Completed'
                        : (widget.lesson.isMandatory ? 'Required' : 'Optional'),
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
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
          child: YoutubePlayer(controller: controller, aspectRatio: 16 / 9),
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
    this.isRetrying = false,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool isRetrying;

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
                        Text(
                          '2. Check that your internet service is available.',
                        ),
                        SizedBox(height: 6),
                        Text(
                          '3. Wait a moment. The app will restore automatically when the connection returns.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: isRetrying ? null : onRetry,
                    icon: isRetrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(isRetrying ? 'Reconnecting...' : 'Try Again'),
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

class RecoveredLeadResult {
  const RecoveredLeadResult({
    required this.leadId,
    required this.leadName,
    required this.statusLabel,
    this.callbackScheduleLabel = '',
  });

  final String leadId;
  final String leadName;
  final String statusLabel;
  final String callbackScheduleLabel;
}

class FollowupQueuePage extends StatefulWidget {
  const FollowupQueuePage({
    super.key,
    required this.apiClient,
    required this.onCall,
  });

  final ApiClient apiClient;
  final Future<void> Function(LeadItem lead) onCall;

  @override
  State<FollowupQueuePage> createState() => _FollowupQueuePageState();
}

class _FollowupQueuePageState extends State<FollowupQueuePage> {
  List<LeadItem> _rows = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFollowups();
  }

  Future<void> _loadFollowups({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final rows = await widget.apiClient.fetchFollowups();
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _isLoading = false;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow Ups')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadFollowups(showLoader: false),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Scheduled follow-ups',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _rows.isEmpty
                    ? 'No follow-ups are scheduled yet.'
                    : '${_rows.length} follow-up(s) are saved here. Scheduled ones are highlighted once their date starts.',
                style: const TextStyle(fontSize: 16.5, color: Colors.black54),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Text(
                    'No follow-ups are available right now.',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              else
                for (final lead in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: lead.isDueNow
                            ? const Color(0xFFFFF6EA)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: lead.isDueNow
                            ? Border.all(color: kOrange.withValues(alpha: 0.32))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: kSoft,
                                foregroundColor: kPrimary,
                                child: Text(lead.name.characters.first),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lead.name,
                                      style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      lead.phone,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill(
                                label: lead.isDueNow ? 'Due now' : 'Scheduled',
                              ),
                            ],
                          ),
                          if (lead.callbackScheduleLabel.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Follow Up: ${lead.callbackScheduleLabel}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: kPrimaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatusPill(
                                label: lead.isScheduledFollowup
                                    ? 'Scheduled'
                                    : 'No Schedule',
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
                                  'Tries: ${lead.followupAttemptCount}/3',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: kPrimaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (lead.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              lead.notes,
                              style: const TextStyle(fontSize: 15.5),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await widget.onCall(lead);
                                    if (!mounted) {
                                      return;
                                    }
                                    await _loadFollowups(showLoader: false);
                                  },
                                  icon: const Icon(Icons.phone_in_talk),
                                  label: Text(
                                    lead.isDueNow
                                        ? 'Call Highlighted Follow Up'
                                        : 'Open Follow Up',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class InterestedLeadCapturePage extends StatefulWidget {
  const InterestedLeadCapturePage({
    super.key,
    required this.lead,
    required this.onSubmit,
  });

  final LeadItem lead;
  final Future<bool> Function({
    required String customerName,
    required String customerPhone,
    required String productEnquired,
    required String enquiryNotes,
    required String preferredCallTime,
  })
  onSubmit;

  @override
  State<InterestedLeadCapturePage> createState() =>
      _InterestedLeadCapturePageState();
}

class _InterestedLeadCapturePageState extends State<InterestedLeadCapturePage> {
  late final TextEditingController _customerNameController;
  late final TextEditingController _customerPhoneController;
  final TextEditingController _productController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _preferredTimeController = TextEditingController(
    text: 'Now',
  );
  bool _isSaving = false;

  bool _validateRequiredFields() {
    final customerName = _customerNameController.text.trim();
    final customerPhone = _customerPhoneController.text.trim();
    final product = _productController.text.trim();
    final preferredTime = _preferredTimeController.text.trim();

    String? message;
    if (customerName.isEmpty) {
      message = 'Enter customer name.';
    } else if (customerPhone.isEmpty) {
      message = 'Enter customer number.';
    } else if (product.isEmpty) {
      message = 'Enter product enquiry details.';
    } else if (preferredTime.isEmpty) {
      message = 'Enter preferred call time.';
    }

    if (message == null) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
    return false;
  }

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(text: widget.lead.name);
    _customerPhoneController = TextEditingController(text: widget.lead.phone);
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _productController.dispose();
    _notesController.dispose();
    _preferredTimeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    if (!_validateRequiredFields()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final didSave = await widget.onSubmit(
      customerName: _customerNameController.text.trim(),
      customerPhone: _customerPhoneController.text.trim(),
      productEnquired: _productController.text.trim(),
      enquiryNotes: _notesController.text.trim(),
      preferredCallTime: _preferredTimeController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (didSave) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Interested Lead Details'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Save customer enquiry details',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete these details now so the admin can review this interested customer properly.',
                style: TextStyle(fontSize: 16.5, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      label: 'Name',
                      controller: _customerNameController,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      label: 'Number',
                      controller: _customerPhoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      label: 'Product Enquired',
                      controller: _productController,
                      hintText: 'Example: Personal loan',
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      label: 'Notes',
                      controller: _notesController,
                      hintText:
                          'Example: Wants to know the interest rate details',
                      minLines: 3,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      label: 'Time For Call',
                      controller: _preferredTimeController,
                      hintText: 'Example: Now',
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'Lead: ${widget.lead.name} (${widget.lead.phone})',
                        style: const TextStyle(
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Submit Interested Lead',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String hintText = '',
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}

class CustomerRecoveryPage extends StatefulWidget {
  const CustomerRecoveryPage({
    super.key,
    required this.staffName,
    required this.onSearch,
    required this.onRecover,
  });

  final String staffName;
  final Future<List<LeadItem>> Function(String query) onSearch;
  final Future<RecoveredLeadResult?> Function(
    LeadItem lead, {
    required String statusLabel,
    String callbackWindow,
    String callbackScheduleLabel,
    DateTime? callbackDate,
    InterestedLeadCaptureInput? interestedDetail,
  })
  onRecover;

  @override
  State<CustomerRecoveryPage> createState() => _CustomerRecoveryPageState();
}

class _CustomerRecoveryPageState extends State<CustomerRecoveryPage> {
  final TextEditingController _searchController = TextEditingController();
  List<LeadItem> _results = const [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _recoveringLeadId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadResults({String? query}) async {
    final searchText = (query ?? _searchController.text).trim();
    if (searchText.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _hasSearched = false;
        _results = const [];
      });
      return;
    }

    setState(() => _isLoading = true);
    final results = await widget.onSearch(searchText);
    if (!mounted) {
      return;
    }
    setState(() {
      _results = results;
      _isLoading = false;
      _hasSearched = true;
    });
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not contacted yet';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month/${value.year} $hour:$minute $meridiem';
  }

  String _callbackWindowValue(String label) {
    return switch (label) {
      'Noon' => 'noon',
      'Evening' => 'evening',
      'Night' => 'night',
      _ => '',
    };
  }

  Future<_RecoverySelection?> _pickRecoverySelection(LeadItem lead) async {
    const callbackChoices = ['Noon', 'Evening', 'Night'];
    var selectedStatus =
        lead.status == 'call_back' ||
            lead.status == 'interested' ||
            lead.statusLabel == 'Follow Up'
        ? 'Follow Up'
        : 'Interested';
    var selectedCallbackWindow = lead.callbackWindowLabel;
    DateTime? selectedCallbackDate = lead.callbackDate;

    return showDialog<_RecoverySelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Bring Customer Back'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lead.name} can be moved back into your active lead list. Choose Follow Up only if the customer requested a timed discussion.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ['Interested', 'Follow Up']
                        .map(
                          (label) => ChoiceChip(
                            selected: selectedStatus == label,
                            onSelected: (_) {
                              setDialogState(() {
                                selectedStatus = label;
                                if (label != 'Follow Up') {
                                  selectedCallbackWindow = '';
                                }
                              });
                            },
                            selectedColor: kPrimary,
                            backgroundColor: Colors.white,
                            label: Text(
                              label,
                              style: TextStyle(
                                color: selectedStatus == label
                                    ? Colors.white
                                    : kPrimaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (selectedStatus == 'Follow Up') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Choose the follow-up date and time',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate:
                              selectedCallbackDate ??
                              DateTime(now.year, now.month, now.day),
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 1, now.month, now.day),
                        );
                        if (picked == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedCallbackDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selectedCallbackDate != null
                                ? kPrimary
                                : Colors.black12,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              color: kPrimaryDark,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedCallbackDate == null
                                    ? 'Choose callback date'
                                    : _formatCallbackDateLabel(
                                        selectedCallbackDate!,
                                      ),
                                style: TextStyle(
                                  color: selectedCallbackDate == null
                                      ? Colors.black54
                                      : kPrimaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: callbackChoices
                          .map(
                            (label) => ChoiceChip(
                              selected: selectedCallbackWindow == label,
                              onSelected: (_) {
                                setDialogState(() {
                                  selectedCallbackWindow = label;
                                });
                              },
                              selectedColor: kPrimary,
                              backgroundColor: Colors.white,
                              label: Text(
                                label,
                                style: TextStyle(
                                  color: selectedCallbackWindow == label
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedStatus == 'Follow Up' &&
                          (selectedCallbackWindow.isEmpty ||
                              selectedCallbackDate == null)
                      ? null
                      : () {
                          final callbackDateLabel = selectedCallbackDate == null
                              ? ''
                              : _formatCallbackDateLabel(selectedCallbackDate!);
                          Navigator.of(dialogContext).pop(
                            _RecoverySelection(
                              statusLabel: selectedStatus,
                              callbackWindow: _callbackWindowValue(
                                selectedCallbackWindow,
                              ),
                              callbackWindowLabel: selectedCallbackWindow,
                              callbackDate: selectedCallbackDate,
                              callbackDateLabel: callbackDateLabel,
                              callbackScheduleLabel:
                                  _formatCallbackScheduleLabel(
                                    callbackDateLabel,
                                    selectedCallbackWindow,
                                  ),
                            ),
                          );
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleRecoverLead(LeadItem lead) async {
    final selection = await _pickRecoverySelection(lead);
    if (!mounted || selection == null) {
      return;
    }

    InterestedLeadCaptureInput? interestedDetail;
    if (selection.statusLabel == 'Interested') {
      interestedDetail = await _captureInterestedLeadDetail(lead);
      if (!mounted || interestedDetail == null) {
        return;
      }
    }

    setState(() => _recoveringLeadId = lead.id);
    final result = await widget.onRecover(
      lead,
      statusLabel: selection.statusLabel,
      callbackWindow: selection.callbackWindow,
      callbackScheduleLabel: selection.callbackScheduleLabel,
      callbackDate: selection.callbackDate,
      interestedDetail: interestedDetail,
    );
    if (!mounted) {
      return;
    }
    setState(() => _recoveringLeadId = null);
    if (result == null) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<InterestedLeadCaptureInput?> _captureInterestedLeadDetail(
    LeadItem lead,
  ) async {
    InterestedLeadCaptureInput? captured;
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InterestedLeadCapturePage(
          lead: lead,
          onSubmit:
              ({
                required customerName,
                required customerPhone,
                required productEnquired,
                required enquiryNotes,
                required preferredCallTime,
              }) async {
                captured = InterestedLeadCaptureInput(
                  customerName: customerName,
                  customerPhone: customerPhone,
                  productEnquired: productEnquired,
                  enquiryNotes: enquiryNotes,
                  preferredCallTime: preferredCallTime,
                );
                return true;
              },
        ),
      ),
    );
    if (submitted == true) {
      return captured;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final canSearch = query.isNotEmpty && !_isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Previous Customers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Find a customer you called earlier',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search with the customer name or phone number. If they later showed interest, you can move them back into Interested or schedule a Follow Up here.',
              style: TextStyle(fontSize: 16.5, color: Colors.black54),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) => _loadResults(query: value),
              decoration: InputDecoration(
                labelText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _hasSearched = false;
                            _results = const [];
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: canSearch ? () => _loadResults(query: query) : null,
              icon: const Icon(Icons.manage_search),
              label: const Text('Search Customer'),
            ),
            const SizedBox(height: 18),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_hasSearched)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Enter the customer phone number or name, then tap Search Customer.',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              )
            else if (_results.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'No previous customer matched your search.',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              )
            else
              ..._results.map((lead) {
                final isConverted = lead.status == 'converted';
                final ownerIsSomeoneElse =
                    lead.assignedToName.isNotEmpty &&
                    lead.assignedToName != widget.staffName;
                final isRecovering = _recoveringLeadId == lead.id;

                return Padding(
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
                              child: Text(lead.name.characters.first),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lead.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    lead.phone,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(label: lead.statusLabel),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Last contacted: ${_formatDateTime(lead.lastContactedAt)}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (lead.callbackScheduleLabel.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Current callback schedule: ${lead.callbackScheduleLabel}',
                            style: const TextStyle(
                              color: kPrimaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (ownerIsSomeoneElse) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Currently assigned to ${lead.assignedToName}.',
                            style: const TextStyle(
                              color: kOrange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (lead.notes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            lead.notes,
                            style: const TextStyle(fontSize: 15.5),
                          ),
                        ],
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: isConverted || isRecovering
                              ? null
                              : () => _handleRecoverLead(lead),
                          icon: isRecovering
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(
                            isConverted
                                ? 'Already Converted'
                                : (lead.isRecoveryLead
                                      ? 'Add Follow Up'
                                      : 'Update Follow Up'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _RecoverySelection {
  const _RecoverySelection({
    required this.statusLabel,
    this.callbackWindow = '',
    this.callbackWindowLabel = '',
    this.callbackDate,
    this.callbackDateLabel = '',
    this.callbackScheduleLabel = '',
  });

  final String statusLabel;
  final String callbackWindow;
  final String callbackWindowLabel;
  final DateTime? callbackDate;
  final String callbackDateLabel;
  final String callbackScheduleLabel;
}

class InterestedLeadCaptureInput {
  const InterestedLeadCaptureInput({
    required this.customerName,
    required this.customerPhone,
    required this.productEnquired,
    required this.enquiryNotes,
    required this.preferredCallTime,
  });

  final String customerName;
  final String customerPhone;
  final String productEnquired;
  final String enquiryNotes;
  final String preferredCallTime;
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

class _CallRemarkDialogResult {
  const _CallRemarkDialogResult({
    this.statusLabel = '',
    this.callbackWindow = '',
    this.callbackWindowLabel = '',
    this.callbackDate,
    this.callbackDateLabel = '',
    this.callbackScheduleLabel = '',
    this.retryCall = false,
  });

  final String statusLabel;
  final String callbackWindow;
  final String callbackWindowLabel;
  final DateTime? callbackDate;
  final String callbackDateLabel;
  final String callbackScheduleLabel;
  final bool retryCall;
}

enum ShortCallDecision { markNoResponse, markRejected, callAgain }

enum _PendingCallAction { markStatus, callRecent, cancel }

enum _AppUpdateAction { download, install, later }

enum _PermissionDialogAction { allowNow, openSettings }

enum _ProfileDocument { aadhar, passbook }

class StaffSalaryDetailsPage extends StatefulWidget {
  const StaffSalaryDetailsPage({
    super.key,
    required this.apiClient,
    this.initialSummary,
  });

  final ApiClient apiClient;
  final SalarySummary? initialSummary;

  @override
  State<StaffSalaryDetailsPage> createState() => _StaffSalaryDetailsPageState();
}

class _StaffSalaryDetailsPageState extends State<StaffSalaryDetailsPage> {
  StaffSalaryDetails? _details;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSalaryDetails());
  }

  Future<void> _loadSalaryDetails({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }
    try {
      final details = await widget.apiClient.fetchStaffSalaryDetails();
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
        _errorMessage = '';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final summary = details?.summary;
    final fallbackSummary = widget.initialSummary;

    return Scaffold(
      appBar: AppBar(title: const Text('Salary Details')),
      body: RefreshIndicator(
        onRefresh: () => _loadSalaryDetails(showLoader: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Salary Details',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              summary == null
                  ? 'Review your earning pattern, payout schedule, and credited payment history here.'
                  : 'Your earnings are tracked from worked hours and shown according to your payout setup.',
              style: const TextStyle(fontSize: 16.5, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (_isLoading && details == null)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage.isNotEmpty && details == null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Could not load salary details right now.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loadSalaryDetails,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
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
                      'Current progress',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      details == null
                          ? 'This page shows your current earning, unpaid balance, and released salary history.'
                          : 'This page shows your running-cycle earning, unpaid balance, and released salary details.',
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
                            value:
                                details?.currentCycle.hoursLabel ??
                                fallbackSummary?.totalWorkingHoursLabel ??
                                '0.0h',
                            color: kPrimary,
                            icon: Icons.timer_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: InfoCard(
                            title: 'Earned',
                            value:
                                details?.currentCycle.earnedTotalLabel ??
                                fallbackSummary?.totalEarnedAmountLabel ??
                                'Rs. 0.00',
                            color: kGreen,
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: InfoCard(
                            title: 'Pending',
                            value:
                                details?.currentCycle.balanceLabel ??
                                'Rs. 0.00',
                            color: kOrange,
                            icon: Icons.pending_actions_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: InfoCard(
                            title: 'Released',
                            value:
                                details?.currentCycle.paidTotalLabel ??
                                fallbackSummary?.totalPaidAmountLabel ??
                                'Rs. 0.00',
                            color: kPrimaryDark,
                            icon: Icons.payments_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (summary != null)
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
                        'Payout overview',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _SalaryMetaChip(
                            icon: Icons.schedule_outlined,
                            label: summary.compensationTypeLabel,
                          ),
                          _SalaryMetaChip(
                            icon: Icons.calendar_today_outlined,
                            label: summary.payoutScheduleLabel,
                          ),
                          _SalaryMetaChip(
                            icon: Icons.payments_outlined,
                            label: 'Hourly ${summary.hourlyRateLabel}',
                          ),
                          _SalaryMetaChip(
                            icon: Icons.phone_forwarded_outlined,
                            label: 'Call ${summary.callRateLabel}',
                          ),
                          _SalaryMetaChip(
                            icon: Icons.workspace_premium_outlined,
                            label:
                                'Success reward ${summary.bonusPerConversionLabel}',
                          ),
                          _SalaryMetaChip(
                            icon: Icons.flag_outlined,
                            label: summary.targetHoursLabel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (details != null) ...[
                const SizedBox(height: 16),
                _SalaryDetailCard(block: details.currentCycle),
                const SizedBox(height: 16),
                _SalaryDetailCard(block: details.previousMonth),
                if (details.pattern.rows.isNotEmpty) ...[
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
                        Text(
                          details.pattern.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          details.pattern.subtitle,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final row in details.pattern.rows) ...[
                          _SalaryPatternCard(row: row),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
                if (details.referralSummary.enabled) ...[
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
                          'Referral tracker',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Track each referred person here from submission to completed reward.',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _SalaryMetaChip(
                              icon: Icons.timer_outlined,
                              label:
                                  'Target ${details.referralSummary.requiredHoursLabel}',
                            ),
                            _SalaryMetaChip(
                              icon: Icons.card_giftcard_outlined,
                              label:
                                  'Reward ${details.referralSummary.rewardAmountLabel}',
                            ),
                            _SalaryMetaChip(
                              icon: Icons.group_add_outlined,
                              label:
                                  '${details.referralSummary.submittedCount} submitted',
                            ),
                            _SalaryMetaChip(
                              icon: Icons.work_history_outlined,
                              label:
                                  '${details.referralSummary.startedWorkingCount} working',
                            ),
                            _SalaryMetaChip(
                              icon: Icons.verified_outlined,
                              label:
                                  '${details.referralSummary.completedCount} completed',
                            ),
                            _SalaryMetaChip(
                              icon: Icons.pending_actions_outlined,
                              label:
                                  '${details.referralSummary.pendingCount} reward pending',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (details.referralTracking.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kSoft,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              'No referral entries have been added yet.',
                              style: TextStyle(
                                color: kPrimaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (final item in details.referralTracking) ...[
                                _ReferralTrackingCard(item: item),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        if (details.referralHistory.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const Text(
                            'Reward history',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Column(
                            children: [
                              for (final reward in details.referralHistory) ...[
                                _ReferralRewardHistoryCard(reward: reward),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
                        'Payment history',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Review earlier credited payments and the periods they covered.',
                        style: TextStyle(fontSize: 14.5, color: Colors.black54),
                      ),
                      const SizedBox(height: 14),
                      if (details.paymentHistory.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kSoft,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'No credited payment history has been added yet.',
                            style: TextStyle(
                              color: kPrimaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (final payment in details.paymentHistory) ...[
                              _SalaryPaymentHistoryCard(payment: payment),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SalaryMetaChip extends StatelessWidget {
  const _SalaryMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: kPrimaryDark),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: kPrimaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryDetailCard extends StatelessWidget {
  const _SalaryDetailCard({required this.block});

  final SalaryDetailBlock block;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (block.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              block.subtitle,
              style: const TextStyle(fontSize: 14.5, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              block.periodLabel,
              style: const TextStyle(
                color: kPrimaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SalaryMetricRow(label: 'Worked hours', value: block.hoursLabel),
          _SalaryMetricRow(
            label: 'Earned amount',
            value: block.earnedTotalLabel,
          ),
          _SalaryMetricRow(
            label: 'Released amount',
            value: block.paidTotalLabel,
          ),
          _SalaryMetricRow(label: 'Pending balance', value: block.balanceLabel),
          const Divider(height: 28),
          _SalaryMetricRow(label: 'Hourly earnings', value: block.basePayLabel),
          _SalaryMetricRow(
            label: 'Successful lead rewards',
            value: block.conversionRewardLabel,
          ),
          _SalaryMetricRow(
            label: 'Hourly bonus rewards',
            value: block.hourlyCallBonusLabel,
          ),
          _SalaryMetricRow(
            label: 'Total extra earnings',
            value: block.bonusEarningsLabel,
          ),
          if (block.conversionRewardRows.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Rewarded successful leads (${block.convertedLeadCount})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kPrimaryDark,
              ),
            ),
            const SizedBox(height: 12),
            for (final reward in block.conversionRewardRows) ...[
              _ConvertedLeadRewardCard(reward: reward),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _SalaryMetricRow extends StatelessWidget {
  const _SalaryMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14.5, color: Colors.black54),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14.5,
              color: kPrimaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryPatternCard extends StatelessWidget {
  const _SalaryPatternCard({required this.row});

  final SalaryPatternRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
                  row.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
              ),
              Text(
                row.earnedTotalLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            row.periodLabel,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Text(
            'Worked ${row.hoursLabel} • Released ${row.paidTotalLabel} • Pending ${row.balanceLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _ConvertedLeadRewardCard extends StatelessWidget {
  const _ConvertedLeadRewardCard({required this.reward});

  final ConversionRewardItem reward;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reward.leadName,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
              ),
              Text(
                reward.rewardAmountLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            reward.leadPhone,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            'Reward added on ${reward.convertedAtLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _SalaryPaymentHistoryCard extends StatelessWidget {
  const _SalaryPaymentHistoryCard({required this.payment});

  final SalaryPaymentHistoryItem payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
                  payment.paidAmountLabel,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  payment.paymentKindLabel,
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
            payment.periodLabel,
            style: const TextStyle(
              fontSize: 14.5,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Paid on ${payment.paidAtLabel} • ${payment.paymentMethodLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            'Worked ${payment.totalHoursLabel} • Earned ${payment.finalSalaryLabel} • ${payment.payoutCycleLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          if (payment.paymentReference.isNotEmpty &&
              payment.paymentReference != '--') ...[
            const SizedBox(height: 6),
            Text(
              'Transaction ID: ${payment.paymentReference}',
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (payment.paymentNote.isNotEmpty &&
              payment.paymentNote != '--') ...[
            const SizedBox(height: 6),
            Text(
              payment.paymentNote,
              style: const TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferralTrackingCard extends StatelessWidget {
  const _ReferralTrackingCard({required this.item});

  final ReferralTrackingItem item;

  @override
  Widget build(BuildContext context) {
    final stageColor = switch (item.workflowStage) {
      'completed' => kGreen,
      'started_working' => kOrange,
      'joined' => kPrimary,
      _ => kPrimaryDark,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.referredName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: kPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.referredPhone,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.workflowStageLabel,
                  style: TextStyle(
                    color: stageColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.progressLabel,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          if (item.joinedStaffName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Joined as ${item.joinedStaffName}',
              style: const TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Submitted on ${item.createdAtLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          if (item.rewardAmountLabel.isNotEmpty &&
              item.rewardAmountLabel != '--') ...[
            const SizedBox(height: 6),
            Text(
              'Reward ${item.rewardAmountLabel} • ${item.rewardStatusLabel}',
              style: const TextStyle(
                fontSize: 13.5,
                color: kPrimaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (item.rewardStatusLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.rewardStatusLabel,
              style: const TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferralRewardHistoryCard extends StatelessWidget {
  const _ReferralRewardHistoryCard({required this.reward});

  final ReferralRewardHistoryItem reward;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
                  reward.rewardAmountLabel,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reward.isPaid ? 'Paid' : 'Pending',
                  style: TextStyle(
                    color: reward.isPaid ? kGreen : kPrimaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reward.referredStaffName,
            style: const TextStyle(
              fontSize: 14.5,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reward.referredStaffPhone,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            'Qualified after ${reward.requiredHoursLabel} on ${reward.qualifiedAtLabel}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          if (reward.isPaid) ...[
            const SizedBox(height: 6),
            Text(
              'Paid on ${reward.paidAtLabel} • ${reward.paymentMethodLabel}',
              style: const TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
          ],
          if (reward.paymentReference.isNotEmpty &&
              reward.paymentReference != '--') ...[
            const SizedBox(height: 6),
            Text(
              'Transaction ID: ${reward.paymentReference}',
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (reward.paymentNote.isNotEmpty && reward.paymentNote != '--') ...[
            const SizedBox(height: 6),
            Text(
              reward.paymentNote,
              style: const TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
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
              Align(
                alignment: centered ? Alignment.center : Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: centered ? Alignment.center : Alignment.centerLeft,
                  child: Text(
                    kBrandName,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: centered ? Alignment.center : Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: centered ? Alignment.center : Alignment.centerLeft,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: subtitleSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
      'Follow Up' => kOrange,
      'No Response' => kRed,
      'Converted' => kGreen,
      'Rejected' => kRed,
      'Completed' => kGreen,
      'Required' => kOrange,
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
