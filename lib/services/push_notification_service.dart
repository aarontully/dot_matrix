import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../screens/chat_screen.dart';
import '../utils/matrix_event_display.dart';

const String _messagesChannelId = 'dot_matrix_messages';
const String _mentionsChannelId = 'dot_matrix_mentions';
const String _androidPusherAppId = 'com.housetully.dotmatrix.android';
const String _iosPusherAppId = 'com.housetully.dotmatrix.ios';
const String _macosPusherAppId = 'com.housetully.dotmatrix.macos';
const String _notificationIcon = '@drawable/ic_notification';
const String _notificationActionMarkRead = 'mark_read';
const String _notificationActionOpen = 'open_room';

final FlutterLocalNotificationsPlugin _backgroundLocalNotifications =
    FlutterLocalNotificationsPlugin();
bool _backgroundNotificationsInitialized = false;

String _firebaseSetupHint() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return '[Push] Android Firebase setup requires '
          '`android/app/google-services.json` so the Google Services Gradle '
          'plugin can generate FirebaseOptions resources.';
    case TargetPlatform.iOS:
      return '[Push] iOS Firebase setup requires '
          '`ios/Runner/GoogleService-Info.plist`, the Push Notifications '
          'capability, Background Modes > Remote notifications, and an APNs '
          'key/certificate uploaded in Firebase.';
    default:
      return '[Push] Background push also requires a working Matrix push '
          'gateway URL to be registered for the signed-in device.';
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[Push] Background Firebase init failed: $error');
      debugPrint(_firebaseSetupHint());
    }
  }

  final data = message.data;
  final notification = message.notification;

  var title =
      notification?.title ?? data['sender_display_name'] ?? 'New message';
  var body =
      notification?.body ?? data['content']?['body'] ?? data['body'] ?? '';

  if (body.isEmpty && data['unread'] != null) {
    final count = int.tryParse(data['unread'].toString()) ?? 1;
    body = count == 1
        ? 'You have a new message'
        : 'You have $count new messages';
  }

  await _ensureBackgroundNotificationsInitialized();

  await _backgroundLocalNotifications.show(
    _notificationIdFromTimestamp(DateTime.now()),
    title,
    body,
    _notificationDetails(highlight: false),
    payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
void _notificationTapBackground(NotificationResponse details) {
  unawaited(
    _enqueuePendingNotificationResponse(
      actionId: details.actionId,
      payload: details.payload,
    ),
  );
}

class PushNotificationService with WidgetsBindingObserver {
  static const _pluginInitializationTimeout = Duration(seconds: 5);

  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<SyncUpdate>? _syncSubscription;
  bool _initialized = false;
  bool _localNotificationsReady = false;
  String? _currentToken;
  String? _activeRoomId;
  String? _boundUserId;
  String? _pendingOpenRoomPayload;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  final Map<String, _RoomNotificationSnapshot> _roomSnapshots = {};

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      _messaging!.onTokenRefresh.listen(_onTokenRefresh);
      _currentToken = await _loadCurrentPushKey();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Push] Firebase not configured: $error');
        debugPrint(_firebaseSetupHint());
      }
      _messaging = null;
    }

    try {
      const androidSettings = AndroidInitializationSettings(_notificationIcon);
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );
      await _localNotifications
          .initialize(
            initSettings,
            onDidReceiveNotificationResponse: _handleNotificationResponse,
            onDidReceiveBackgroundNotificationResponse:
                _notificationTapBackground,
          )
          .timeout(_pluginInitializationTimeout);

      await _createChannels().timeout(_pluginInitializationTimeout);
      WidgetsBinding.instance.addObserver(this);
      _localNotificationsReady = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Push] Local notifications unavailable: $error');
      }
      _localNotificationsReady = false;
    }

    _initialized = true;
    if (_localNotificationsReady) {
      await _processPendingNotificationResponses();
    }
  }

  Future<void> bindClient(Client client) async {
    await initialize();
    _syncSubscription?.cancel();
    _boundUserId = client.userID;
    _seedRoomSnapshots(client);
    _syncSubscription = client.onSync.stream.listen(
      (syncUpdate) => _handleSyncUpdate(client, syncUpdate),
    );
    await _processPendingNotificationResponses();
    _tryHandlePendingNavigation();
  }

  void unbindClient() {
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _boundUserId = null;
    _activeRoomId = null;
    _roomSnapshots.clear();
  }

  void setActiveRoom(String? roomId) {
    _activeRoomId = roomId;
  }

  void tryOpenPendingRoom() {
    _tryHandlePendingNavigation();
  }

  Future<bool> requestPermission() async {
    await initialize();

    var granted = false;

    if (_messaging != null) {
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = _isAuthorized(settings.authorizationStatus);
      debugPrint(
        '[Push] Firebase permission status: ${settings.authorizationStatus}',
      );
    }

    final androidGranted = await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final iosGranted = await _localNotifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final macGranted = await _localNotifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    granted =
        granted ||
        androidGranted == true ||
        iosGranted == true ||
        macGranted == true;

    if (androidGranted == null &&
        iosGranted == null &&
        macGranted == null &&
        _messaging == null) {
      // Platforms without runtime notification permission simply no-op here.
      granted = true;
    }

    return granted;
  }

  Future<void> registerPusher(String pushGatewayUrl) async {
    if (_messaging == null) return;
    _currentToken ??= await _loadCurrentPushKey();
    if (_currentToken == null) {
      return;
    }

    final client = Get.find<AuthController>().client;
    final deviceId = client.deviceID ?? 'unknown';
    final appId = _platformPusherAppId();
    if (appId == null) {
      return;
    }

    final pusher = Pusher(
      appId: appId,
      pushkey: _currentToken!,
      appDisplayName: 'Dot Matrix',
      data: PusherData(url: Uri.parse(pushGatewayUrl)),
      deviceDisplayName: deviceId,
      kind: 'http',
      lang: 'en',
    );

    try {
      await client.postPusher(pusher, append: false);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Push] Failed to register pusher: $error');
      }
    }
  }

  Future<void> unregisterPusher() async {
    if (_currentToken == null) return;

    final client = Get.find<AuthController>().client;
    final appId = _platformPusherAppId();
    if (appId == null) return;
    final pusherId = PusherId(appId: appId, pushkey: _currentToken!);

    try {
      await client.deletePusher(pusherId);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Push] Failed to unregister pusher: $error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  Future<void> _handleSyncUpdate(Client client, SyncUpdate syncUpdate) async {
    final joinUpdates = syncUpdate.rooms?.join;
    if (joinUpdates == null || joinUpdates.isEmpty) {
      _pruneSnapshots(client);
      return;
    }

    for (final entry in joinUpdates.entries) {
      final roomId = entry.key;
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) continue;

      final previous =
          _roomSnapshots[roomId] ?? _RoomNotificationSnapshot.fromRoom(room);
      final current = _RoomNotificationSnapshot.fromRoom(room);
      _roomSnapshots[roomId] = current;

      if (!_shouldShowSyncNotification(
        roomId: roomId,
        previous: previous,
        current: current,
      )) {
        continue;
      }

      final event = _pickNotificationEvent(
        room: room,
        update: entry.value,
        ownUserId: _boundUserId,
      );
      if (event == null) continue;

      final isHighlight = current.highlightCount > previous.highlightCount;
      await _showEventNotification(
        room: room,
        event: event,
        isHighlight: isHighlight,
      );
    }

    _pruneSnapshots(client);
    _tryHandlePendingNavigation();
  }

  bool _shouldShowSyncNotification({
    required String roomId,
    required _RoomNotificationSnapshot previous,
    required _RoomNotificationSnapshot current,
  }) {
    if (_appLifecycleState != AppLifecycleState.resumed &&
        _appLifecycleState != AppLifecycleState.inactive) {
      return false;
    }
    if (_activeRoomId == roomId) return false;
    if (!_notificationsEnabled()) return false;

    return current.notificationCount > previous.notificationCount ||
        current.highlightCount > previous.highlightCount;
  }

  Event? _pickNotificationEvent({
    required Room room,
    required JoinedRoomUpdate update,
    required String? ownUserId,
  }) {
    final timelineEvents = update.timeline?.events;
    if (timelineEvents == null || timelineEvents.isEmpty) return null;

    for (final matrixEvent in timelineEvents.reversed) {
      final event = Event.fromJson(
        Map<String, dynamic>.from(matrixEvent.toJson()),
        room,
      );
      if (_isNotifiableEvent(event, ownUserId)) {
        return event;
      }
    }

    return null;
  }

  bool _isNotifiableEvent(Event event, String? ownUserId) {
    if (event.senderId == ownUserId) return false;
    if (event.relationshipType == RelationshipTypes.edit) return false;

    return event.type == EventTypes.Message ||
        event.type == EventTypes.Encrypted ||
        event.type == EventTypes.Sticker ||
        event.type == EventTypes.Reaction;
  }

  Future<void> _showEventNotification({
    required Room room,
    required Event event,
    required bool isHighlight,
  }) async {
    if (!_localNotificationsReady) {
      return;
    }

    final roomName = room.getLocalizedDisplayname().trim();
    final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
    final preview = _notificationPreview(event);
    final title = isHighlight
        ? 'Mention in ${roomName.isEmpty ? senderName : roomName}'
        : (roomName.isEmpty ? senderName : roomName);
    final body = senderName == roomName || preview.isEmpty
        ? preview
        : '$senderName: $preview';
    final payload = jsonEncode({
      'room_id': room.id,
      'event_id': event.eventId,
      'highlight': isHighlight,
    });

    await _localNotifications.show(
      _notificationIdFromTimestamp(DateTime.now()),
      title,
      body.isEmpty ? 'New activity' : body,
      _notificationDetails(highlight: isHighlight),
      payload: payload,
    );
  }

  String _notificationPreview(Event event) {
    if (event.type == EventTypes.Reaction) {
      final relatesTo = event.content['m.relates_to'];
      final emoji = relatesTo is Map ? (relatesTo['key'] as String?) : null;
      return emoji == null || emoji.isEmpty
          ? 'reacted to your message'
          : 'reacted $emoji to your message';
    }

    final body = matrixEventDisplayText(event).trim();
    return body.isEmpty ? 'New message' : body;
  }

  Future<void> _createChannels() async {
    const messagesChannel = AndroidNotificationChannel(
      _messagesChannelId,
      'Messages',
      description: 'Incoming chat messages',
      importance: Importance.high,
    );
    const mentionsChannel = AndroidNotificationChannel(
      _mentionsChannelId,
      'Mentions',
      description: 'Mentions and highlighted activity',
      importance: Importance.high,
    );

    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(messagesChannel);
    await android?.createNotificationChannel(mentionsChannel);
  }

  Future<void> _onTokenRefresh(String token) async {
    final pushKey = await _loadCurrentPushKey(refreshedFcmToken: token);
    _currentToken = pushKey;

    final client = Get.find<AuthController>().client;
    if (client.accessToken == null || !_notificationsEnabled()) {
      return;
    }

    final url = await _getPushGatewayUrl();
    if (url != null && url.isNotEmpty) {
      await registerPusher(url);
    }
  }

  Future<String?> _getPushGatewayUrl() async {
    if (!Get.isRegistered<SettingsController>()) {
      return null;
    }
    return Get.find<SettingsController>().ensurePushGatewayUrl();
  }

  bool _notificationsEnabled() {
    if (!Get.isRegistered<SettingsController>()) {
      return false;
    }
    final settings = Get.find<SettingsController>().state;
    return settings?.notificationsEnabled == true;
  }

  void _seedRoomSnapshots(Client client) {
    _roomSnapshots
      ..clear()
      ..addEntries(
        client.rooms
            .where((room) => room.membership == Membership.join)
            .map(
              (room) =>
                  MapEntry(room.id, _RoomNotificationSnapshot.fromRoom(room)),
            ),
      );
  }

  void _pruneSnapshots(Client client) {
    final joinedRoomIds = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room.id)
        .toSet();
    _roomSnapshots.removeWhere((roomId, _) => !joinedRoomIds.contains(roomId));
  }

  bool _isAuthorized(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<String?> _loadCurrentPushKey({String? refreshedFcmToken}) async {
    if (_messaging == null) return null;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final apnsToken = await _messaging!.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          return apnsToken;
        }
        return refreshedFcmToken ?? await _messaging!.getToken();
      case TargetPlatform.android:
        return refreshedFcmToken ?? await _messaging!.getToken();
      default:
        return refreshedFcmToken ?? await _messaging!.getToken();
    }
  }

  String? _platformPusherAppId() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidPusherAppId;
      case TargetPlatform.iOS:
        return _iosPusherAppId;
      case TargetPlatform.macOS:
        return _macosPusherAppId;
      default:
        return null;
    }
  }

  void _handleNotificationResponse(NotificationResponse details) {
    final payload = details.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }

    if (details.actionId == _notificationActionMarkRead) {
      if (!_markRoomAsReadFromPayload(payload)) {
        unawaited(
          _enqueuePendingNotificationResponse(
            actionId: details.actionId,
            payload: payload,
          ),
        );
      }
      return;
    }

    if (!_openRoomFromPayload(payload)) {
      _pendingOpenRoomPayload = payload;
    }
  }

  Future<void> _processPendingNotificationResponses() async {
    final pendingResponses = await _drainPendingNotificationResponses();
    for (final pending in pendingResponses) {
      final payload = pending.payload;
      if (payload == null || payload.isEmpty) {
        continue;
      }
      if (pending.actionId == _notificationActionMarkRead) {
        if (!_markRoomAsReadFromPayload(payload)) {
          await _enqueuePendingNotificationResponse(
            actionId: pending.actionId,
            payload: payload,
          );
        }
        continue;
      }

      if (!_openRoomFromPayload(payload)) {
        _pendingOpenRoomPayload = payload;
      }
    }
  }

  bool _openRoomFromPayload(String payload) {
    final roomId = _roomIdFromPayload(payload);
    if (roomId == null || roomId == _activeRoomId) {
      return roomId != null;
    }
    if (!Get.isRegistered<RoomController>()) {
      return false;
    }
    final rooms = Get.find<RoomController>().state;
    if (rooms == null) {
      return false;
    }
    final room = rooms.firstWhereOrNull((candidate) => candidate.id == roomId);
    if (room == null || Get.context == null) {
      return false;
    }
    Get.to(() => ChatScreen(room: room), preventDuplicates: false);
    _pendingOpenRoomPayload = null;
    return true;
  }

  void _tryHandlePendingNavigation() {
    final pendingPayload = _pendingOpenRoomPayload;
    if (pendingPayload == null) return;
    if (_openRoomFromPayload(pendingPayload)) {
      _pendingOpenRoomPayload = null;
    }
  }

  bool _markRoomAsReadFromPayload(String payload) {
    final roomId = _roomIdFromPayload(payload);
    final eventId = _eventIdFromPayload(payload);
    if (roomId == null ||
        eventId == null ||
        !Get.isRegistered<AuthController>()) {
      return false;
    }

    final client = Get.find<AuthController>().client;
    final room = client.getRoomById(roomId);
    if (room == null) {
      return false;
    }

    unawaited(() async {
      try {
        if (room.markedUnread) {
          await room.markUnread(false);
        }
        await room.setReadMarker(eventId, mRead: eventId);
        if (Get.isRegistered<RoomController>()) {
          await Get.find<RoomController>().refreshRooms();
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[Push] Failed to mark room as read: $error');
        }
      }
    }());
    return true;
  }

  String? _roomIdFromPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final roomId = data['room_id']?.toString().trim();
      return roomId == null || roomId.isEmpty ? null : roomId;
    } catch (_) {
      return null;
    }
  }

  String? _eventIdFromPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final eventId = data['event_id']?.toString().trim();
      return eventId == null || eventId.isEmpty ? null : eventId;
    } catch (_) {
      return null;
    }
  }
}

