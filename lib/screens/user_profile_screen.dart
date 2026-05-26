import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/bridge_detector.dart';
import '../widgets/bridge_icon.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final client = Get.find<AuthController>().client;

    return GetBuilder<SettingsController>(
      builder: (settingsController) {
        final settings = settingsController.state;
        final isMe = user.id == client.userID;
        final isBridgeIdentity =
            settings?.alsoMeUserIds.contains(user.id) ?? false;
        final bridgePlatform = BridgeDetector.detectFromUserId(user.id);
        final displayName = _displayNameFor(user);
        final avatarUrl = resolveAvatarImageUrl(
          user.avatarUrl,
          client,
          size: 240,
        );

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              if (!isMe)
                IconButton(
                  tooltip: isBridgeIdentity
                      ? 'Already added as bridge identity'
                      : 'Add as bridge identity',
                  onPressed: isBridgeIdentity
                      ? null
                      : () => _confirmAddBridgeIdentity(
                          context,
                          settingsController,
                          displayName,
                        ),
                  icon: Icon(
                    isBridgeIdentity
                        ? Icons.verified_user_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: isBridgeIdentity ? cs.primary : null,
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      _ProfileAvatar(
                        avatarUrl: avatarUrl,
                        rawAvatarUrl: user.avatarUrl,
                        displayName: displayName,
                        colorScheme: cs,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.id,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isMe)
                            _StatusChip(label: 'You', color: cs.primary),
                          if (bridgePlatform != BridgePlatform.unknown)
                            _BridgePlatformChip(platform: bridgePlatform),
                          if (isBridgeIdentity)
                            _StatusChip(
                              label: 'Bridge identity',
                              color: cs.tertiary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(label: 'Name', value: displayName),
                      const SizedBox(height: 14),
                      _InfoRow(label: 'Matrix ID', value: user.id),
                      const SizedBox(height: 14),
                      _InfoRow(
                        label: 'Bridge source',
                        value: bridgePlatform == BridgePlatform.unknown
                            ? 'Not detected'
                            : bridgePlatform.name,
                      ),
                      const SizedBox(height: 14),
                      _InfoRow(
                        label: 'Local status',
                        value: isBridgeIdentity
                            ? 'Added as bridge identity on this device'
                            : 'Normal contact',
                      ),
                    ],
                  ),
                ),
                if (!isMe) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Bridge identity is a local-only label. It helps Dot Matrix hide your own bridged accounts from member lists and bridge detection, but marking the wrong person can make this client treat them like one of your identities.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAddBridgeIdentity(
    BuildContext context,
    SettingsController settingsController,
    String displayName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add bridge identity?'),
        content: Text(
          'Mark "$displayName" as one of your bridge identities on this device? Dot Matrix will hide them from member lists and treat them like one of your own bridged accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await settingsController.addAlsoMeUser(user.id);
    if (!context.mounted) return;
    Get.snackbar('', '$displayName added as bridge identity');
  }

  String _displayNameFor(User value) {
    final displayName = value.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return value.id.localpart ?? value.id;
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.avatarUrl,
    required this.rawAvatarUrl,
    required this.displayName,
    required this.colorScheme,
  });

  final String? avatarUrl;
  final Uri? rawAvatarUrl;
  final String displayName;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    if (avatarUrl == null) {
      return CircleAvatar(
        radius: 44,
        backgroundColor: colorScheme.secondaryContainer,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: avatarUrl!,
      imageBuilder: (context, imageProvider) =>
          CircleAvatar(radius: 44, backgroundImage: imageProvider),
      placeholder: (_, __) => CircleAvatar(
        radius: 44,
        backgroundColor: colorScheme.secondaryContainer,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      ),
      errorWidget: (_, __, ___) {
        markAvatarSourceBroken(rawAvatarUrl);
        return CircleAvatar(
          radius: 44,
          backgroundColor: colorScheme.secondaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BridgePlatformChip extends StatelessWidget {
  const _BridgePlatformChip({required this.platform});

  final BridgePlatform platform;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BridgeIcon(platform: platform),
          const SizedBox(width: 6),
          Text(
            platform.name,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
