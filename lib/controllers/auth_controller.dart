import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../services/push_notification_service.dart';
import '../utils/avatar_url_resolver.dart';
import 'settings_controller.dart';
import '../widgets/device_verification_dialog.dart';

class AuthController extends GetxController with StateMixin<String?> {
  static const _storageTokenKey = 'matrix_token';
  static const _storageUserIdKey = 'matrix_user_id';
  static const _storageHomeserverKey = 'matrix_homeserver';
  static const _storageDeviceIdKey = 'matrix_device_id';
  static const _storageDeviceNameKey = 'matrix_device_name';
  static const _defaultDeviceName = 'DotMatrix';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Client _client = Client('Dot Matrix');
  StreamSubscription? _verificationSubscription;

  Client get client => _client;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<HiveCollectionsDatabase> _openMatrixDatabase() async {
    final dir = await getApplicationSupportDirectory();
    final db = HiveCollectionsDatabase('matrix', dir.path);
    await db.open();
    return db;
  }

  Future<Client> _createClient() async {
    final newClient = Client(
      'Dot Matrix',
      databaseBuilder: (_) async => _openMatrixDatabase(),
      verificationMethods: {KeyVerificationMethod.emoji},
    );

    return newClient;
  }

  Future<void> _clearMatrixCache() async {
    final db = await _openMatrixDatabase();
    try {
      await db.clear();
    } finally {
      await db.close();
    }
  }

  Future<bool> _hasLocalMatrixSession() async {
    final db = await _openMatrixDatabase();
    try {
      final account = await db.getClient(_client.clientName);
      return account != null;
    } finally {
      await db.close();
    }
  }

  bool _isInvalidTokenError(Object error) {
    if (error is MatrixException) {
      return error.error == MatrixError.M_UNKNOWN_TOKEN ||
          error.errcode == 'M_MISSING_TOKEN';
    }
    final message = error.toString();
    return message.contains('M_UNKNOWN_TOKEN') ||
        message.contains('M_MISSING_TOKEN');
  }

  Future<bool> _validateStoredSession({
    required Uri homeserver,
    required String accessToken,
    required String userId,
    required String deviceId,
  }) async {
    final matrixApi = MatrixApi(
      homeserver: homeserver,
      accessToken: accessToken,
    );
    final tokenOwner = await matrixApi.getTokenOwner();
    return tokenOwner.userId == userId &&
        (tokenOwner.deviceId == null || tokenOwner.deviceId == deviceId);
  }

  Future<void> _resetStoredSession() async {
    await _clearStoredSession();
    await _clearMatrixCache();
    clearBrokenAvatarSources();
    _client = await _createClient();
  }

