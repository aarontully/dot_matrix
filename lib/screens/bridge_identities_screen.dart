import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/bridge_detector.dart';

class BridgeIdentitiesScreen extends StatefulWidget {
  const BridgeIdentitiesScreen({super.key});

  @override
  State<BridgeIdentitiesScreen> createState() => _BridgeIdentitiesScreenState();
}

class _BridgeIdentitiesScreenState extends State<BridgeIdentitiesScreen> {
  final _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Bridge identities'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mark bridge or meta users as "also me" so they do not appear in group member lists.',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              _buildAddRow(context),
              const SizedBox(height: 16),
              Expanded(
                child: GetBuilder<SettingsController>(
                  builder: (controller) {
                    final ids = controller.state?.alsoMeUserIds ?? [];
                    if (ids.isEmpty) {
                      return Center(
                        child: Text(
                          'No bridge identities yet',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: ids.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final id = ids[index];
                        final platform = BridgeDetector.detectFromUserId(id);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            id,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: platform != BridgePlatform.unknown
                              ? Text(
                                  'Detected: ${platform.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error.withValues(alpha: 0.7),
                            ),
                            onPressed: () => _remove(context, id),
                          ),
                        );
                      },
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

  Widget _buildAddRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Get.isDarkMode ? 0.18 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _inputCtrl,
                decoration: const InputDecoration(
                  hintText: 'Matrix user ID (e.g. @facebook_123:server)',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(context),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => _add(context),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    try {
      await Get.find<SettingsController>().addAlsoMeUser(text);
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', e.toString());
      }
    }
  }

  Future<void> _remove(BuildContext context, String id) async {
    try {
      await Get.find<SettingsController>().removeAlsoMeUser(id);
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', e.toString());
      }
    }
  }
}
