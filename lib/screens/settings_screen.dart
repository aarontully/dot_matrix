import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/settings_state.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _displayNameController = TextEditingController();
  final _statusMessageController = TextEditingController();
  String? _seededProfileKey;

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
        title: const Text('Profile'),
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
                  'We could not load your profile.\n$error',
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
            if (settings.isSavingProfile || settings.isUploadingAvatar)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            _buildProfileCard(settings),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Profile Details',
              subtitle: 'This is what Matrix contacts will see.',
              child: Column(
                children: [
                  TextField(
                    controller: _displayNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      hintText: 'How you appear in chats',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _statusMessageController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Status note',
                      hintText: 'Share a short note or leave this empty',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: settings.isSavingProfile ? null : _saveProfile,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save profile'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Account',
              subtitle:
                  'Quick identity details for the currently signed-in user.',
              child: Column(
                children: [
                  _buildInfoRow('User ID', settings.userId),
                  _buildInfoRow('Homeserver', settings.homeserver),
                  _buildInfoRow(
                    'Mode',
                    settings.isDemoMode ? 'Demo mode' : 'Connected',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'App controls like appearance, encryption recovery, notifications, and device safety live in the Menu tab.',
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

  Widget _buildProfileCard(SettingsState settings) {
    final theme = Theme.of(context);
    final isDark = Get.isDarkMode;
    final avatarUrl = _resolvedAvatarUrl(settings);
    final cardColor = theme.cardColor;
    final accentPanel = isDark
        ? const Color(0xFF233146)
        : const Color(0xFFEAF3FF);
    final subtlePanel = isDark
        ? const Color(0xFF243042)
        : const Color(0xFFEAF3FF);
    final mutedTextColor = theme.colorScheme.onSurface.withValues(alpha: 0.72);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: accentPanel,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(
                        avatarUrl,
                        headers: {
                          if (Get.find<AuthController>().client.accessToken !=
                              null)
                            'Authorization':
                                'Bearer ${Get.find<AuthController>().client.accessToken}',
                        },
                      )
                    : null,
                child: avatarUrl == null
                    ? Text(
                        settings.initials,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryBlue,
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Material(
                  color: cardColor,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: settings.isUploadingAvatar ? null : _pickAvatar,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.camera_alt, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            settings.displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            settings.statusMessage.isEmpty
                ? (settings.isDemoMode
                      ? 'Demo profile, local settings only'
                      : 'Customize your Matrix identity and presence')
                : settings.statusMessage,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatusPill(
                settings.activeStatusEnabled ? 'Active' : 'Offline',
                settings.activeStatusEnabled
                    ? const Color(0xFFE8F7EC)
                    : subtlePanel,
                settings.activeStatusEnabled
                    ? const Color(0xFF1B8D4B)
                    : mutedTextColor,
              ),
              _buildStatusPill(
                settings.isDemoMode ? 'Demo mode' : 'Profile only',
                subtlePanel,
                AppTheme.primaryBlue,
              ),
            ],
          ),
          if (avatarUrl != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: settings.isUploadingAvatar ? null : _clearAvatar,
              child: const Text('Remove avatar'),
            ),
          ],
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
            width: 92,
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

  Widget _buildStatusPill(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  String? _resolvedAvatarUrl(SettingsState settings) {
    final avatarUrl = settings.avatarUrl;
    if (avatarUrl == null || settings.isDemoMode) {
      return null;
    }

    final client = Get.find<AuthController>().client;
    final resolved = avatarUrl.getThumbnail(client, width: 240, height: 240);
    final value = resolved.toString();
    return value.isEmpty ? null : value;
  }

  void _syncControllers(SettingsState settings) {
    final profileKey = '${settings.userId}:${settings.isDemoMode}';
    if (_seededProfileKey == profileKey) {
      return;
    }

    _displayNameController.text = settings.displayName;
    _statusMessageController.text = settings.statusMessage;
    _seededProfileKey = profileKey;
  }

  Future<void> _saveProfile() async {
    try {
      final current = Get.find<SettingsController>().state;
      if (current == null) return;

      await Get.find<SettingsController>().saveProfile(
        displayName: _displayNameController.text,
        statusMessage: _statusMessageController.text,
        deviceName: current.deviceName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _pickAvatar() async {
    try {
      await Get.find<SettingsController>().pickAvatar();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avatar updated')));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _clearAvatar() async {
    try {
      await Get.find<SettingsController>().clearAvatar();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avatar removed')));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _statusMessageController.dispose();
    super.dispose();
  }
}
