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
    if (!auth.isDummy && auth.status.isSuccess && auth.state != null) {
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
    if (auth.isDummy || auth.state == null || auth.status.isLoading) {
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
      if (auth.isDummy) {
        // Dummy data
        final dummyRooms = [
          AppRoom(
            id: 'room1',
            displayname: 'General Chat',
            lastMessage: 'Hey everyone!',
            messages: [
              AppEvent(
                senderId: 'user1',
                body: 'Hello!',
                originServerTs: DateTime.now().subtract(
                  const Duration(minutes: 10),
                ),
                isMe: false,
              ),
              AppEvent(
                senderId: 'dummy_user',
                body: 'Hi there!',
                originServerTs: DateTime.now().subtract(
                  const Duration(minutes: 5),
                ),
                isMe: true,
              ),
              AppEvent(
                senderId: 'user1',
                body: 'How are you?',
                originServerTs: DateTime.now().subtract(
                  const Duration(minutes: 2),
                ),
                isMe: false,
              ),
            ],
          ),
          AppRoom(
            id: 'room2',
            displayname: 'Work Team',
            lastMessage: 'Meeting at 3 PM',
            messages: [
              AppEvent(
                senderId: 'user2',
                body: 'Meeting at 3 PM',
                originServerTs: DateTime.now().subtract(
                  const Duration(hours: 1),
                ),
                isMe: false,
              ),
              AppEvent(
                senderId: 'dummy_user',
                body: 'Got it!',
                originServerTs: DateTime.now().subtract(
                  const Duration(minutes: 30),
                ),
                isMe: true,
              ),
            ],
          ),
          AppRoom(
            id: 'room3',
            displayname: 'John Doe',
            lastMessage: 'See you tomorrow!',
            messages: [
              AppEvent(
                senderId: 'john_doe',
                body: 'Hey, how was your day?',
                originServerTs: DateTime.now().subtract(
                  const Duration(hours: 2),
                ),
                isMe: false,
              ),
              AppEvent(
                senderId: 'dummy_user',
                body: 'It was good, thanks! Busy with work.',
                originServerTs: DateTime.now().subtract(
                  const Duration(hours: 1, minutes: 45),
                ),
                isMe: true,
              ),
              AppEvent(
                senderId: 'john_doe',
                body: 'Same here. See you tomorrow!',
                originServerTs: DateTime.now().subtract(
                  const Duration(minutes: 30),
                ),
                isMe: false,
              ),
            ],
          ),
        ];
        change(dummyRooms, status: RxStatus.success());
      } else {
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
                      body: matrixEventDisplayText(e, timeline: timeline),
                      originServerTs: e.originServerTs,
                      isMe: e.senderId == client.userID,
                    ),
                  )
                  .toList();

              return AppRoom(
                id: room.id,
                displayname: room.getLocalizedDisplayname(),
                lastMessage: room.lastEvent == null
                    ? null
                    : matrixEventDisplayText(room.lastEvent!),
                hasUnread: room.hasNewMessages,
                messages: messages,
              );
            });

        final rooms = await Future.wait(roomFutures);
        change(rooms, status: RxStatus.success());
      }
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }

    _isLoadingRooms = false;
    if (_needsReload) {
      Future.microtask(() => _loadRoomsInternal());
    }
  }
}
