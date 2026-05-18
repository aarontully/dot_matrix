import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../models/device_session_info.dart';
import '../theme/app_theme.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final int _refreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    final theme = Theme.of(context);
    final isDark = Get.isDarkMode;
    final scaffoldColor = isDark
        ? AppTheme.darkBackground
        : AppTheme.settingsBackground;
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: scaffoldColor,
      appBar: AppBar(
        leadingWidth: 40,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appBarForeground, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Sessions'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionCard(
                title: 'Devices',
                subtitle:
                    'Devices signed in to your Matrix account. Verification reflects cross-signing when encryption is enabled.',
                child: FutureBuilder<List<DeviceSessionInfo>>(
                  key: ValueKey(_refreshToken),
                  future: settingsController.fetchDeviceSessions(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Could not load devices: ${snapshot.error}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      );
                    }
                    final sessions = snapshot.data ?? const [];
                    if (sessions.isEmpty) {
                      return Text(
                        'No sessions returned.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < sessions.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          _buildSessionTile(context, sessions[i]),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = Get.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildSessionTile(BuildContext context, DeviceSessionInfo session) {
    final cs = Theme.of(context).colorScheme;
    final title = session.displayName?.trim().isNotEmpty == true
        ? session.displayName!.trim()
        : session.deviceId;
    final subtitle = session.displayName?.trim().isNotEmpty == true
        ? session.deviceId
        : _formatSessionLastSeen(session.lastSeenTs);
    final chip = _sessionVerificationChip(context, session.verification);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            session.isCurrentDevice ? Icons.smartphone : Icons.devices_other,
            color: cs.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (session.isCurrentDevice)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'This device',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                if (session.displayName?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatSessionLastSeen(session.lastSeenTs),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                chip,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionVerificationChip(
    BuildContext context,
    DeviceVerificationLabel v,
  ) {
    final cs = Theme.of(context).colorScheme;
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (v) {
      case DeviceVerificationLabel.verified:
        label = 'Verified';
        bg = const Color(0xFFE8F7EC);
        fg = const Color(0xFF1B8D4B);
        break;
      case DeviceVerificationLabel.unverified:
        label = 'Not verified';
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case DeviceVerificationLabel.blocked:
        label = 'Blocked';
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case DeviceVerificationLabel.unknown:
        label = 'Keys unknown';
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  String _formatSessionLastSeen(int? lastSeenTs) {
    if (lastSeenTs == null) {
      return 'Last active unknown';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSeenTs);
    return 'Last active ${_formatTimestamp(dt)}';
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(timestamp, now)) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    if (now.difference(timestamp).inDays < 7) {
      final days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return days[timestamp.weekday - 1];
    }
    return '${timestamp.day} ${_monthName(timestamp.month)}';
  }

  String _monthName(int month) {
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
    return months[month - 1];
  }
}
