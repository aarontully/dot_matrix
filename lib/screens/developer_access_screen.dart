import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';

class DeveloperAccessScreen extends StatefulWidget {
  const DeveloperAccessScreen({super.key});

  @override
  State<DeveloperAccessScreen> createState() => _DeveloperAccessScreenState();
}

class _DeveloperAccessScreenState extends State<DeveloperAccessScreen> {
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
        title: const Text('Developer access'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionCard(
                title: 'Access token',
                subtitle:
                    'Your access token is as powerful as your password. Never share it or paste it into untrusted sites.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showAccessTokenSheet(context),
                      icon: const Icon(Icons.vpn_key_outlined, size: 20),
                      label: const Text('View access token'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Recovery passphrase',
                subtitle:
                    'Rotate the passphrase used to protect your Matrix Secure Backup.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showChangeRecoveryKeyDialog(context),
                      icon: const Icon(Icons.password_outlined, size: 20),
                      label: const Text('Change recovery passphrase'),
                    ),
                  ],
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

  Future<void> _showAccessTokenSheet(BuildContext context) async {
    final token = Get.find<AuthController>().client.accessToken;
    if (!context.mounted) return;
    if (token == null || token.isEmpty) {
      Get.snackbar('Error', 'No access token is available.');
      return;
    }

    var revealed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final obscured = token.length <= 10
                ? '•' * token.length
                : '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
            final display = revealed ? token : obscured;
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.paddingOf(ctx).bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Access token',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Anyone with this token can use your account. Copy it only for trusted tools (e.g. curl, bridges, debugging).',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    display,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setModal(() => revealed = !revealed),
                          child: Text(revealed ? 'Hide' : 'Reveal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: token));
                            if (ctx.mounted) {
                              Get.snackbar('', 'Access token copied', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
                            }
                          },
                          child: const Text('Copy'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showChangeRecoveryKeyDialog(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final nextCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var busy = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialog) {
              return AlertDialog(
                title: const Text('Change recovery passphrase'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter your current Matrix recovery key or Secure Backup passphrase, then choose a new passphrase (at least 8 characters). This updates Secure Backup.',
                          style: Theme.of(
                            ctx,
                          ).textTheme.bodySmall?.copyWith(height: 1.35),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: currentCtrl,
                          obscureText: true,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Current recovery key or passphrase',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nextCtrl,
                          obscureText: true,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'New passphrase',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 8) {
                              return 'At least 8 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            setDialog(() => busy = true);
                            try {
                              final msg = await Get.find<SettingsController>()
                                  .changeRecoveryPassphrase(
                                    currentSecret: currentCtrl.text,
                                    newPassphrase: nextCtrl.text,
                                  );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                Get.snackbar('', msg, snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
                              }
                            } catch (e) {
                              setDialog(() => busy = false);
                              if (ctx.mounted) {
                                Get.snackbar('Error', e.toString());
                              }
                            }
                          },
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      currentCtrl.dispose();
      nextCtrl.dispose();
    }
  }
}
