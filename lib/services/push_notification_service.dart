import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[Push] Background message: ${message.messageId}');
  debugPrint('[Push] Data: ${message.data}');

  final data = message.data;
  final notification = message.notification;

  String title = notification?.title ?? data['sender_display_name'] ?? 'New message';
  String body = notification?.body ?? data['content']?['body'] ?? data['body'] ?? '';

  if (body.isEmpty && data['unread'] != null) {
    final count = int.tryParse(data['unread'].toString()) ?? 1;
    body = count == 1 ? 'You have a new message' : 'You have $count new messages';
  }

  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinSettings = DarwinInitializationSettings();
  await localNotifications.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    ),
  );

  const androidDetails = AndroidNotificationDetails(
    'dot_matrix_messages',
    'Messages',
    channelDescription: 'Incoming chat messages',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
  );
  const darwinDetails = DarwinNotificationDetails();
  const details = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
    macOS: darwinDetails,
  );

  await localNotifications.show(
    DateTime.now().millisecond,
    title,
    body,
    details,
    payload: jsonEncode(data),
  );
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentToken;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Push] Firebase not configured: $e');
      return;
    }

    _messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[Push] Permission status: ${settings.authorizationStatus}');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
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
          // TODO: Navigate to the specific chat room from payload
        } catch (_) {}
      },
    );

    const androidChannel = AndroidNotificationChannel(
      'dot_matrix_messages',
      'Messages',
      description: 'Incoming chat messages',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _messaging!.onTokenRefresh.listen(_onTokenRefresh);

    _currentToken = await _messaging!.getToken();
    debugPrint('[Push] FCM token: $_currentToken');

    _initialized = true;
  }

  Future<void> registerPusher(String pushGatewayUrl) async {
    if (_messaging == null) return;
    _currentToken ??= await _messaging!.getToken();
    if (_currentToken == null) {
      debugPrint('[Push] No FCM token available');
      return;
    }

    final client = Get.find<AuthController>().client;
    final deviceId = client.deviceID ?? 'unknown';

    final pusher = Pusher(
      appId: 'com.housetully.dotmatrix',
      pushkey: _currentToken!,
      appDisplayName: 'Dot Matrix',
      data: PusherData(
        url: Uri.parse(pushGatewayUrl),
      ),
      deviceDisplayName: deviceId,
      kind: 'http',
      lang: 'en',
    );

    try {
      await client.postPusher(pusher, append: false);
      debugPrint('[Push] Pusher registered');
    } catch (e) {
      debugPrint('[Push] Failed to register pusher: $e');
    }
  }

  Future<void> unregisterPusher() async {
    if (_currentToken == null) return;

    final client = Get.find<AuthController>().client;
    final pusherId = PusherId(
      appId: 'com.housetully.dotmatrix',
      pushkey: _currentToken!,
    );

    try {
      await client.deletePusher(pusherId);
      debugPrint('[Push] Pusher unregistered');
    } catch (e) {
      debugPrint('[Push] Failed to unregister pusher: $e');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    debugPrint('[Push] Token refreshed: $token');
    _currentToken = token;

    final client = Get.find<AuthController>().client;
    if (client.accessToken != null) {
      final url = await _getPushGatewayUrl();
      if (url != null) {
        await registerPusher(url);
      }
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[Push] Foreground message: ${message.notification?.title}');
  }

  Future<String?> _getPushGatewayUrl() async {
    return null;
  }
}
