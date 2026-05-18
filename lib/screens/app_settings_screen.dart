import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../models/settings_state.dart';
import '../theme/app_theme.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {

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
            _buildSectionCard(
              title: 'Preferences',
              subtitle: 'Appearance and presence for this app.',
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Accent colour',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: bodyColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildColorPicker(settings),
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
            const SizedBox(height: 12),
            Text(
              'Sign out lives on the Profile screen (person icon in the header).',
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

  Widget _buildColorPicker(SettingsState settings) {
    final presets = [
      const Color(0xFF0084FF), // Default blue
      const Color(0xFFE91E63), // Pink
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF4CAF50), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFFF44336), // Red
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFF795548), // Brown
    ];
    final current = settings.customPrimaryColor;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...presets.map((color) {
          final isSelected = current == color;
          return InkWell(
            onTap: () =>
                Get.find<SettingsController>().setCustomPrimaryColor(color),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          );
        }),
        InkWell(
          onTap: () =>
              Get.find<SettingsController>().clearCustomPrimaryColor(),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: current == null
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: const Icon(Icons.replay, size: 16),
          ),
        ),
      ],
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

  Future<void> _toggleActiveStatus(bool value) async {
    try {
      await Get.find<SettingsController>().setActiveStatus(value);
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
    super.dispose();
  }
}
