import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';
import '../models/room_model.dart';
import '../utils/bridge_detector.dart';
import '../utils/matrix_event_display.dart';
import 'auth_controller.dart';
import 'settings_controller.dart';

class RoomController extends GetxController with StateMixin<List<AppRoom>> {
  StreamSubscription? _syncSubscription;
  StreamSubscription<String>? _secretStoredSubscription;
  final Map<String, Timeline> _timelines = {};
  bool _isLoadingRooms = false;
  bool _needsReload = false;

  /// Currently selected space filter. null = show all rooms.
  final Rx<String?> selectedSpaceId = Rx<String?>(null);

  @override
  void onInit() {
    super.onInit();
    Get.find<AuthController>().addListener(() {
      _setupSyncListener();
      _queueLoadRooms();
    });
    _setupSyncListener();
    _queueLoadRooms();
  }

  void _setupSyncListener() {
    _syncSubscription?.cancel();
    _secretStoredSubscription?.cancel();
    final auth = Get.find<AuthController>();
    if (auth.status.isSuccess && auth.state != null) {
      _syncSubscription = auth.client.onSync.stream.listen((_) {
        _queueLoadRooms();
      });
      final encryption = auth.client.encryption;
      if (encryption != null) {
        _secretStoredSubscription = encryption.ssss.onSecretStored.stream
            .listen((_) async {
              if (await encryption.keyManager.isCached()) {
                await encryption.keyManager.loadAllKeys();
              }
              await requestMissingEncryptionKeys();
              await refreshRooms(rebuildTimelines: true);
            });
      }
    }
  }

  @override
  void onClose() {
    _syncSubscription?.cancel();
    _secretStoredSubscription?.cancel();
    for (final timeline in _timelines.values) {
      timeline.cancelSubscriptions();
    }
    super.onClose();
  }

  void _queueLoadRooms() {
    if (_isLoadingRooms) {
      _needsReload = true;
      return;
    }
    _loadRoomsInternal();
  }

  Future<void> refreshRooms({bool rebuildTimelines = false}) async {
    if (rebuildTimelines) {
      for (final timeline in _timelines.values) {
        timeline.cancelSubscriptions();
      }
      _timelines.clear();
    }
    if (_isLoadingRooms) {
      _needsReload = true;
      return;
    }
    await _loadRoomsInternal();
  }

  Future<void> requestMissingEncryptionKeys() async {
    final auth = Get.find<AuthController>();
    if (auth.state == null || auth.status.isLoading) {
      return;
    }

    final client = auth.client;
    await client.roomsLoading;
    for (final room in client.rooms.where(
      (room) => room.membership == Membership.join,
    )) {
      final timeline = await _timelineFor(room);
      timeline.requestKeys(tryOnlineBackup: true, onlineKeyBackupOnly: false);
    }
  }

  Future<Timeline> _timelineFor(Room room) async {
    if (_timelines.containsKey(room.id)) {
      return _timelines[room.id]!;
    }
    final timeline = await room.getTimeline(
      onChange: (event) {
        _queueLoadRooms();
      },
    );
    _timelines[room.id] = timeline;
    return timeline;
  }

  bool canRequestRoomHistory(String roomId) {
    final timeline = _timelines[roomId];
    return timeline?.canRequestHistory ?? false;
  }

  Future<void> requestRoomHistory(
    String roomId, {
    int historyCount = 40,
  }) async {
    final timeline = _timelines[roomId];
    if (timeline == null || !timeline.canRequestHistory) return;
    try {
      await timeline.requestHistory(historyCount: historyCount);
    } catch (e) {
      debugPrint('History request failed: $e');
    }
  }

  String _cleanRoomName(String name) {
    var content = name;

    if (name.startsWith('Group with ')) {
      content = name.substring('Group with '.length);
    }

    var parts = content.split(',').map((p) => p.trim()).toList();

    // Remove any user whose name contains 'bot' (case-insensitive)
    parts.removeWhere((part) => part.toLowerCase().contains('bot'));

    var cleaned = parts.join(', ').trim();

    if (cleaned.isEmpty) {
      return 'Empty Group';
    }

    return cleaned;
  }

