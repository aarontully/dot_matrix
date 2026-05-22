import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../services/push_notification_service.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/current_session_trust.dart';
import '../screens/device_setup_screen.dart';
import 'room_controller.dart';
import 'settings_controller.dart';
import '../widgets/device_verification_dialog.dart';

class AuthController extends GetxController with StateMixin<String?> {
  static const _storageTokenKey = 'matrix_token';
  static const _storageUserIdKey = 'matrix_user_id';
  static const _storageHomeserverKey = 'matrix_homeserver';
  static const _storageDeviceIdKey = 'matrix_device_id';
  static const _storageDeviceNameKey = 'matrix_device_name';
  static const _defaultDeviceName = 'DotMatrix';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
  Client _client = Client('Dot Matrix');
  StreamSubscription? _verificationSubscription;
  bool _postLoginFlowInProgress = false;

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
      debugPrint('[AuthController] Starting _init, reading secure storage...');
      final storedValues = await _storage.readAll();
      debugPrint(
        '[AuthController] Secure storage readAll completed. Keys: ${storedValues.keys.toList()}',
      );
      final accessToken = storedValues[_storageTokenKey];
      final userId = storedValues[_storageUserIdKey];
      final homeserver = storedValues[_storageHomeserverKey];
      final deviceId = storedValues[_storageDeviceIdKey];
      final deviceName =
          storedValues[_storageDeviceNameKey] ?? _defaultDeviceName;

      debugPrint(
        '[AuthController] token=${accessToken != null}, userId=${userId != null}, homeserver=${homeserver != null}, deviceId=${deviceId != null}',
      );

      if (accessToken == null ||
          userId == null ||
          homeserver == null ||
          deviceId == null) {
        debugPrint(
          '[AuthController] Missing stored session fields, showing login.',
        );
        change(null, status: RxStatus.success());
        return;
      }

      final homeserverUri = Uri.parse(homeserver);
      final hasLocalMatrixSession = await _hasLocalMatrixSession();

      if (!hasLocalMatrixSession) {
        debugPrint(
          '[AuthController] Local Matrix DB missing but credentials exist. Resetting session.',
        );
        await _resetStoredSession();
        change(null, status: RxStatus.success());
        return;
      }

      debugPrint('[AuthController] Validating stored session...');
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

