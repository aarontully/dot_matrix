import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/settings_state.dart';
import '../theme/app_theme.dart';
import '../widgets/device_verification_dialog.dart';

class EncryptionSettingsScreen extends StatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  State<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState extends State<EncryptionSettingsScreen> {
  final _encryptionRecoveryController = TextEditingController();

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
        title: const Text('Encryption'),
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
                  'We could not load your settings.\n$error',
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settings.encryptionEnabled && !settings.encryptedHistoryReady) ...[
              _buildRecoveryNudge(settings),
              const SizedBox(height: 16),
            ],
            _buildSectionCard(
              title: 'Status',
              subtitle: 'Secure Backup and room keys on this device.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    'Secure backup',
                    settings.secureBackupAvailable
                        ? 'Available'
                        : 'Not configured',
                  ),
                  _buildInfoRow(
                    'Room-key backup',
                    settings.keyBackupEnabled ? 'Available' : 'Not found',
                  ),
                  _buildInfoRow(
                    'History access',
                    settings.encryptedHistoryReady
                        ? 'Ready on this device'
                        : 'Needs recovery',
                  ),
                  _buildInfoRow(
                    'Encryption',
                    settings.encryptionEnabled ? 'Enabled' : 'Unavailable',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Message Encryption',
              subtitle:
                  'End-to-end encryption protects your messages so only you and the recipient can read them.',
              child: SwitchListTile.adaptive(
                value: settings.encryptMessages,
                contentPadding: EdgeInsets.zero,
                title: const Text('Encrypt messages'),
                subtitle: const Text(
                  'When enabled, new direct messages are sent with end-to-end encryption.',
                ),
                onChanged: (value) {
                  Get.find<SettingsController>().setEncryptMessages(value);
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Encrypted History',
              subtitle:
                  'Restore room keys from Secure Backup, or ask verified devices to share them.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _encryptionRecoveryController,
                    enabled: !settings.isRestoringEncryption,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Recovery key or passphrase',
                      hintText:
                          'Paste your Matrix recovery key or backup passphrase',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: settings.isRestoringEncryption
                          ? null
                          : _restoreEncryptedHistory,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: Text(
                        settings.isRestoringEncryption
                            ? 'Restoring...'
                            : 'Restore from backup',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: settings.isRestoringEncryption
                          ? null
                          : _verifyDevice,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Verify Device'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    settings.secureBackupAvailable
                        ? 'Use your recovery key or passphrase on new devices. If another trusted Matrix app is already signed in, you can ask it for keys first.'
                        : 'This account does not currently advertise Secure Backup. Another verified Matrix app may still be able to share keys.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.72,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryNudge(SettingsState settings) {
    final theme = Theme.of(context);

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
              Icon(Icons.key_outlined, color: Color(0xFFC96A12)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Finish encrypted history setup',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            settings.secureBackupAvailable
                ? 'This device can send and receive encrypted messages, but it still needs your backup keys to read older secure history smoothly.'
                : 'This device can send and receive encrypted messages, but older secure history may still depend on another trusted device sharing keys.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: settings.isRestoringEncryption
                    ? null
                    : _verifyDevice,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Verify Device'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _encryptionRecoveryController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _encryptionRecoveryController.text.length,
                    ),
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Use backup below'),
              ),
            ],
          ),
        ],
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

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreEncryptedHistory() async {
    try {
      final message = await Get.find<SettingsController>()
          .restoreEncryptedHistory(_encryptionRecoveryController.text);
      _encryptionRecoveryController.clear();
      if (!mounted) return;
      Get.snackbar('', message, snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
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

      final client = Get.find<AuthController>().client;
      final encryption = client.encryption;
      if (encryption != null) {
        await encryption.ssss.maybeRequestAll();
      }
      await Get.find<RoomController>().requestMissingEncryptionKeys();
      await Get.find<SettingsController>().refreshSettings();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    Get.snackbar('Error', error.toString());
  }

  @override
  void dispose() {
    _encryptionRecoveryController.dispose();
    super.dispose();
  }
}