  /// Badge count: prefer homeserver [Room.notificationCount], else at least 1
  /// when there are new messages or the room is marked unread.
  int _unreadBadgeCount(Room room) {
    var n = room.notificationCount;
    if (n <= 0 && (room.hasNewMessages || room.markedUnread)) {
      n = 1;
    }
    return n < 0 ? 0 : n;
  }

  String? _attachmentLogicalKey(Event event) {
    final candidates = <String?>[
      event.content['filename'] as String?,
      event.content['body'] as String?,
      event.content['name'] as String?,
    ];

    final waitingBody = (event.content['body'] as String?) ?? event.body;
    final waitingMatch = RegExp(
      r'^(?:Waiting for attachment|Failed to transfer attachment)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(waitingBody);
    if (waitingMatch != null) {
      final key = waitingMatch.group(1)?.trim().toLowerCase();
      if (key != null && key.isNotEmpty) return key;
    }

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final cleaned = candidate.trim().toLowerCase();
      if (cleaned.isEmpty) continue;
      final stemMatch = RegExp(
        r'^(.+?)(?:\.[a-z0-9]{1,5})?$',
      ).firstMatch(cleaned);
      final stem = stemMatch?.group(1)?.trim();
      if (stem != null && stem.isNotEmpty) return stem;
    }

    return null;
  }

  bool _hasRenderableMedia(Event event) {
    final type = event.messageType;
    if (type == MessageTypes.Image ||
        type == MessageTypes.Video ||
        type == MessageTypes.Sticker) {
      return true;
    }
    if (event.content['url'] is String || event.content['file'] is Map) {
      return true;
    }
    final info = event.content['info'];
    if (info is Map) {
      final mime = (info['mimetype'] as String?)?.toLowerCase() ?? '';
      if (mime.startsWith('image/') || mime.startsWith('video/')) {
        return true;
      }
    }
    return false;
  }

  bool _isProvisionalGMessagesMedia(Event event) {
    final body = ((event.content['body'] as String?) ?? event.body).trim();
    final hasDebugData =
        event.content['fi.mau.gmessages.raw_debug_data'] is String;
    final isWaiting =
        body.startsWith('Waiting for attachment ') ||
        body.startsWith('Failed to transfer attachment ');
    return event.messageType == MessageTypes.Notice &&
        (hasDebugData || isWaiting) &&
        !_hasRenderableMedia(event);
  }

  Event? _resolveBetterBridgeMediaEvent(
    Event event,
    Timeline timeline,
    List<Event> allTimelineEvents,
  ) {
    if (!_isProvisionalGMessagesMedia(event)) return null;
    final key = _attachmentLogicalKey(event);
    if (key == null) return null;

    Event? best;
    for (final candidate in allTimelineEvents) {
      if (candidate.senderId != event.senderId) continue;
      final displayCandidate = candidate.getDisplayEvent(timeline);
      if (!_hasRenderableMedia(displayCandidate)) continue;

      final candidateKeys = <String?>{
        _attachmentLogicalKey(candidate),
        _attachmentLogicalKey(displayCandidate),
      };
      if (!candidateKeys.contains(key)) continue;

      if (best == null ||
          displayCandidate.originServerTs.isAfter(best.originServerTs)) {
        best = displayCandidate;
      }
    }

    return best;
  }

  List<AppEvent> _collapseBridgeMediaPlaceholders(List<AppEvent> events) {
    final bestBySenderAndKey = <String, AppEvent>{};

    for (final event in events) {
      final key = _attachmentLogicalKey(event.displayEvent);
      if (key == null) continue;
      final compoundKey = '${event.senderId}::$key';
      final existing = bestBySenderAndKey[compoundKey];
      if (existing == null) {
        bestBySenderAndKey[compoundKey] = event;
        continue;
      }

      final existingRenderable = _hasRenderableMedia(existing.displayEvent);
      final currentRenderable = _hasRenderableMedia(event.displayEvent);
      if (!existingRenderable && currentRenderable) {
        bestBySenderAndKey[compoundKey] = event;
      } else if (existingRenderable == currentRenderable &&
          event.originServerTs.isAfter(existing.originServerTs)) {
        bestBySenderAndKey[compoundKey] = event;
      }
    }

    return events.where((event) {
      if (!_isProvisionalGMessagesMedia(event.displayEvent)) return true;
      final key = _attachmentLogicalKey(event.displayEvent);
      if (key == null) return true;
      final compoundKey = '${event.senderId}::$key';
      final best = bestBySenderAndKey[compoundKey];
      if (best == null) return true;
      return identical(best, event) ||
          best.rawEvent.eventId == event.rawEvent.eventId;
    }).toList();
  }