class _RoomNotificationSnapshot {
  const _RoomNotificationSnapshot({
    required this.notificationCount,
    required this.highlightCount,
  });

  final int notificationCount;
  final int highlightCount;

  factory _RoomNotificationSnapshot.fromRoom(Room room) {
    return _RoomNotificationSnapshot(
      notificationCount: room.notificationCount,
      highlightCount: room.highlightCount,
    );
  }
}

int _notificationIdFromTimestamp(DateTime timestamp) {
  return timestamp.microsecondsSinceEpoch.abs() % 0x7fffffff;
}

NotificationDetails _notificationDetails({required bool highlight}) {
  final androidDetails = AndroidNotificationDetails(
    highlight ? _mentionsChannelId : _messagesChannelId,
    highlight ? 'Mentions' : 'Messages',
    channelDescription: highlight
        ? 'Mentions and highlighted activity'
        : 'Incoming chat messages',
    icon: _notificationIcon,
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    actions: const <AndroidNotificationAction>[
      AndroidNotificationAction(
        _notificationActionOpen,
        'Open',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(_notificationActionMarkRead, 'Mark as read'),
    ],
  );
  const darwinDetails = DarwinNotificationDetails();
  return NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
    macOS: darwinDetails,
  );
}

Future<void> _ensureBackgroundNotificationsInitialized() async {
  if (_backgroundNotificationsInitialized) return;

  try {
    const androidSettings = AndroidInitializationSettings(_notificationIcon);
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _backgroundLocalNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    const messagesChannel = AndroidNotificationChannel(
      _messagesChannelId,
      'Messages',
      description: 'Incoming chat messages',
      importance: Importance.high,
    );
    const mentionsChannel = AndroidNotificationChannel(
      _mentionsChannelId,
      'Mentions',
      description: 'Mentions and highlighted activity',
      importance: Importance.high,
    );
    final android = _backgroundLocalNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(messagesChannel);
    await android?.createNotificationChannel(mentionsChannel);
    _backgroundNotificationsInitialized = true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[Push] Background notifications unavailable: $error');
    }
  }
}

