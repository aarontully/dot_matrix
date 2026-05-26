import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../models/device_session_info.dart';

Future<DeviceSessionInfo?> chooseDeviceVerificationTarget({
  required SettingsController settingsController,
}) async {
  final sessions = await settingsController.fetchVerificationTargetSessions();
  if (sessions.isEmpty) {
    return null;
  }
  if (sessions.length == 1) {
    return sessions.first;
  }

  return Get.dialog<DeviceSessionInfo>(
    DeviceVerificationTargetDialog(sessions: sessions),
  );
}

class DeviceVerificationTargetDialog extends StatelessWidget {
  const DeviceVerificationTargetDialog({super.key, required this.sessions});

  final List<DeviceSessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a device'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick another signed-in session to approve this verification. Verified devices are shown first.',
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final title = session.displayName?.trim().isNotEmpty == true
                      ? session.displayName!.trim()
                      : session.deviceId;
                  final subtitle =
                      session.displayName?.trim().isNotEmpty == true
                      ? '${session.deviceId} • ${_formatSessionLastSeen(session.lastSeenTs)}'
                      : _formatSessionLastSeen(session.lastSeenTs);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      session.verification == DeviceVerificationLabel.verified
                          ? Icons.verified_user_outlined
                          : Icons.devices_other_outlined,
                    ),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    trailing: _verificationChip(context, session.verification),
                    onTap: () => Get.back(result: session),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back<DeviceSessionInfo?>(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _verificationChip(
    BuildContext context,
    DeviceVerificationLabel verification,
  ) {
    final cs = Theme.of(context).colorScheme;
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (verification) {
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
      const days = [
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
