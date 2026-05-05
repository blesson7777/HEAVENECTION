import 'dart:async';

import 'package:flutter/material.dart';

import 'app_models.dart';

class AppNotificationBannerData {
  const AppNotificationBannerData({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.color,
    required this.icon,
    required this.allowManualClose,
    required this.autoDismissSeconds,
    required this.isRemote,
  });

  final String id;
  final String title;
  final String message;
  final String severity;
  final Color color;
  final IconData icon;
  final bool allowManualClose;
  final int autoDismissSeconds;
  final bool isRemote;
}

class AppNotificationOverlayController {
  AppNotificationOverlayController._();

  static final AppNotificationOverlayController instance =
      AppNotificationOverlayController._();

  final ValueNotifier<List<AppNotificationBannerData>> notices =
      ValueNotifier<List<AppNotificationBannerData>>(const []);
  final Map<String, Timer> _timers = <String, Timer>{};
  final Set<String> _dismissedRemoteIds = <String>{};

  void syncRemote(List<AppNotificationItem> items) {
    final activeIds =
        items.map((item) => item.id).where((id) => id.trim().isNotEmpty).toSet();
    _dismissedRemoteIds.removeWhere((id) => !activeIds.contains(id));

    final localNotices = notices.value.where((item) => !item.isRemote).toList();
    final remoteNotices = items
        .where(
          (item) =>
              item.id.trim().isNotEmpty && !_dismissedRemoteIds.contains(item.id),
        )
        .map(_remoteBannerFromItem)
        .toList();

    final combined = <AppNotificationBannerData>[
      ...remoteNotices,
      ...localNotices,
    ];
    notices.value = combined;

    final visibleIds = combined.map((item) => item.id).toSet();
    final timerIds = _timers.keys.toList(growable: false);
    for (final id in timerIds) {
      if (!visibleIds.contains(id)) {
        _timers.remove(id)?.cancel();
      }
    }
    for (final item in combined) {
      _scheduleAutoDismiss(item);
    }
  }

  void showLocal({
    required String message,
    String title = '',
    String severity = 'normal',
    bool allowManualClose = true,
    int autoDismissSeconds = 5,
  }) {
    final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final banner = _localBanner(
      id: id,
      title: title,
      message: message,
      severity: severity,
      allowManualClose: allowManualClose,
      autoDismissSeconds: autoDismissSeconds,
    );
    notices.value = <AppNotificationBannerData>[
      banner,
      ...notices.value.where((item) => item.id != id),
    ];
    _scheduleAutoDismiss(banner);
  }

  void dismiss(String id, {bool rememberRemote = true}) {
    final existing = notices.value.cast<AppNotificationBannerData?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (existing != null && existing.isRemote && rememberRemote) {
      _dismissedRemoteIds.add(id);
    }
    _timers.remove(id)?.cancel();
    notices.value = notices.value.where((item) => item.id != id).toList();
  }

  void clearAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _dismissedRemoteIds.clear();
    notices.value = const [];
  }

  AppNotificationBannerData _remoteBannerFromItem(AppNotificationItem item) {
    final palette = _paletteForSeverity(item.severity);
    return AppNotificationBannerData(
      id: item.id,
      title: item.title,
      message: item.message,
      severity: item.severity,
      color: palette.color,
      icon: palette.icon,
      allowManualClose: item.allowManualClose,
      autoDismissSeconds: item.autoDismissSeconds <= 0
          ? 6
          : item.autoDismissSeconds,
      isRemote: true,
    );
  }

  AppNotificationBannerData _localBanner({
    required String id,
    required String title,
    required String message,
    required String severity,
    required bool allowManualClose,
    required int autoDismissSeconds,
  }) {
    final palette = _paletteForSeverity(severity);
    return AppNotificationBannerData(
      id: id,
      title: title,
      message: message,
      severity: severity,
      color: palette.color,
      icon: palette.icon,
      allowManualClose: allowManualClose,
      autoDismissSeconds: autoDismissSeconds <= 0 ? 5 : autoDismissSeconds,
      isRemote: false,
    );
  }

  void _scheduleAutoDismiss(AppNotificationBannerData item) {
    _timers[item.id]?.cancel();
    if (item.autoDismissSeconds <= 0) {
      return;
    }
    _timers[item.id] = Timer(
      Duration(seconds: item.autoDismissSeconds),
      () => dismiss(item.id),
    );
  }

  _NotificationPalette _paletteForSeverity(String severity) {
    switch (severity.trim().toLowerCase()) {
      case 'critical':
        return const _NotificationPalette(
          color: Color(0xFFD84E58),
          icon: Icons.warning_rounded,
        );
      case 'warning':
        return const _NotificationPalette(
          color: Color(0xFFF0B63F),
          icon: Icons.warning_amber_rounded,
        );
      case 'good':
        return const _NotificationPalette(
          color: Color(0xFF2D9D68),
          icon: Icons.check_circle_rounded,
        );
      default:
        return const _NotificationPalette(
          color: Color(0xFF4D5C90),
          icon: Icons.info_rounded,
        );
    }
  }
}

class AppNotificationOverlay extends StatelessWidget {
  const AppNotificationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppNotificationBannerData>>(
      valueListenable: AppNotificationOverlayController.instance.notices,
      builder: (context, notices, child) {
        if (notices.isEmpty) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: false,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: notices
                        .map((notice) => _NotificationBannerCard(notice: notice))
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationBannerCard extends StatelessWidget {
  const _NotificationBannerCard({required this.notice});

  final AppNotificationBannerData notice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        elevation: 14,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: notice.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: notice.color.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(notice.icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (notice.title.trim().isNotEmpty) ...[
                          Text(
                            notice.title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          notice.message,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (notice.allowManualClose) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () =>
                        AppNotificationOverlayController.instance.dismiss(
                          notice.id,
                        ),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    splashRadius: 18,
                    tooltip: 'Close',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationPalette {
  const _NotificationPalette({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}
