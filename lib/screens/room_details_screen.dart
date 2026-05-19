import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/room_model.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/bridge_detector.dart';
import '../widgets/dot_matrix_loader.dart';
import '../widgets/room_avatar_grid.dart';

class RoomDetailsScreen extends StatefulWidget {
  final AppRoom room;

  const RoomDetailsScreen({super.key, required this.room});

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  bool _isLoadingMembers = true;
  List<User> _members = [];
  String? _topic;
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRoomInfo();
  }

  Future<void> _loadRoomInfo() async {
    final client = Get.find<AuthController>().client;
    final room = client.getRoomById(widget.room.id);
    if (room == null) {
      setState(() => _isLoadingMembers = false);
      return;
    }

    try {
      final participants = room.getParticipants();
      final alsoMe = Get.find<SettingsController>().state?.alsoMeUserIds ?? [];
      final realMembers = participants.where((m) {
        if (alsoMe.contains(m.id)) return false;
        return !BridgeDetector.isBridgeBot(
          m.id,
          displayName: m.displayName,
        );
      }).toList();
      final topic = room.topic;
      setState(() {
        _members = realMembers;
        _memberCount = realMembers.length;
        _topic = topic;
        _isLoadingMembers = false;
      });
    } catch (e) {
      setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _leaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave chat?'),
        content: Text(
          'You will leave "${widget.room.displayname}". This removes it from your room list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room != null) {
        await room.leave();
        await Get.find<RoomController>().refreshRooms();
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        Get.snackbar('Error', 'Could not leave room: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final client = Get.find<AuthController>().client;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Chat Info',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // Room header
                  Row(
                    children: [
                      RoomAvatarGrid(
                        avatarUrl: widget.room.avatarUrl,
                        memberAvatarUrls: widget.room.memberAvatarUrls,
                        size: 64,
                        fallbackInitial: widget.room.displayname.isNotEmpty
                            ? widget.room.displayname[0].toUpperCase()
                            : '?',
                        backgroundColor: cs.secondaryContainer,
                        fallbackColor: cs.secondary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.room.displayname,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_memberCount members',
                              style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Topic
                  if (_topic != null && _topic!.isNotEmpty) ...[
                    Text(
                      'Topic',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _topic!,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Members section
                  Text(
                    'Members',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingMembers)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: DotMatrixLoader(size: 28, dotSize: 4),
                      ),
                    )
                  else if (_members.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No members found',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._members.map((member) {
                      final avatarUrl = member.avatarUrl;
                      final resolved = avatarUrl != null
                          ? resolveAvatarImageUrl(
                              avatarUrl,
                              client,
                              size: 80,
                            )
                          : null;
                      final displayName = member.displayName ?? member.id.localpart ?? member.id;
                      final isMe = member.id == client.userID;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.secondaryContainer,
                              ),
                              child: resolved != null
                                  ? ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl: resolved,
                                        httpHeaders: {
                                          if (client.accessToken != null)
                                            'Authorization': 'Bearer ${client.accessToken}',
                                        },
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => _fallbackAvatar(displayName, cs),
                                        errorWidget: (_, __, ___) => _fallbackAvatar(displayName, cs),
                                      ),
                                    )
                                  : _fallbackAvatar(displayName, cs),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (isMe)
                                    Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            // Leave room button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _leaveRoom,
                  icon: Icon(
                    Icons.logout,
                    color: cs.error,
                  ),
                  label: Text(
                    'Leave Chat',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackAvatar(String displayName, ColorScheme cs) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '#';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }
}