  Future<void> _loadRoomsInternal() async {
    _isLoadingRooms = true;
    _needsReload = false;

    final auth = Get.find<AuthController>();

    // Wait for auth to be success and state to not be null
    if (auth.status.isLoading) {
      change(null, status: RxStatus.loading());
      _isLoadingRooms = false;
      return;
    }

    if (auth.state == null && auth.status.isSuccess) {
      change([], status: RxStatus.success());
      _isLoadingRooms = false;
      return;
    }

    if (state == null) {
      change(null, status: RxStatus.loading());
    }

    try {
      final client = auth.client;
      await client.roomsLoading;

      // Build a map of child room ID -> parent space IDs from all space rooms.
      // This is more reliable than reading m.space.parent from each room,
      // since the SDK's spaceParents getter filters out entries with empty via.
      final roomToSpaceParents = <String, List<String>>{};
      for (final spaceRoom in client.rooms) {
        if (spaceRoom.membership != Membership.join) continue;
        final childStates = spaceRoom.states[EventTypes.spaceChild];
        if (childStates != null) {
          for (final entry in childStates.entries) {
            final childRoomId = entry.key;
            if (childRoomId.isEmpty) continue;
            roomToSpaceParents
                .putIfAbsent(childRoomId, () => [])
                .add(spaceRoom.id);
          }
        }
      }

      final roomFutures = client.rooms
          .where((room) => room.membership == Membership.join && !room.isSpace)
          .map((room) async {
            final timeline = await _timelineFor(room);
            final allTimelineEvents = List<Event>.from(timeline.events);
            if (client.encryptionEnabled) {
              timeline.requestKeys(
                tryOnlineBackup: true,
                onlineKeyBackupOnly: false,
              );
            }

            final messages = _collapseBridgeMediaPlaceholders(
              timeline.events
                  .where(
                    (e) =>
                        (e.type == EventTypes.Message ||
                            e.type == EventTypes.Encrypted ||
                            e.type == EventTypes.Sticker) &&
                        e.relationshipType != RelationshipTypes.edit,
                  )
                  .map((e) {
                    final reactionEvents =
                        timeline.aggregatedEvents[e.eventId]?['m.annotation'] ??
                        <Event>{};
                    final reactionCounts = <String, int>{};
                    final myReactionEventIds = <String, String>{};
                    final reactionSenders = <String, List<ReactionSender>>{};
                    for (final r in reactionEvents) {
                      final relatesTo =
                          r.content['m.relates_to'] as Map<String, dynamic>?;
                      final key = relatesTo?['key'] as String?;
                      if (key != null && key.isNotEmpty) {
                        reactionCounts[key] = (reactionCounts[key] ?? 0) + 1;
                        final sender = ReactionSender(
                          id: r.senderId,
                          name: r.senderFromMemoryOrFallback.calcDisplayname(),
                          avatarUrl: r.senderFromMemoryOrFallback.avatarUrl,
                        );
                        reactionSenders.putIfAbsent(key, () => []).add(sender);
                        if (r.senderId == client.userID) {
                          myReactionEventIds[key] = r.eventId;
                        }
                      }
                    }
                    final displayEvent =
                        _resolveBetterBridgeMediaEvent(
                          e,
                          timeline,
                          allTimelineEvents,
                        ) ??
                        e.getDisplayEvent(timeline);
                    return AppEvent(
                      senderId: e.senderId,
                      senderName: e.senderFromMemoryOrFallback
                          .calcDisplayname(),
                      senderAvatarUrl: e.senderFromMemoryOrFallback.avatarUrl,
                      body: matrixEventDisplayText(displayEvent),
                      originServerTs: e.originServerTs,
                      isMe: e.senderId == client.userID,
                      rawEvent: e,
                      displayEvent: displayEvent,
                      reactions: reactionCounts,
                      myReactions: myReactionEventIds,
                      reactionSenders: reactionSenders,
                      isEdited: e.hasAggregatedEvents(
                        timeline,
                        RelationshipTypes.edit,
                      ),
                    );
                  })
                  .toList(),
            );

            final unread = _unreadBadgeCount(room);

            // Collect member count, avatars, and detect bridge platform
            final memberAvatars = <Uri>[];
            var memberCount = 0;
            var bridgePlatform = BridgePlatform.unknown;
            try {
              final members = await room.requestParticipants();
              final alsoMe =
                  Get.find<SettingsController>().state?.alsoMeUserIds ?? [];
              final realMembers = members.where((m) {
                if (m.id == client.userID) return false;
                if (alsoMe.contains(m.id)) return false;
                return !BridgeDetector.isBridgeBot(
                  m.id,
                  displayName: m.displayName,
                );
              }).toList();
              memberCount = realMembers.length + 1; // +1 for current user
              final memberIds = realMembers.map((m) => m.id).toList();
              bridgePlatform = BridgeDetector.detectFromMembers(
                memberIds,
                client.userID ?? '',
              );
              if (room.avatar == null) {
                for (final member in realMembers) {
                  if (member.avatarUrl != null) {
                    memberAvatars.add(member.avatarUrl!);
                  }
                  if (memberAvatars.length >= 4) break;
                }
              }
            } catch (e) {
              debugPrint('Participant fetch failed: $e');
            }

            final spaceParentIds = roomToSpaceParents[room.id] ?? [];

            // Find latest reaction from someone else for the activity feed
            AppReactionActivity? latestReactionActivity;
            for (final ev in timeline.events) {
              if (ev.type != EventTypes.Reaction) continue;
              if (ev.senderId == client.userID) continue;
              final relatesTo =
                  ev.content['m.relates_to'] as Map<String, dynamic>?;
              final emoji = relatesTo?['key'] as String?;
              final targetId = relatesTo?['event_id'] as String?;
              if (emoji == null || targetId == null) continue;
              String targetBody = 'a message';
              final targetEvent = timeline.events.firstWhereOrNull(
                (e) => e.eventId == targetId,
              );
              if (targetEvent != null) {
                targetBody = matrixEventDisplayText(
                  targetEvent,
                  timeline: timeline,
                );
              }
              final activity = AppReactionActivity(
                senderId: ev.senderId,
                senderName: ev.senderFromMemoryOrFallback.calcDisplayname(),
                emoji: emoji,
                targetMessageBody: targetBody,
                timestamp: ev.originServerTs,
              );
              if (latestReactionActivity == null ||
                  activity.timestamp.isAfter(
                    latestReactionActivity.timestamp,
                  )) {
                latestReactionActivity = activity;
              }
            }

            return AppRoom(
              id: room.id,
              displayname: _cleanRoomName(room.getLocalizedDisplayname()),
              lastMessage: room.lastEvent == null
                  ? null
                  : matrixEventDisplayText(room.lastEvent!, timeline: timeline),
              lastEventTs: room.lastEvent?.originServerTs,
              hasUnread: unread > 0,
              unreadCount: unread,
              messages: messages,
              avatarUrl: room.avatar,
              memberAvatarUrls: memberAvatars,
              isGroup: memberCount > 2,
              spaceParentIds: spaceParentIds,
              latestReactionActivity: latestReactionActivity,
              bridgePlatform: bridgePlatform,
            );
          });

      final rooms = await Future.wait(roomFutures);
      change(rooms, status: RxStatus.success());
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }

    _isLoadingRooms = false;
    if (_needsReload) {
      Future.microtask(() => _loadRoomsInternal());
    }
  }

  /// Returns the list of spaces the user is in, for the filter UI.
  List<Map<String, String>> get spaces {
    final auth = Get.find<AuthController>();
    if (auth.state == null) return [];
    return auth.client.rooms
        .where((r) => r.membership == Membership.join && r.isSpace)
        .map((r) => {'id': r.id, 'name': r.getLocalizedDisplayname()})
        .toList();
  }
}