      debugPrint('[AuthController] Creating Matrix client...');
      _client = await _createClient();
      debugPrint('[AuthController] Initializing Matrix client...');
      await _client.init(
        newToken: hasLocalMatrixSession ? null : accessToken,
        newHomeserver: hasLocalMatrixSession ? null : homeserverUri,
        newUserID: hasLocalMatrixSession ? null : userId,
        newDeviceID: hasLocalMatrixSession ? null : deviceId,
        newDeviceName: hasLocalMatrixSession ? null : deviceName,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      debugPrint('[AuthController] Matrix client init completed.');
      await (_client.roomsLoading ?? Future.value());
      debugPrint('[AuthController] Rooms loading completed.');
      _setupVerificationListener();
      await _maybeRegisterPusher();
      change(userId, status: RxStatus.success());
      await _maybePromptDeviceVerification();
    } catch (error, stackTrace) {
      debugPrint('[AuthController] _init error: $error');
      debugPrint('[AuthController] _init stackTrace: $stackTrace');
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

      debugPrint('[AuthController] Login successful, persisting session...');
      await _persistSession(
        accessToken: loginResponse.accessToken,
        userId: loginResponse.userId,
        homeserver: resolvedHomeserver.toString(),
        deviceId: loginResponse.deviceId,
        deviceName: _defaultDeviceName,
      );
      debugPrint('[AuthController] Session persisted.');

      clearBrokenAvatarSources();
      _setupVerificationListener();
      await _maybeRegisterPusher();
      change(loginResponse.userId, status: RxStatus.success());
      await _runFreshLoginOnboarding();
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }
  }

  void _setupVerificationListener() {
    _verificationSubscription?.cancel();
    _verificationSubscription = _client.onKeyVerificationRequest.stream.listen((
      request,
    ) {
      request.onUpdate = () {
        if (request.isDone) {
          request.onUpdate = null;
        }
      };
      Get.dialog(DeviceVerificationDialog(request: request));
    });
  }

  Future<void> persistDeviceName(String deviceName) async {
    try {
      debugPrint('[AuthController] persistDeviceName: writing deviceName...');
      await _storage.write(key: _storageDeviceNameKey, value: deviceName);
      debugPrint('[AuthController] persistDeviceName: success');
    } catch (e, st) {
      debugPrint('[AuthController] persistDeviceName error: $e');
      debugPrint('[AuthController] persistDeviceName stackTrace: $st');
      rethrow;
    }
  }

  Future<void> logout() async {
    change(state, status: RxStatus.loading());
    try {
      await _client.logout();
    } catch (_) {
      // Best effort logout. Local cleanup still matters more here.
    }

    await PushNotificationService().unregisterPusher();
    try {
      debugPrint('[AuthController] Clearing stored session...');
      await _clearStoredSession();
      debugPrint('[AuthController] Stored session cleared.');
    } catch (e, st) {
      debugPrint('[AuthController] logout clear session error: $e');
      debugPrint('[AuthController] logout clear session stackTrace: $st');
    }
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

  Future<void> _runFreshLoginOnboarding() async {
    if (_postLoginFlowInProgress) return;
    _postLoginFlowInProgress = true;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final settingsController = Get.find<SettingsController>();
      await settingsController.refreshSettings();

      final settings = settingsController.state;
      if (settings != null && settings.needsDeviceSetup) {
        await Get.to(
          () => const DeviceSetupScreen(launchedFromOnboarding: true),
          preventDuplicates: false,
        );
      }
    } finally {
      _postLoginFlowInProgress = false;
    }
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) async {
    await Get.dialog<void>(
      AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Get.back(), child: const Text('OK')),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _maybePromptDeviceVerification({
    bool showUnavailableInfo = false,
  }) async {
    try {
      final encryption = _client.encryption;
      if (encryption == null) return;

      final userId = _client.userID;
      if (userId == null) return;

      await _client.updateUserDeviceKeys(additionalUsers: {userId});
      await _client.userDeviceKeysLoading;

      final ownKeys = _client.userDeviceKeys[userId];
      if (isCurrentSessionTrusted(_client)) return;

      final otherKeys =
          ownKeys?.deviceKeys.values
              .where((dk) => dk.deviceId != _client.deviceID)
              .toList() ??
          [];

      if (otherKeys.isEmpty) {
        if (showUnavailableInfo) {
          await _showInfoDialog(
            title: 'Verify this device',
            message:
                'No other signed-in devices were found for this account, so there is nothing to verify against yet.',
          );
        }
        return;
      }

      final hasVerified = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Verify this device'),
          content: const Text(
            'Another device is signed into your account. '
            'Verify this session to access your encrypted message history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Verify'),
            ),
          ],
        ),
      );

      if (hasVerified != true) return;

      final request = await Get.find<SettingsController>()
          .startDeviceVerification();
      await Get.dialog(
        barrierDismissible: false,
        DeviceVerificationDialog(request: request),
      );

      if (request.state == KeyVerificationState.done) {
        await encryption.ssss.maybeRequestAll();
        await Get.find<RoomController>().requestMissingEncryptionKeys();
        await Get.find<RoomController>().refreshRooms(rebuildTimelines: true);
        await Get.find<SettingsController>().refreshSettings();
      }
    } catch (_) {
      // Best effort prompt.
    }
  }

  Future<void> _persistSession({
    required String accessToken,
    required String userId,
    required String homeserver,
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      debugPrint('[AuthController] _persistSession: writing token...');
      await _storage.write(key: _storageTokenKey, value: accessToken);
      debugPrint('[AuthController] _persistSession: writing userId...');
      await _storage.write(key: _storageUserIdKey, value: userId);
      debugPrint('[AuthController] _persistSession: writing homeserver...');
      await _storage.write(key: _storageHomeserverKey, value: homeserver);
      debugPrint('[AuthController] _persistSession: writing deviceId...');
      await _storage.write(key: _storageDeviceIdKey, value: deviceId);
      debugPrint('[AuthController] _persistSession: writing deviceName...');
      await _storage.write(key: _storageDeviceNameKey, value: deviceName);
      debugPrint('[AuthController] _persistSession: all writes completed');
    } catch (e, st) {
      debugPrint('[AuthController] _persistSession error: $e');
      debugPrint('[AuthController] _persistSession stackTrace: $st');
      rethrow;
    }
  }

  Future<void> _clearStoredSession() async {
    try {
      debugPrint('[AuthController] _clearStoredSession: deleting keys...');
      await _storage.delete(key: _storageTokenKey);
      await _storage.delete(key: _storageUserIdKey);
      await _storage.delete(key: _storageHomeserverKey);
      await _storage.delete(key: _storageDeviceIdKey);
      await _storage.delete(key: _storageDeviceNameKey);
      debugPrint('[AuthController] _clearStoredSession: done');
    } catch (e, st) {
      debugPrint('[AuthController] _clearStoredSession error: $e');
      debugPrint('[AuthController] _clearStoredSession stackTrace: $st');
      rethrow;
    }
  }
}
