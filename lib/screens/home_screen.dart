import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../models/room_model.dart';
import '../models/settings_state.dart';
import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/matrix_event_display.dart';
import '../widgets/dot_matrix_text.dart';
import '../widgets/room_avatar_grid.dart';
import 'app_settings_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'compose_screen.dart';
import 'developer_access_screen.dart';
import 'encryption_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'sessions_screen.dart';

enum _HomeTab { chats, activity, menu }

enum _ActivityKind {
  textMessage,
  emote,
  image,
  video,
  reaction,
  encryptedMessage,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _searchQuery = '';
  int _menuRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final roomController = Get.find<RoomController>();
    final selectedTab = _HomeTab.values[_selectedIndex];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, selectedTab),
            if (selectedTab != _HomeTab.menu)
              _buildSearchBar(context, selectedTab),
            Expanded(
              child: switch (selectedTab) {
                _HomeTab.chats => roomController.obx(
                  (rooms) => Obx(
                    () => _buildChatsTab(context, rooms ?? []),
                  ),
                  onLoading: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onError: (error) => _buildErrorState(
                    context,
                    'We could not load your rooms yet.',
                    error.toString(),
                  ),
                ),
                _HomeTab.activity => roomController.obx(
                  (rooms) => _buildActivityTab(context, rooms ?? []),
                  onLoading: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onError: (error) => _buildErrorState(
                    context,
                    'We could not build your activity feed yet.',
                    error.toString(),
                  ),
                ),
                _HomeTab.menu => _buildMenuTab(context),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt_outlined),
            activeIcon: Icon(Icons.bolt),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Menu',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _HomeTab tab) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          DotMatrixText(
            dotSize: 3.0,
            spacing: 3.8,
            letterGap: 2.2,
            color: cs.primary,
          ),
          const Spacer(),
          if (tab == _HomeTab.chats) ...[
            IconButton(
              icon: Icon(
                Icons.filter_list_outlined,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => _showSpaceFilterSheet(context),
            ),
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComposeScreen()),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, _HomeTab tab) {
    final cs = Theme.of(context).colorScheme;
    final hintText = tab == _HomeTab.activity
        ? 'Search activity'
        : 'Search chats';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        style: TextStyle(color: cs.onSurface),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  void _showSpaceFilterSheet(BuildContext context) {
    final roomController = Get.find<RoomController>();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Obx(() {
              final spaces = roomController.spaces;
              final selectedId = roomController.selectedSpaceId.value;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter by Space',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _SpaceFilterTile(
                    label: 'All chats',
                    value: null,
                    groupValue: selectedId,
                    onTap: (value) {
                      roomController.selectedSpaceId.value = value;
                      Navigator.pop(ctx);
                    },
                  ),
                  ...spaces.map((space) {
                    return _SpaceFilterTile(
                      label: space['name'] ?? 'Space',
                      value: space['id'],
                      groupValue: selectedId,
                      onTap: (value) {
                        roomController.selectedSpaceId.value = value;
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildChatsTab(BuildContext context, List<AppRoom> rooms) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filteredRooms = _filterRooms(rooms);

    if (filteredRooms.isEmpty) {
      final isSyncing = Get.find<AuthController>().client.prevBatch == null;
      if (isSyncing) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 24),
            Text(
              'Syncing with Matrix...',
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }

      if (_searchQuery.isEmpty) {
        return _buildEmptyState(
          context,
          icon: Icons.forum_outlined,
          title: 'No chats yet',
          subtitle: 'Start a new conversation to see it here.',
        );
      }

      return _buildEmptyState(
        context,
        icon: Icons.forum_outlined,
        title: 'No chats match that search',
        subtitle: 'Try a different room name or message preview.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: filteredRooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final room = filteredRooms[index];
        return Dismissible(
          key: ValueKey(room.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmLeaveRoom(context, room),
          onDismissed: (_) {},
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.archive_outlined, color: Colors.white),
          ),
          child: _buildChatItem(context, room),
        );
      },
    );
  }

  Widget _buildActivityTab(BuildContext context, List<AppRoom> rooms) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Future<void> onRefresh() async {
      await Get.find<RoomController>().refreshRooms();
    }

    final activityItems = _filterActivityItems(_buildActivityItems(rooms));

    Widget scrollBody;
    if (activityItems.isEmpty) {
      final isSyncing = Get.find<AuthController>().client.prevBatch == null;
      if (isSyncing) {
        scrollBody = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: (MediaQuery.sizeOf(context).height - 200).clamp(
                280.0,
                640.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: cs.primary),
                  const SizedBox(height: 24),
                  Text(
                    'Syncing with Matrix...',
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      } else if (_searchQuery.isEmpty) {
        scrollBody = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: (MediaQuery.sizeOf(context).height - 200).clamp(
                280.0,
                640.0,
              ),
              child: _buildEmptyState(
                context,
                icon: Icons.bolt_outlined,
                title: 'Your activity feed is clear',
                subtitle:
                    'New messages, reactions, and media from others in your group chats will show here.',
              ),
            ),
          ],
        );
      } else {
        scrollBody = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: (MediaQuery.sizeOf(context).height - 200).clamp(
                280.0,
                640.0,
              ),
              child: _buildEmptyState(
                context,
                icon: Icons.bolt_outlined,
                title: 'No activity matches that search',
                subtitle: 'Try a different term or clear your search.',
              ),
            ),
          ],
        );
      }
    } else {
      scrollBody = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Activity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...activityItems.map((e) => _buildActivityCard(context, e)),
        ],
      );
    }

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: onRefresh,
      child: scrollBody,
    );
  }

  Widget _buildMenuTab(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settingsController = Get.find<SettingsController>();

    Future<void> onMenuRefresh() async {
      await settingsController.refreshSettings();
      if (context.mounted) {
        setState(() => _menuRefreshToken++);
      }
    }

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: onMenuRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          GetBuilder<SettingsController>(
            builder: (ctrl) {
              final settings = ctrl.state;
              if (settings == null) return const SizedBox.shrink();

              final client = Get.find<AuthController>().client;
              final avatarImageUrl = resolveAvatarImageUrl(
                settings.avatarUrl,
                client,
                size: 112,
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => _openProfile(context),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (avatarImageUrl != null)
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: cs.primaryContainer,
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: avatarImageUrl,
                                httpHeaders: {
                                  if (client.accessToken != null)
                                    'Authorization': 'Bearer ${client.accessToken}',
                                },
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 56,
                                  height: 56,
                                  color: cs.primaryContainer,
                                  child: Center(
                                    child: Text(
                                      settings.initials,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 56,
                                  height: 56,
                                  color: cs.primaryContainer,
                                  child: Center(
                                    child: Text(
                                      settings.initials,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              settings.initials,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                settings.displayName.isNotEmpty
                                    ? settings.displayName
                                    : settings.userId,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                settings.userId,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          GetBuilder<SettingsController>(
            builder: (ctrl) {
              final settings = ctrl.state;
              if (settings == null ||
                  !settings.encryptionEnabled ||
                  settings.encryptedHistoryReady) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.onTertiaryContainer.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.key_outlined,
                            color: cs.onTertiaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Finish encrypted history setup',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        settings.secureBackupAvailable
                            ? 'This device is connected, but it still needs your backup keys to read older secure history smoothly.'
                            : 'This device can chat securely, but older secure history may still depend on another trusted device sharing keys.',
                        style: TextStyle(
                          color: cs.onTertiaryContainer.withValues(alpha: 0.88),
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
                                : () => _askDevicesAgain(context),
                            icon: const Icon(Icons.devices_outlined),
                            label: const Text('Ask devices again'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openEncryptionSettings(context),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Open recovery tools'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          _buildMenuSection(
            context,
            title: 'Settings',
            subtitle: 'Manage notifications, encryption, sessions, and more.',
            child: Column(
              children: [
                _buildMenuTile(
                  context,
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: _menuNotificationsSubtitle(),
                  onTap: () => _openNotificationSettings(context),
                ),
                const Divider(height: 1),
                _buildMenuTile(
                  context,
                  icon: Icons.lock_outline,
                  title: 'Encryption',
                  subtitle: _menuEncryptionSubtitle(),
                  onTap: () => _openEncryptionSettings(context),
                ),
                const Divider(height: 1),
                _buildMenuTile(
                  context,
                  icon: Icons.devices_outlined,
                  title: 'Sessions',
                  subtitle: 'Devices signed in to your Matrix account',
                  onTap: () => _openSessions(context),
                ),
                const Divider(height: 1),
                _buildMenuTile(
                  context,
                  icon: Icons.code_outlined,
                  title: 'Developer access',
                  subtitle: 'Access token and recovery tools',
                  onTap: () => _openDeveloperAccess(context),
                ),
                const Divider(height: 1),
                _buildMenuTile(
                  context,
                  icon: Icons.tune,
                  title: 'App',
                  subtitle: _menuAppSubtitle(),
                  onTap: () => _openAppSettings(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(
    BuildContext context, {
    String? title,
    String? subtitle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: cs.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
    );
  }

  Widget _buildChatItem(BuildContext context, AppRoom room) {
    final activityAt = _roomActivityAt(room);
    final preview = _roomPreview(room);
    final previewUnread = room.hasUnread;
    final theme = Theme.of(context);
    final initial = room.displayname.isEmpty
        ? '#'
        : room.displayname.characters.first.toUpperCase();
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            RoomAvatarGrid(
              avatarUrl: room.avatarUrl,
              memberAvatarUrls: room.memberAvatarUrls,
              size: 56,
              fallbackInitial: initial,
              backgroundColor: theme.colorScheme.primaryContainer,
              fallbackColor: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.displayname,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: previewUnread
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.76,
                                  ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimestamp(activityAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: previewUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: previewUnread
                                ? theme.colorScheme.onSurface.withValues(
                                    alpha: 0.92,
                                  )
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (room.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        _buildUnreadCountBadge(context, room.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnreadCountBadge(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: EdgeInsets.symmetric(horizontal: count > 9 ? 7 : 6, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildActivityCard(BuildContext context, _ActivityItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(room: item.room)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, color: item.tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.caption,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.preview,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.92),
                        fontSize: 14,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: item.tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.status,
                        style: TextStyle(
                          color: item.tint,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, size: 32, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String title, String details) {
    return _buildEmptyState(
      context,
      icon: Icons.error_outline,
      title: title,
      subtitle: details,
    );
  }

  List<AppRoom> _filterRooms(List<AppRoom> rooms) {
    final normalizedQuery = _searchQuery.toLowerCase();
    var filteredRooms = normalizedQuery.isEmpty
        ? List<AppRoom>.from(rooms)
        : rooms.where((room) {
            final haystack = '${room.displayname} ${room.lastMessage ?? ''}'
                .toLowerCase();
            return haystack.contains(normalizedQuery);
          }).toList();

    final selectedSpaceId =
        Get.find<RoomController>().selectedSpaceId.value;
    if (selectedSpaceId != null) {
      filteredRooms = filteredRooms
          .where((r) => r.spaceParentIds.contains(selectedSpaceId))
          .toList();
    }

    final sortOrder =
        Get.find<SettingsController>().state?.chatSortOrder ??
        ChatSortOrder.newest;

    filteredRooms.sort((a, b) {
      if (sortOrder == ChatSortOrder.unreadFirst) {
        if (a.hasUnread && !b.hasUnread) return -1;
        if (!a.hasUnread && b.hasUnread) return 1;
      }
      return _roomActivityAt(b).compareTo(_roomActivityAt(a));
    });

    return filteredRooms;
  }

  List<_ActivityItem> _filterActivityItems(List<_ActivityItem> items) {
    final normalizedQuery = _searchQuery.toLowerCase();
    if (normalizedQuery.isEmpty) {
      return items;
    }

    return items.where((item) {
      final haystack = '${item.title} ${item.preview} ${item.caption}'
          .toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  List<_ActivityItem> _buildActivityItems(List<AppRoom> rooms) {
    final auth = Get.find<AuthController>();
    if (auth.state == null) return [];
    final client = auth.client;
    final myId = client.userID;
    if (myId == null) return [];

    final items = <_ActivityItem>[];

    for (final room in rooms) {
      final matrixRoom = client.getRoomById(room.id);
      if (matrixRoom == null || matrixRoom.isDirectChat) continue;

      final latestMessage = _latestQualifyingActivityFromOthers(room, myId);
      final latestReaction = room.latestReactionActivity;

      final messageTs = latestMessage?.originServerTs;
      final reactionTs = latestReaction?.timestamp;

      if (messageTs == null && reactionTs == null) continue;

      if (reactionTs != null &&
          (messageTs == null || reactionTs.isAfter(messageTs))) {
        final senderName = latestReaction!.senderName?.isNotEmpty == true
            ? latestReaction.senderName!
            : _localpart(latestReaction.senderId);
        items.add(
          _ActivityItem(
            room: room,
            title: room.displayname,
            preview: latestReaction.targetMessageBody,
            caption: '$senderName reacted ${latestReaction.emoji}',
            status: 'Reaction',
            timestamp: latestReaction.timestamp,
            kind: _ActivityKind.reaction,
          ),
        );
      } else {
        final labels = _activityLabelsForEvent(latestMessage!.rawEvent);
        items.add(
          _ActivityItem(
            room: room,
            title: room.displayname,
            preview: matrixEventDisplayText(latestMessage.rawEvent),
            caption: labels.$1,
            status: labels.$2,
            timestamp: latestMessage.originServerTs,
            kind: labels.$3,
          ),
        );
      }
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  /// Latest timeline event from someone else: text, emote, image, video,
  /// encrypted message, or reaction.
  AppEvent? _latestQualifyingActivityFromOthers(AppRoom room, String myUserId) {
    final sorted = List<AppEvent>.from(room.messages)
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    for (final e in sorted) {
      if (e.senderId == myUserId) continue;
      if (!_isActivityEligibleEvent(e.rawEvent)) continue;
      return e;
    }
    return null;
  }

  bool _isActivityEligibleEvent(Event ev) {
    if (ev.type == EventTypes.Reaction) return true;
    if (ev.type == EventTypes.Encrypted) return true;
    if (ev.type != EventTypes.Message) return false;
    switch (ev.messageType) {
      case MessageTypes.Text:
      case MessageTypes.Emote:
      case MessageTypes.Image:
      case MessageTypes.Video:
        return true;
      default:
        return false;
    }
  }

  (String, String, _ActivityKind) _activityLabelsForEvent(Event ev) {
    if (ev.type == EventTypes.Reaction) {
      return ('Someone reacted', 'Reaction', _ActivityKind.reaction);
    }
    if (ev.type == EventTypes.Encrypted) {
      return ('New message', 'Encrypted', _ActivityKind.encryptedMessage);
    }
    if (ev.type == EventTypes.Message) {
      switch (ev.messageType) {
        case MessageTypes.Image:
          return ('New image', 'Image', _ActivityKind.image);
        case MessageTypes.Video:
          return ('New video', 'Video', _ActivityKind.video);
        case MessageTypes.Text:
          return ('New message', 'Message', _ActivityKind.textMessage);
        case MessageTypes.Emote:
          return ('Emote', 'Emote', _ActivityKind.emote);
        default:
          return ('New message', 'Message', _ActivityKind.textMessage);
      }
    }
    return ('New activity', 'Update', _ActivityKind.textMessage);
  }

  AppEvent? _latestEvent(AppRoom room) {
    if (room.messages.isEmpty) {
      return null;
    }

    final sortedMessages = List<AppEvent>.from(room.messages)
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    return sortedMessages.last;
  }

  DateTime _roomActivityAt(AppRoom room) {
    final latestEvent = _latestEvent(room);
    final lastEventTs = room.lastEventTs;

    if (lastEventTs != null && latestEvent != null) {
      return lastEventTs.isAfter(latestEvent.originServerTs)
          ? lastEventTs
          : latestEvent.originServerTs;
    }

    return lastEventTs ?? latestEvent?.originServerTs ?? DateTime.now();
  }

  String _roomPreview(AppRoom room) {
    final latestEvent = _latestEvent(room);
    final lastEventTs = room.lastEventTs;

    String text;
    if (lastEventTs != null && latestEvent != null) {
      if (lastEventTs.isAfter(latestEvent.originServerTs)) {
        text = room.lastMessage ?? latestEvent.body;
      } else {
        text = latestEvent.body;
      }
    } else {
      text = room.lastMessage ?? latestEvent?.body ?? 'No messages yet';
    }

    if (room.isGroup && latestEvent != null) {
      final name = latestEvent.senderName?.isNotEmpty == true
          ? latestEvent.senderName!
          : _localpart(latestEvent.senderId);
      return '$name: $text';
    }

    return text;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(timestamp, now)) {
      return DateFormat.jm().format(timestamp);
    }
    if (now.difference(timestamp).inDays < 7) {
      return DateFormat.E().format(timestamp);
    }
    return DateFormat.MMMd().format(timestamp);
  }

  String _localpart(String userId) {
    final withoutServer = userId.split(':').first;
    return withoutServer.startsWith('@')
        ? withoutServer.substring(1)
        : withoutServer;
  }

  String _menuNotificationsSubtitle() {
    final settings = Get.find<SettingsController>().state;
    if (settings == null) {
      return 'Message alerts';
    }
    return settings.notificationsEnabled ? 'On' : 'Off';
  }

  String _menuEncryptionSubtitle() {
    final settings = Get.find<SettingsController>().state;
    if (settings == null) {
      return 'Secure Backup and room keys';
    }
    if (settings.encryptionEnabled && !settings.encryptedHistoryReady) {
      return 'Finish encrypted history recovery';
    }
    return settings.encryptionEnabled ? 'Enabled' : 'Unavailable';
  }

  String _menuAppSubtitle() {
    final settings = Get.find<SettingsController>().state;
    if (settings == null) {
      return 'Appearance, presence, and chat ordering';
    }
    return 'Appearance, presence, and chat ordering';
  }

  Future<void> _askDevicesAgain(BuildContext context) async {
    try {
      final message = await Get.find<SettingsController>()
          .requestEncryptedHistoryFromVerifiedDevices();
      if (!context.mounted) return;
      Get.snackbar('', message, snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
    } catch (error) {
      if (!context.mounted) return;
      Get.snackbar('Error', error.toString());
    }
  }

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openNotificationSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
  }

  void _openEncryptionSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EncryptionSettingsScreen()),
    );
  }

  void _openSessions(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SessionsScreen()),
    );
  }

  void _openDeveloperAccess(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeveloperAccessScreen()),
    );
  }

  void _openAppSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
  }

  Future<bool> _confirmLeaveRoom(BuildContext context, AppRoom appRoom) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave chat?'),
        content: Text(
          'You will leave "${appRoom.displayname}". This removes it from your room list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (result != true) return false;

    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(appRoom.id);
      if (room != null) {
        await room.leave();
        await Get.find<RoomController>().refreshRooms();
      }
    } catch (error) {
      if (context.mounted) {
        Get.snackbar('Error', 'Could not leave room: $error');
      }
      return false;
    }

    return true;
  }
}

class _SpaceFilterTile extends StatelessWidget {
  const _SpaceFilterTile({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onTap,
  });

  final String label;
  final String? value;
  final String? groupValue;
  final void Function(String?) onTap;

  bool get isSelected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      leading: SizedBox(
        width: 40,
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                width: isSelected ? 6 : 2,
              ),
            ),
          ),
        ),
      ),
      onTap: () => onTap(value),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.room,
    required this.title,
    required this.preview,
    required this.caption,
    required this.status,
    required this.timestamp,
    required this.kind,
  });

  final AppRoom room;
  final String title;
  final String preview;
  final String caption;
  final String status;
  final DateTime timestamp;
  final _ActivityKind kind;

  Color get tint => switch (kind) {
    _ActivityKind.textMessage => AppTheme.primaryBlue,
    _ActivityKind.emote => const Color(0xFFE91E8C),
    _ActivityKind.image => const Color(0xFF8E44AD),
    _ActivityKind.video => const Color(0xFFC0392B),
    _ActivityKind.reaction => const Color(0xFFFF8A34),
    _ActivityKind.encryptedMessage => const Color(0xFF546E7A),
  };

  IconData get icon => switch (kind) {
    _ActivityKind.textMessage => Icons.chat_bubble_outline,
    _ActivityKind.emote => Icons.emoji_emotions_outlined,
    _ActivityKind.image => Icons.image_outlined,
    _ActivityKind.video => Icons.videocam_outlined,
    _ActivityKind.reaction => Icons.add_reaction_outlined,
    _ActivityKind.encryptedMessage => Icons.lock_outline,
  };
}
