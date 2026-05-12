import 'dart:async';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';
import '../models/room_model.dart';
import '../utils/matrix_event_display.dart';
import 'auth_controller.dart';

class RoomController extends GetxController with StateMixin<List<AppRoom>> {
  StreamSubscription? _syncSubscription;
  StreamSubscription<String>? _secretStoredSubscription;
  final Map<String, Timeline> _timelines = {};
  bool _isLoadingRooms = false;
  bool _needsReload = false;

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

  String _cleanRoomName(String name) {
    var prefix = '';
    var content = name;

    if (name.startsWith('Group with ')) {
      prefix = 'Group with ';
      content = name.substring('Group with '.length);
    }

    var parts = content.split(',').map((p) => p.trim()).toList();

    // Remove any user whose name contains 'bot' (case-insensitive)
    parts.removeWhere((part) => part.toLowerCase().contains('bot'));

    var cleaned = parts.join(', ').trim();
    if (prefix.isNotEmpty && cleaned.isNotEmpty) {
      cleaned = prefix + cleaned;
    }

    if (cleaned.isEmpty || cleaned == 'Group with') {
      return 'Empty Group';
    }

    return cleaned;
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

      final roomFutures = client.rooms
          .where((room) => room.membership == Membership.join)
          .map((room) async {
            final timeline = await _timelineFor(room);
            if (client.encryptionEnabled) {
              timeline.requestKeys(
                tryOnlineBackup: true,
                onlineKeyBackupOnly: false,
              );
            }

            final messages = timeline.events
                .where(
                  (e) =>
                      e.type == EventTypes.Message ||
                      e.type == EventTypes.Encrypted,
                )
                .map(
                  (e) => AppEvent(
                    senderId: e.senderId,
                    senderName: e.senderFromMemoryOrFallback.calcDisplayname(),
                    senderAvatarUrl: e.senderFromMemoryOrFallback.avatarUrl,
                    body: matrixEventDisplayText(e, timeline: timeline),
                    originServerTs: e.originServerTs,
                    isMe: e.senderId == client.userID,
                  ),
                )
                .toList();

            return AppRoom(
              id: room.id,
              displayname: _cleanRoomName(room.getLocalizedDisplayname()),
              lastMessage: room.lastEvent == null
                  ? null
                  : matrixEventDisplayText(room.lastEvent!, timeline: timeline),
              lastEventTs: room.lastEvent?.originServerTs,
              hasUnread: room.hasNewMessages,
              messages: messages,
              avatarUrl: room.avatar,
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
}
