import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:matrix/encryption.dart';

import '../controllers/settings_controller.dart';
import '../models/settings_state.dart';
import '../theme/app_theme.dart';
import '../widgets/device_verification_dialog.dart';
import '../widgets/dot_matrix_loader.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, this.launchedFromOnboarding = false});

  final bool launchedFromOnboarding;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final _recoveryController = TextEditingController();

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
        title: Text(
          widget.launchedFromOnboarding ? 'Set Up This Device' : 'Device Setup',
        ),
        actions: [
          if (widget.launchedFromOnboarding)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
        ],
      ),
      body: settingsController.obx(
        (settings) {
          if (settings == null) return const SizedBox.shrink();
          return _buildContent(context, settings);
        },
        onLoading: const Center(child: DotMatrixLoader()),
        onError: (error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'We could not load device setup.\n$error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => settingsController.refreshSettings(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SettingsState settings) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.launchedFromOnboarding)
              _buildIntroCard(settings, cs)
            else
              _buildSetupSummaryCard(settings, cs),
            const SizedBox(height: 16),
            _buildStepCard(
              context,
              icon: Icons.lock_open_outlined,
              title: 'Restore encrypted history',
              isComplete: settings.encryptedHistoryReady,
              accentColor: const Color(0xFF2B7FFF),
              description: settings.encryptedHistoryReady
                  ? 'Older encrypted messages are ready on this device.'
                  : settings.secureBackupAvailable
                  ? 'Enter your recovery key or backup passphrase to unlock older encrypted chats.'
                  : 'Secure Backup is not available for this account right now. You can still verify another signed-in device to request keys.',
              child: settings.encryptedHistoryReady
                  ? const SizedBox.shrink()
                  : settings.secureBackupAvailable
                  ? Column(
                      children: [
                        TextField(
                          controller: _recoveryController,
                          enabled: !settings.isRestoringEncryption,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Recovery key or passphrase',
                            hintText: 'Paste your Matrix recovery key',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: settings.isRestoringEncryption
                                ? null
                                : _restoreEncryptedHistory,
                            icon: const Icon(Icons.key_outlined),
                            label: Text(
                              settings.isRestoringEncryption
                                  ? 'Restoring...'
                                  : 'Restore now',
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildInfoPill(
                      cs,
                      Icons.info_outline,
                      'Use verification below or open another trusted Matrix app already signed into this account.',
                    ),
            ),
            const SizedBox(height: 16),
            _buildStepCard(
              context,
              icon: Icons.verified_user_outlined,
              title: 'Verify this device',
              isComplete: settings.isCurrentDeviceVerified,
              accentColor: const Color(0xFF00A37A),
              description: settings.isCurrentDeviceVerified
                  ? 'This device is trusted and can smoothly access encrypted history.'
                  : settings.hasOtherDeviceSessions
                  ? 'Confirm this device from another signed-in Matrix app to make encrypted history sharing smoother.'
                  : 'No other signed-in devices were found yet. Sign into another Matrix app first if you want to verify this device.',
              child: settings.isCurrentDeviceVerified
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        if (!settings.hasOtherDeviceSessions)
                          _buildInfoPill(
                            cs,
                            Icons.devices_outlined,
                            'No other sessions are available to verify against yet.',
                          )
                        else if (!settings.hasOtherVerifiedDeviceSessions)
                          _buildInfoPill(
                            cs,
                            Icons.info_outline,
                            'Your other session can still accept verification. Keep it open while you approve the emoji check.',
                          ),
                        if (settings.hasOtherDeviceSessions) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _verifyDevice,
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Verify now'),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _buildStatusSnapshot(settings, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard(SettingsState settings, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.onPrimaryContainer.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Finish setting up this device',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.needsDeviceSetup
                ? 'We will help this device read older encrypted chats and become trusted.'
                : 'This device is already ready for encrypted chats.',
            style: TextStyle(
              color: cs.onPrimaryContainer.withValues(alpha: 0.86),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _buildProgressRow(settings, cs.onPrimaryContainer),
        ],
      ),
    );
  }

  Widget _buildSetupSummaryCard(SettingsState settings, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD7AC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: Color(0xFFC96A12)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set up this device',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            settings.needsDeviceSetup
                ? 'Use this guide to finish recovery and trust setup in one place.'
                : 'Everything needed for encrypted chats is already ready on this device.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.78),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _buildProgressRow(settings, cs.onSurface),
        ],
      ),
    );
  }

  Widget _buildProgressRow(SettingsState settings, Color progressColor) {
    final total = settings.totalDeviceSetupSteps;
    final completed = settings.completedDeviceSetupSteps;
    final progress = total == 0 ? 1.0 : completed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'Encryption is unavailable on this device.'
              : completed == total
              ? 'All setup steps are complete.'
              : '$completed of $total steps complete',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: progressColor,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: progressColor.withValues(alpha: 0.14),
          ),
        ),
      ],
    );
  }

  Widget _buildStepCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isComplete,
    required Color accentColor,
    required String description,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isComplete
              ? accentColor.withValues(alpha: 0.28)
              : cs.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildStateChip(isComplete, accentColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.78),
            ),
          ),
          if (!isComplete) ...[const SizedBox(height: 14), child],
        ],
      ),
    );
  }

  Widget _buildStateChip(bool isComplete, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isComplete
            ? accentColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isComplete
              ? accentColor.withValues(alpha: 0.32)
              : Colors.black12,
        ),
      ),
      child: Text(
        isComplete ? 'Done' : 'Needed',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isComplete ? accentColor : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildInfoPill(ColorScheme cs, IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSnapshot(SettingsState settings, ColorScheme cs) {
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
            Expanded(child: Text(value, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status snapshot',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          row(
            'Secure backup',
            settings.secureBackupAvailable ? 'Available' : 'Not configured',
          ),
          row(
            'Room-key backup',
            settings.keyBackupEnabled ? 'Available' : 'Not found',
          ),
          row(
            'History access',
            settings.encryptedHistoryReady
                ? 'Ready on this device'
                : 'Needs recovery',
          ),
          row(
            'This device',
            settings.isCurrentDeviceVerified
                ? 'Verified'
                : 'Needs verification',
          ),
        ],
      ),
    );
  }

  Future<void> _restoreEncryptedHistory() async {
    try {
      final message = await Get.find<SettingsController>()
          .restoreEncryptedHistory(_recoveryController.text);
      _recoveryController.clear();
      if (!mounted) return;
      Get.snackbar('', message, snackPosition: SnackPosition.BOTTOM);
      await _maybeFinishIfComplete();
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', error.toString());
    }
  }

  Future<void> _verifyDevice() async {
    try {
      final request = await Get.find<SettingsController>()
          .startDeviceVerification();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeviceVerificationDialog(request: request),
      );
      if (!mounted) return;
      if (request.state == KeyVerificationState.done) {
        await Get.find<SettingsController>().refreshAfterDeviceVerification();
        await _maybeFinishIfComplete();
      }
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', error.toString());
    }
  }

  Future<void> _maybeFinishIfComplete() async {
    final settingsController = Get.find<SettingsController>();
    await settingsController.refreshSettings();
    final refreshed = settingsController.state;
    if (!mounted || refreshed == null) return;

    if (!refreshed.needsDeviceSetup) {
      Get.snackbar(
        '',
        'This device is fully set up for encrypted chats.',
        snackPosition: SnackPosition.BOTTOM,
      );
      if (widget.launchedFromOnboarding) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _recoveryController.dispose();
    super.dispose();
  }
}
