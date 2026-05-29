import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/push_defaults.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final TextEditingController _pushGatewayController = TextEditingController();
  bool _didSeedPushGateway = false;

  @override
  void dispose() {
    _pushGatewayController.dispose();
    super.dispose();
  }

  void _seedPushGatewayUrl(String? value) {
    if (_didSeedPushGateway) return;
    _pushGatewayController.text = value ?? '';
    _didSeedPushGateway = true;
  }

  String? _normalizedPushGatewayUrl() {
    final trimmed = _pushGatewayController.text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _savePushGatewayUrl(SettingsController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = _normalizedPushGatewayUrl();
    if (url != null) {
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Enter a full push gateway URL, including https://'),
          ),
        );
        return;
      }
    }

    await controller.setPushGatewayUrl(url);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          url == null
              ? 'Push gateway cleared.'
              : 'Push gateway saved. DotMatrix will register this device for background push when notifications are enabled.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    final theme = Theme.of(context);
    final appDefaultGateway = defaultPushGatewayUrl();
    final appBarForeground = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
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
          _seedPushGatewayUrl(settings.pushGatewayUrl);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  context,
                  title: 'Message alerts',
                  subtitle:
                      'Get alerts for new messages, mentions, and highlighted activity.',
                  child: SwitchListTile.adaptive(
                    value: settings.notificationsEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifications'),
                    subtitle: const Text(
                      'Turning this on requests notification permission if needed.',
                    ),
                    onChanged: (value) async {
                      final controller = Get.find<SettingsController>();
                      if (value) {
                        final granted = await controller.enableNotifications();
                        if (!granted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Notification permission was not granted.',
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      await controller.disableNotifications();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  title: 'Push gateway (advanced)',
                  subtitle:
                      'DotMatrix auto-detects an existing Matrix push gateway when possible and falls back to the built-in DotMatrix gateway. Only set this manually if you need to override that behavior.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (appDefaultGateway != null) ...[
                        Text(
                          'Default gateway: $appDefaultGateway',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _pushGatewayController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Gateway URL',
                          hintText:
                              'https://push.example.com/_matrix/push/v1/notify',
                        ),
                        onSubmitted: (_) =>
                            _savePushGatewayUrl(settingsController),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Most Matrix setups use a Sygnal-style endpoint ending in `/_matrix/push/v1/notify`. If you already use another Matrix client, DotMatrix will try to reuse that gateway automatically before falling back to its own default.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _savePushGatewayUrl(settingsController),
                            child: const Text('Save gateway'),
                          ),
                          TextButton(
                            onPressed: () async {
                              _pushGatewayController.clear();
                              await _savePushGatewayUrl(settingsController);
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Local alerts work while DotMatrix is running. Full Android background push still depends on Firebase setup plus a working Matrix push gateway.',
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
      color: theme.brightness == Brightness.dark
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
