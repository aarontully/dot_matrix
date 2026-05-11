import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/room_model.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

enum _HomeTab { chats, activity, menu }

enum _ActivityKind { incoming, outgoing, quiet }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsProvider);
    final selectedTab = _HomeTab.values[_selectedIndex];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, selectedTab),
            if (selectedTab != _HomeTab.menu) _buildSearchBar(selectedTab),
            Expanded(
              child: switch (selectedTab) {
                _HomeTab.chats => roomsAsync.when(
                  data: _buildChatsTab,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _buildErrorState(
                    'We could not load your rooms yet.',
                    error.toString(),
                  ),
                ),
                _HomeTab.activity => roomsAsync.when(
                  data: _buildActivityTab,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _buildErrorState(
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
            onTap: () => _openSettings(context),
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
            icon: Icon(_headerActionIcon(tab), color: Colors.black87),
            onPressed: () {
              if (tab == _HomeTab.menu) {
                ref.read(authProvider.notifier).logout();
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
      return _buildEmptyState(
        icon: Icons.bolt_outlined,
        title: 'Your activity feed is clear',
        subtitle: 'Recent updates, replies, and room movement will land here.',
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
        _buildMenuSection(
          children: [
            _buildMenuTile(
              icon: Icons.person_outline,
              title: 'Profile & settings',
              subtitle: 'Account, appearance, privacy, and sessions',
              onTap: () => _openSettings(context),
            ),
            _buildMenuTile(
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: 'Fine-tune room and direct message alerts',
              onTap: () => _openSettings(context),
            ),
            _buildMenuTile(
              icon: Icons.security_outlined,
              title: 'Session safety',
              subtitle: 'Review devices and keep sign-in simple',
              onTap: () => _openSettings(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(authProvider.notifier).logout(),
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

    filteredRooms.sort(
      (a, b) => _roomActivityAt(b).compareTo(_roomActivityAt(a)),
    );
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
      final timestamp =
          latestEvent?.originServerTs ??
          now.subtract(Duration(minutes: (index + 1) * 11));
      final preview = _roomPreview(room);

      if (latestEvent == null) {
        return _ActivityItem(
          room: room,
          title: room.displayname,
          preview: preview,
          caption: 'Room synced and ready',
          status: 'Synced',
          timestamp: timestamp,
          kind: _ActivityKind.quiet,
          needsAttention: false,
        );
      }

      final isIncoming = !latestEvent.isMe;
      return _ActivityItem(
        room: room,
        title: room.displayname,
        preview: latestEvent.body,
        caption: isIncoming ? 'New message waiting' : 'You sent an update',
        status: isIncoming ? 'Reply' : 'Sent',
        timestamp: latestEvent.originServerTs,
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
    return latestEvent?.originServerTs ?? DateTime.now();
  }

  String _roomPreview(AppRoom room) {
    final latestEvent = _latestEvent(room);
    return latestEvent?.body ?? room.lastMessage ?? 'No messages yet';
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

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
