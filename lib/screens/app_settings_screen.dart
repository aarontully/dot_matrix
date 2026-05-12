import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/settings_state.dart';
import '../theme/app_theme.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final _deviceNameController = TextEditingController();
  final _encryptionRecoveryController = TextEditingController();
  String? _seededSettingsKey;

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
        title: const Text('App settings'),
      ),
      body: settingsController.obx(
        (settings) {
          if (settings == null) return const SizedBox.shrink();
          _syncControllers(settings);
          return _buildContent(context, settings);
        },
        onLoading: const Center(child: CircularProgressIndicator()),
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
    final bodyColor = theme.colorScheme.onSurface.withValues(alpha: 0.76);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settings.isSavingProfile ||
                settings.isUploadingAvatar ||
                settings.isRestoringEncryption)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (settings.encryptionEnabled &&
                !settings.encryptedHistoryReady) ...[
              _buildRecoveryNudge(settings),
              const SizedBox(height: 16),
            ],
            _buildSectionCard(
              title: 'Preferences',
              subtitle: 'Appearance, alerts, and presence for this app.',
              child: Column(
                children: [
                  DropdownButtonFormField<AppAppearance>(
                    initialValue: settings.appearance,
                    decoration: const InputDecoration(labelText: 'Appearance'),
                    items: AppAppearance.values
                        .map(
                          (appearance) => DropdownMenuItem(
                            value: appearance,
                            child: Text(appearance.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      Get.find<SettingsController>().setAppearance(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: settings.activeStatusEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active status'),
                    subtitle: const Text('Updates your Matrix presence state'),
                    onChanged: (value) => _toggleActiveStatus(value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: settings.notificationsEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifications'),
                    subtitle: const Text(
                      'Saved locally while notification wiring is still lightweight',
                    ),
                    onChanged: (value) {
                      Get.find<SettingsController>().setNotificationsEnabled(
                        value,
                      );
                    },
                  ),
                ],
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
                          : _requestKeysFromVerifiedDevices,
                      icon: const Icon(Icons.devices_outlined),
                      label: const Text('Ask verified devices'),
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
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Session Safety',
              subtitle: 'Device details and account connection state.',
              child: Column(
                children: [
                  TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Device label',
                      hintText: 'How this device appears in Matrix',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: settings.isSavingProfile
                          ? null
                          : _saveDeviceName,
                      child: const Text('Save device label'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('User ID', settings.userId),
                  _buildInfoRow('Homeserver', settings.homeserver),
                  _buildInfoRow('Device ID', settings.deviceId),
                  _buildInfoRow(
                    'Encryption',
                    settings.encryptionEnabled ? 'Enabled' : 'Unavailable',
                  ),
                  _buildInfoRow('Mode', 'Connected'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Chats',
              subtitle: 'Choose how your inbox is organized.',
              child: SegmentedButton<ChatSortOrder>(
                segments: [
                  ButtonSegment(
                    value: ChatSortOrder.newest,
                    label: Text(ChatSortOrder.newest.label),
                  ),
                  ButtonSegment(
                    value: ChatSortOrder.unreadFirst,
                    label: Text(ChatSortOrder.unreadFirst.label),
                  ),
                ],
                selected: {settings.chatSortOrder},
                onSelectionChanged: (Set<ChatSortOrder> newSelection) {
                  Get.find<SettingsController>().setChatSortOrder(
                    newSelection.first,
                  );
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white,
                  selectedForegroundColor: AppTheme.primaryBlue,
                  selectedBackgroundColor: const Color(0xFFEAF3FF),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'About',
              subtitle:
                  'A few practical notes while the client keeps evolving.',
              child: Column(
                children: [
                  _buildInfoRow(
                    'Product direction',
                    'A lightweight Matrix messenger with a Messenger-style shell',
                  ),
                  _buildInfoRow(
                    'Status',
                    'Matrix profile, presence, avatar, device settings, and recovery tools are live',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Profile editing stays separate so the menu can focus on app controls, encryption recovery, and device safety.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: bodyColor,
                height: 1.4,
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
                    : _requestKeysFromVerifiedDevices,
                icon: const Icon(Icons.devices_outlined),
                label: const Text('Ask devices again'),
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

  void _syncControllers(SettingsState settings) {
    final settingsKey = '${settings.userId}:${settings.deviceName}';
    if (_seededSettingsKey == settingsKey) {
      return;
    }

    _deviceNameController.text = settings.deviceName;
    _seededSettingsKey = settingsKey;
  }

  Future<void> _toggleActiveStatus(bool value) async {
    try {
      await Get.find<SettingsController>().setActiveStatus(value);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _restoreEncryptedHistory() async {
    try {
      final message = await Get.find<SettingsController>()
          .restoreEncryptedHistory(_encryptionRecoveryController.text);
      _encryptionRecoveryController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _requestKeysFromVerifiedDevices() async {
    try {
      final message = await Get.find<SettingsController>()
          .requestEncryptedHistoryFromVerifiedDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _saveDeviceName() async {
    try {
      await Get.find<SettingsController>().saveDeviceName(
        _deviceNameController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device label saved')));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _signOut() async {
    await Get.find<AuthController>().logout();
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _encryptionRecoveryController.dispose();
    super.dispose();
  }
}