Future<File> _pendingNotificationQueueFile() async {
  return File(
    '${Directory.systemTemp.path}/dot_matrix_notification_responses.json',
  );
}

Future<void> _enqueuePendingNotificationResponse({
  required String? actionId,
  required String? payload,
}) async {
  if (payload == null || payload.isEmpty) {
    return;
  }

  final file = await _pendingNotificationQueueFile();
  final pending = await _drainPendingNotificationResponses();
  pending.add(
    _QueuedNotificationResponse(actionId: actionId, payload: payload),
  );
  await file.writeAsString(
    jsonEncode(pending.map((entry) => entry.toJson()).toList()),
    flush: true,
  );
}

Future<List<_QueuedNotificationResponse>>
_drainPendingNotificationResponses() async {
  final file = await _pendingNotificationQueueFile();
  if (!await file.exists()) {
    return <_QueuedNotificationResponse>[];
  }

  try {
    final raw = await file.readAsString();
    await file.delete();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <_QueuedNotificationResponse>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (entry) => _QueuedNotificationResponse(
            actionId: entry['action_id']?.toString(),
            payload: entry['payload']?.toString(),
          ),
        )
        .toList();
  } catch (_) {
    try {
      await file.delete();
    } catch (_) {}
    return <_QueuedNotificationResponse>[];
  }
}

class _QueuedNotificationResponse {
  const _QueuedNotificationResponse({
    required this.actionId,
    required this.payload,
  });

  final String? actionId;
  final String? payload;

  Map<String, dynamic> toJson() => {'action_id': actionId, 'payload': payload};
}
