import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    final theme = Theme.of(context);
    final appBarForeground =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor:
          theme.brightness == Brightness.dark
              ? AppTheme.darkBackground
              : AppTheme.settingsBackground,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appBarForeground, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications'),
      ),
      body: settingsController.obx(
        (settings) {
          if (settings == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  context,
                  title: 'Message alerts',
                  subtitle: 'Control whether DotMatrix shows notifications.',
                  child: SwitchListTile.adaptive(
                    value: settings.notificationsEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifications'),
                    subtitle: const Text(
                      'Saved locally while notification wiring is still lightweight',
                    ),
                    onChanged: (value) {
                      Get.find<SettingsController>().setNotificationsEnabled(value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Push notifications through the homeserver are not yet enabled.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );
        },
        onLoading: const Center(child: CircularProgressIndicator()),
        onError: (error) => Center(child: Text('Error: ${error ?? ""}')),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color:
          theme.brightness == Brightness.dark
              ? const Color(0xFF1C1C1E)
              : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
