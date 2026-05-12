import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../models/room_model.dart';
import '../models/settings_state.dart';
import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_url_resolver.dart';
import 'app_settings_screen.dart';
import 'chat_screen.dart';
import 'compose_screen.dart';
import 'settings_screen.dart';

enum _HomeTab { chats, activity, menu }

enum _ActivityKind { incoming, outgoing, quiet }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final roomController = Get.find<RoomController>();
    final selectedTab = _HomeTab.values[_selectedIndex];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, selectedTab),
            if (selectedTab != _HomeTab.menu) _buildSearchBar(selectedTab),
            Expanded(
              child: switch (selectedTab) {
                _HomeTab.chats => roomController.obx(
                  (rooms) => _buildChatsTab(rooms ?? []),
                  onLoading: const Center(child: CircularProgressIndicator()),
                  onError: (error) => _buildErrorState(
                    'We could not load your rooms yet.',
                    error.toString(),
                  ),
                ),
                _HomeTab.activity => roomController.obx(
                  (rooms) => _buildActivityTab(rooms ?? []),
                  onLoading: const Center(child: CircularProgressIndicator()),
                  onError: (error) => _buildErrorState(
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => _openProfile(context),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DotMatrix',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.7,
                  ),
                ),
                Text(
                  _headerSubtitle(tab),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _headerActionIcon(tab),
              color:
                  Theme.of(context).appBarTheme.foregroundColor ??
                  Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              if (tab == _HomeTab.menu) {
                Get.find<AuthController>().logout();
                return;
              }

              if (tab == _HomeTab.chats) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComposeScreen()),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_headerActionMessage(tab))),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(_HomeTab tab) {
    final hintText = tab == _HomeTab.activity
        ? 'Search activity'
        : 'Search chats';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
        ),
      ),
    );
  }

  Widget _buildChatsTab(List<AppRoom> rooms) {
    final filteredRooms = _filterRooms(rooms);

    if (filteredRooms.isEmpty) {
      final isSyncing = Get.find<AuthController>().client.prevBatch == null;
      if (isSyncing) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Syncing with Matrix...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }

      if (_searchQuery.isEmpty) {
        return _buildEmptyState(
          icon: Icons.forum_outlined,
          title: 'No chats yet',
          subtitle: 'Start a new conversation to see it here.',
        );
      }

      return _buildEmptyState(
        icon: Icons.forum_outlined,
        title: 'No chats match that search',
        subtitle: 'Try a different room name or message preview.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: filteredRooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) =>
          _buildChatItem(context, filteredRooms[index]),
    );
  }

  Widget _buildActivityTab(List<AppRoom> rooms) {
    final activityItems = _filterActivityItems(_buildActivityItems(rooms));

    if (activityItems.isEmpty) {
      final isSyncing = Get.find<AuthController>().client.prevBatch == null;
      if (isSyncing) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Syncing with Matrix...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }

      if (_searchQuery.isEmpty) {
        return _buildEmptyState(
          icon: Icons.bolt_outlined,
          title: 'Your activity feed is clear',
          subtitle:
              'Recent updates, replies, and room movement will land here.',
        );
      }

      return _buildEmptyState(
        icon: Icons.bolt_outlined,
        title: 'No activity matches that search',
        subtitle: 'Try a different term or clear your search.',
      );
    }

    final needsAttention = activityItems
        .where((item) => item.needsAttention)
        .toList();
    final activeToday = activityItems
        .where((item) => DateUtils.isSameDay(item.timestamp, DateTime.now()))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildActivitySummary(
          totalRooms: rooms.length,
          activeToday: activeToday,
          needsReply: needsAttention.length,
        ),
        const SizedBox(height: 20),
        if (needsAttention.isNotEmpty) ...[
          const Text(
            'Needs attention',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...needsAttention.take(3).map(_buildActivityCard),
          const SizedBox(height: 20),
        ],
        const Text(
          'Recent activity',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...activityItems.map(_buildActivityCard),
      ],
    );
  }

  Widget _buildMenuTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Matrix-first messaging',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Keep the shell lean: chats, lightweight activity, and the controls people actually use every day.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GetBuilder<SettingsController>(
          builder: (settingsController) {
            final settings = settingsController.state;
            if (settings == null ||
                !settings.encryptionEnabled ||
                settings.encryptedHistoryReady) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
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
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
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
                        color: Colors.black.withValues(alpha: 0.75),
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
                          onPressed: () => _openAppSettings(context),
                          icon: const Icon(Icons.tune),
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
          children: [
            _buildMenuTile(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle: 'Avatar, display name, and status note',
              onTap: () => _openProfile(context),
            ),
            _buildMenuTile(
              icon: Icons.tune,
              title: 'App settings',
              subtitle: _menuSettingsSubtitle(),
              onTap: () => _openAppSettings(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: () => Get.find<AuthController>().logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _buildActivitySummary({
    required int totalRooms,
    required int activeToday,
    required int needsReply,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Rooms',
            value: '$totalRooms',
            color: const Color(0xFFEAF3FF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Today',
            value: '$activeToday',
            color: const Color(0xFFEFF8EC),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Replies',
            value: '$needsReply',
            color: const Color(0xFFFFF1E5),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  Widget _buildChatItem(BuildContext context, AppRoom room) {
    final activityAt = _roomActivityAt(room);
    final preview = _roomPreview(room);
    final initial = room.displayname.isEmpty
        ? '#'
        : room.displayname.characters.first.toUpperCase();
    final client = Get.find<AuthController>().client;
    final avatarImageUrl = resolveAvatarImageUrl(
      room.avatarUrl,
      client,
      size: 112,
    );

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
            if (avatarImageUrl != null)
              CachedNetworkImage(
                imageUrl: avatarImageUrl,
                httpHeaders: {
                  if (client.accessToken != null)
                    'Authorization': 'Bearer ${client.accessToken}',
                },
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFEAF3FF),
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFEAF3FF),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  markAvatarSourceBroken(room.avatarUrl);
                  return CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFEAF3FF),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              )
            else
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFEAF3FF),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(_ActivityItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EDF5)),
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: TextStyle(
                            color: Colors.grey[500],
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
                        color: Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.preview,
                      style: TextStyle(
                        color: Colors.grey[800],
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, size: 32, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String title, String details) {
    return _buildEmptyState(
      icon: Icons.error_outline,
      title: title,
      subtitle: details,
    );
  }

  List<AppRoom> _filterRooms(List<AppRoom> rooms) {
    final normalizedQuery = _searchQuery.toLowerCase();
    final filteredRooms = normalizedQuery.isEmpty
        ? List<AppRoom>.from(rooms)
        : rooms.where((room) {
            final haystack = '${room.displayname} ${room.lastMessage ?? ''}'
                .toLowerCase();
            return haystack.contains(normalizedQuery);
          }).toList();

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
    final now = DateTime.now();
    final items = rooms.asMap().entries.map((entry) {
      final index = entry.key;
      final room = entry.value;
      final latestEvent = _latestEvent(room);
      final activityAt = _roomActivityAt(room);
      final preview = _roomPreview(room);

      if (latestEvent == null && room.lastMessage == null) {
        return _ActivityItem(
          room: room,
          title: room.displayname,
          preview: preview,
          caption: 'Room synced and ready',
          status: 'Synced',
          timestamp: now.subtract(Duration(minutes: (index + 1) * 11)),
          kind: _ActivityKind.quiet,
          needsAttention: false,
        );
      }

      final isIncoming = latestEvent != null
          ? !latestEvent.isMe
          : room.hasUnread;
      return _ActivityItem(
        room: room,
        title: room.displayname,
        preview: preview,
        caption: isIncoming ? 'New message waiting' : 'You sent an update',
        status: isIncoming ? 'Reply' : 'Sent',
        timestamp: activityAt,
        kind: isIncoming ? _ActivityKind.incoming : _ActivityKind.outgoing,
        needsAttention: isIncoming,
      );
    }).toList();

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
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

    if (lastEventTs != null && latestEvent != null) {
      if (lastEventTs.isAfter(latestEvent.originServerTs)) {
        return room.lastMessage ?? latestEvent.body;
      }
      return latestEvent.body;
    }

    return room.lastMessage ?? latestEvent?.body ?? 'No messages yet';
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

  String _headerSubtitle(_HomeTab tab) {
    return switch (tab) {
      _HomeTab.chats => 'Matrix conversations, kept simple',
      _HomeTab.activity => 'Recent updates across your rooms',
      _HomeTab.menu => 'Account controls and quick actions',
    };
  }

  IconData _headerActionIcon(_HomeTab tab) {
    return switch (tab) {
      _HomeTab.chats => Icons.edit_outlined,
      _HomeTab.activity => Icons.refresh_outlined,
      _HomeTab.menu => Icons.logout,
    };
  }

  String _headerActionMessage(_HomeTab tab) {
    return switch (tab) {
      _HomeTab.chats => 'Compose is a good next step for DotMatrix.',
      _HomeTab.activity =>
        'Pull-to-refresh or background sync would fit well here.',
      _HomeTab.menu => 'Signing out...',
    };
  }

  String _menuSettingsSubtitle() {
    final settings = Get.find<SettingsController>().state;
    if (settings == null) {
      return 'Notifications, appearance, encryption, and device safety';
    }
    if (settings.encryptionEnabled && !settings.encryptedHistoryReady) {
      return 'Finish encrypted history recovery for this device';
    }
    return 'Notifications, appearance, encryption, and device safety';
  }

  Future<void> _askDevicesAgain(BuildContext context) async {
    try {
      final message = await Get.find<SettingsController>()
          .requestEncryptedHistoryFromVerifiedDevices();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openAppSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
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
    required this.needsAttention,
  });

  final AppRoom room;
  final String title;
  final String preview;
  final String caption;
  final String status;
  final DateTime timestamp;
  final _ActivityKind kind;
  final bool needsAttention;

  Color get tint => switch (kind) {
    _ActivityKind.incoming => const Color(0xFFFF8A34),
    _ActivityKind.outgoing => AppTheme.primaryBlue,
    _ActivityKind.quiet => const Color(0xFF5C6B80),
  };

  IconData get icon => switch (kind) {
    _ActivityKind.incoming => Icons.mark_chat_unread_outlined,
    _ActivityKind.outgoing => Icons.north_east,
    _ActivityKind.quiet => Icons.done_all,
  };
}
