import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/room_controller.dart';
import '../models/room_model.dart';
import '../widgets/room_avatar_grid.dart';
import 'chat_screen.dart';

class SpaceRoomsScreen extends StatelessWidget {
  const SpaceRoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomController = Get.find<RoomController>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leadingWidth: 40,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.secondary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Rooms'),
      ),
      body: roomController.obx(
        (rooms) {
          if (rooms == null || rooms.isEmpty) {
            return const Center(child: Text('No rooms'));
          }
          return _SpaceRoomsList(rooms: rooms);
        },
        onLoading: const Center(child: CircularProgressIndicator()),
        onError: (error) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _SpaceRoomsList extends StatelessWidget {
  final List<AppRoom> rooms;

  const _SpaceRoomsList({required this.rooms});

  @override
  Widget build(BuildContext context) {
    final roomController = Get.find<RoomController>();
    final spaces = roomController.spaces;

    // Group rooms by space ID
    final spaceRooms = <String, List<AppRoom>>{};
    final ungroupedRooms = <AppRoom>[];

    for (final room in rooms) {
      if (room.spaceParentIds.isEmpty) {
        ungroupedRooms.add(room);
      } else {
        for (final spaceId in room.spaceParentIds) {
          spaceRooms.putIfAbsent(spaceId, () => []).add(room);
        }
      }
    }

    // Build sections in order: spaces first, then ungrouped
    final sections = <_Section>[];

    for (final space in spaces) {
      final spaceId = space['id']!;
      final spaceName = space['name'] ?? 'Space';
      final roomsInSpace = spaceRooms[spaceId] ?? [];
      if (roomsInSpace.isNotEmpty) {
        sections.add(_Section(title: spaceName, rooms: roomsInSpace));
      }
    }

    if (ungroupedRooms.isNotEmpty) {
      sections.add(_Section(title: 'Other', rooms: ungroupedRooms));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return _SectionCard(section: section);
      },
    );
  }
}

class _Section {
  final String title;
  final List<AppRoom> rooms;

  _Section({required this.title, required this.rooms});
}

class _SectionCard extends StatelessWidget {
  final _Section section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                section.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const Divider(height: 1),
            ...section.rooms.map((room) => _RoomTile(room: room)),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final AppRoom room;

  const _RoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = room.displayname.isNotEmpty
        ? room.displayname[0].toUpperCase()
        : '#';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            RoomAvatarGrid(
              avatarUrl: room.avatarUrl,
              memberAvatarUrls: room.memberAvatarUrls,
              size: 44,
              fallbackInitial: initial,
              backgroundColor: cs.secondaryContainer,
              fallbackColor: cs.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.displayname,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (room.lastMessage != null && room.lastMessage!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        room.lastMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (room.hasUnread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