  Future<void> _init() async {
    change(null, status: RxStatus.loading());
    try {
      final storedValues = await _storage.readAll();
      final accessToken = storedValues[_storageTokenKey];
      final userId = storedValues[_storageUserIdKey];
      final homeserver = storedValues[_storageHomeserverKey];
      final deviceId = storedValues[_storageDeviceIdKey];
      final deviceName =
          storedValues[_storageDeviceNameKey] ?? _defaultDeviceName;

      if (accessToken == null ||
          userId == null ||
          homeserver == null ||
          deviceId == null) {
        change(null, status: RxStatus.success());
        return;
      }

      final homeserverUri = Uri.parse(homeserver);
      final hasLocalMatrixSession = await _hasLocalMatrixSession();

      try {
        final isStoredSessionValid = await _validateStoredSession(
          homeserver: homeserverUri,
          accessToken: accessToken,
          userId: userId,
          deviceId: deviceId,
        );
        if (!isStoredSessionValid) {
          await _resetStoredSession();
          change(null, status: RxStatus.success());
          return;
        }
      } catch (error) {
        if (_isInvalidTokenError(error)) {
          await _resetStoredSession();
          change(null, status: RxStatus.success());
          return;
        }
      }

      _client = await _createClient();
      await _client.init(
        newToken: hasLocalMatrixSession ? null : accessToken,
        newHomeserver: hasLocalMatrixSession ? null : homeserverUri,
        newUserID: hasLocalMatrixSession ? null : userId,
        newDeviceID: hasLocalMatrixSession ? null : deviceId,
        newDeviceName: hasLocalMatrixSession ? null : deviceName,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      await (_client.roomsLoading ?? Future.value());
      _setupVerificationListener();
      await _maybeRegisterPusher();

      change(userId, status: RxStatus.success());
    } catch (error) {
      if (_isInvalidTokenError(error)) {
        await _resetStoredSession();
        change(null, status: RxStatus.success());
        return;
      }

      _client = await _createClient();
      change(null, status: RxStatus.error(error.toString()));
      change(null, status: RxStatus.success());
    }
  }

  Future<void> login(
    String username,
    String password,
    String homeserver,
  ) async {
    change(null, status: RxStatus.loading());
    try {
      _client = await _createClient();
      await _client.checkHomeserver(Uri.parse(homeserver));
      final resolvedHomeserver = _client.homeserver ?? Uri.parse(homeserver);
      final matrixApi = MatrixApi(homeserver: resolvedHomeserver);
      final loginResponse = await matrixApi.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: _defaultDeviceName,
      );

      await _client.init(
        newToken: loginResponse.accessToken,
        newHomeserver: resolvedHomeserver,
        newUserID: loginResponse.userId,
        newDeviceID: loginResponse.deviceId,
        newDeviceName: _defaultDeviceName,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );

      await _persistSession(
        accessToken: loginResponse.accessToken,
        userId: loginResponse.userId,
        homeserver: resolvedHomeserver.toString(),
        deviceId: loginResponse.deviceId,
        deviceName: _defaultDeviceName,
      );

      clearBrokenAvatarSources();
      await _maybeRegisterPusher();
      change(loginResponse.userId, status: RxStatus.success());
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }
  }

  void _setupVerificationListener() {
    _verificationSubscription?.cancel();
    _verificationSubscription = _client.onKeyVerificationRequest.stream.listen(
      (request) {
        request.onUpdate = () {
          if (request.isDone) {
            request.onUpdate = null;
          }
        };
        Get.dialog(DeviceVerificationDialog(request: request));
      },
    );
  }

  Future<void> persistDeviceName(String deviceName) async {
    await _storage.write(key: _storageDeviceNameKey, value: deviceName);
  }

  Future<void> logout() async {
    change(state, status: RxStatus.loading());
    try {
      await _client.logout();
    } catch (_) {
      // Best effort logout. Local cleanup still matters more here.
    }

    await PushNotificationService().unregisterPusher();
    await _clearStoredSession();
    clearBrokenAvatarSources();
    _verificationSubscription?.cancel();
    _verificationSubscription = null;
    _client = await _createClient();
    change(null, status: RxStatus.success());
  }

  Future<void> _maybeRegisterPusher() async {
    try {
      final settings = Get.find<SettingsController>().state;
      final url = settings?.pushGatewayUrl;
      if (url != null && url.isNotEmpty) {
        await PushNotificationService().registerPusher(url);
      }
    } catch (_) {
      // Best effort pusher registration.
    }
  }

  Future<void> _persistSession({
    required String accessToken,
    required String userId,
    required String homeserver,
    required String deviceId,
    required String deviceName,
  }) async {
    await _storage.write(key: _storageTokenKey, value: accessToken);
    await _storage.write(key: _storageUserIdKey, value: userId);
    await _storage.write(key: _storageHomeserverKey, value: homeserver);
    await _storage.write(key: _storageDeviceIdKey, value: deviceId);
    await _storage.write(key: _storageDeviceNameKey, value: deviceName);
  }

  Future<void> _clearStoredSession() async {
    await _storage.delete(key: _storageTokenKey);
    await _storage.delete(key: _storageUserIdKey);
    await _storage.delete(key: _storageHomeserverKey);
    await _storage.delete(key: _storageDeviceIdKey);
    await _storage.delete(key: _storageDeviceNameKey);
  }
}
