import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../utils/matrix_event_display.dart';

const String _messagesChannelId = 'dot_matrix_messages';
const String _mentionsChannelId = 'dot_matrix_mentions';
const String _androidPusherAppId = 'com.housetully.dotmatrix.android';
const String _iosPusherAppId = 'com.housetully.dotmatrix.ios';
const String _macosPusherAppId = 'com.housetully.dotmatrix.macos';

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
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('[Push] Background Firebase init failed: $error');
    debugPrint(_firebaseSetupHint());
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

  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await localNotifications.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    ),
  );

  await localNotifications.show(
    _notificationIdFromTimestamp(DateTime.now()),
    title,
    body,
    _notificationDetails(highlight: false),
    payload: jsonEncode(data),
  );
}

class PushNotificationService with WidgetsBindingObserver {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<SyncUpdate>? _syncSubscription;
  bool _initialized = false;
  String? _currentToken;
  String? _activeRoomId;
  String? _boundUserId;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  final Map<String, _RoomNotificationSnapshot> _roomSnapshots = {};

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      _messaging!.onTokenRefresh.listen(_onTokenRefresh);
      _currentToken = await _loadCurrentPushKey();
      debugPrint('[Push] Push key: $_currentToken');
    } catch (error) {
      debugPrint('[Push] Firebase not configured: $error');
      debugPrint(_firebaseSetupHint());
      _messaging = null;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          debugPrint('[Push] Notification tapped: $data');
          // TODO: Navigate to the specific chat room from payload.
        } catch (_) {}
      },
    );

    await _createChannels();
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  Future<void> bindClient(Client client) async {
    await initialize();
    _syncSubscription?.cancel();
    _boundUserId = client.userID;
    _seedRoomSnapshots(client);
    _syncSubscription = client.onSync.stream.listen(
      (syncUpdate) => _handleSyncUpdate(client, syncUpdate),
    );
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
      debugPrint('[Push] No push key available');
      return;
    }

    final client = Get.find<AuthController>().client;
    final deviceId = client.deviceID ?? 'unknown';
    final appId = _platformPusherAppId();
    if (appId == null) {
      debugPrint('[Push] Unsupported platform for Matrix push registration');
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
      debugPrint('[Push] Pusher registered');
    } catch (error) {
      debugPrint('[Push] Failed to register pusher: $error');
    }
  }

  Future<void> unregisterPusher() async {
    if (_currentToken == null) return;

    final client = Get.find<AuthController>().client;
    final appId = _platformPusherAppId();
    if (appId == null) return;
    final pusherId = PusherId(
      appId: appId,
      pushkey: _currentToken!,
    );

    try {
      await client.deletePusher(pusherId);
      debugPrint('[Push] Pusher unregistered');
    } catch (error) {
      debugPrint('[Push] Failed to unregister pusher: $error');
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
  }

  bool _shouldShowSyncNotification({
    required String roomId,
    required _RoomNotificationSnapshot previous,
    required _RoomNotificationSnapshot current,
  }) {
    if (_appLifecycleState != AppLifecycleState.resumed) return false;
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
    debugPrint('[Push] Push key refreshed: $pushKey');
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
  return timestamp.microsecondsSinceEpoch.remainder(1 << 31);
}

NotificationDetails _notificationDetails({required bool highlight}) {
  final androidDetails = AndroidNotificationDetails(
    highlight ? _mentionsChannelId : _messagesChannelId,
    highlight ? 'Mentions' : 'Messages',
    channelDescription: highlight
        ? 'Mentions and highlighted activity'
        : 'Incoming chat messages',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
  );
  const darwinDetails = DarwinNotificationDetails();
  return NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
    macOS: darwinDetails,
  );
}
