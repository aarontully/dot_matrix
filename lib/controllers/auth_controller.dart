import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../services/push_notification_service.dart';
import '../utils/pinned_http_client.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/current_session_trust.dart';
import '../utils/secure_storage_recovery.dart';
import '../screens/device_setup_screen.dart';
import 'room_controller.dart';
import 'settings_controller.dart';
import '../widgets/device_verification_dialog.dart';
import '../widgets/device_verification_target_dialog.dart';

class AuthController extends GetxController with StateMixin<String?> {
  static const _storageTokenKey = 'matrix_token';
  static const _storageUserIdKey = 'matrix_user_id';
  static const _storageHomeserverKey = 'matrix_homeserver';
  static const _storageDeviceIdKey = 'matrix_device_id';
  static const _storageDeviceNameKey = 'matrix_device_name';
  static const _defaultDeviceName = 'DotMatrix';
  static const _storedSessionValidationTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: true),
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
      httpClient: createPinnedHttpClient(),
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

  Future<Map<String, dynamic>?> _getLocalMatrixAccount() async {
    final db = await _openMatrixDatabase();
    try {
      return await db.getClient(_client.clientName);
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

  bool _isConnectivityError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is HttpException;
  }

  bool _isUploadKeyFailure(Object error) {
    return error.toString().contains('Upload key failed');
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[AuthController] $message');
    }
  }

  void _runInBackground(Future<void> Function() task, {required String label}) {
    unawaited(
      task().catchError((Object error, StackTrace stackTrace) {
        _debugLog('$label failed: $error');
        if (kDebugMode) {
          debugPrint('$stackTrace');
        }
      }),
    );
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

  Future<bool> _recoverFromCorruptedSecureStorage(
    Object error, {
    StackTrace? stackTrace,
  }) async {
    if (!isSecureStorageDecryptionError(error)) {
      return false;
    }

    _debugLog('Secure storage decryption failed, clearing app secrets.');
    if (kDebugMode && stackTrace != null) {
      debugPrint('$stackTrace');
    }

    await clearSecureStorageSafely(_storage);
    await _clearMatrixCache();
    clearBrokenAvatarSources();
    _verificationSubscription?.cancel();
    _verificationSubscription = null;
    _client = await _createClient();
    change(null, status: RxStatus.success());
    return true;
  }

  Future<void> _init() async {
    change(null, status: RxStatus.loading());
    try {
      _debugLog('Restoring stored session...');
      final storedValues = await _storage.readAll().catchError((
        Object error,
        StackTrace stackTrace,
      ) async {
        if (await _recoverFromCorruptedSecureStorage(
          error,
          stackTrace: stackTrace,
        )) {
          return <String, String>{};
        }
        throw error;
      });
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
      final localAccount = await _getLocalMatrixAccount();

      if (localAccount == null) {
        _debugLog('Local Matrix database missing, resetting stored session.');
        await _resetStoredSession();
        change(null, status: RxStatus.success());
        return;
      }

      try {
        final isStoredSessionValid = await _validateStoredSession(
          homeserver: homeserverUri,
          accessToken: accessToken,
          userId: userId,
          deviceId: deviceId,
        ).timeout(_storedSessionValidationTimeout);
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
        if (_isConnectivityError(error)) {
          _debugLog(
            'Stored session validation unavailable, continuing with cached session: $error',
          );
        } else {
          rethrow;
        }
      }

      _client = await _createClient();
      await _client.init(
        newToken: accessToken,
        newHomeserver: homeserverUri,
        newUserID: userId,
        newDeviceID: deviceId,
        newDeviceName: deviceName,
        newOlmAccount: localAccount['olm_account'] as String?,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      await (_client.roomsLoading ?? Future.value()).timeout(
        const Duration(seconds: 20),
        onTimeout: () => Future.value(),
      );
      _setupVerificationListener();
      change(userId, status: RxStatus.success());
      _runInBackground(() async {
        await PushNotificationService().bindClient(_client);
        await _maybeRegisterPusher();
        await _maybePromptDeviceVerification();
      }, label: 'post-restore setup');
    } catch (error, stackTrace) {
      _debugLog('_init failed: $error');
      if (kDebugMode) {
        debugPrint('$stackTrace');
      }
      if (await _recoverFromCorruptedSecureStorage(
        error,
        stackTrace: stackTrace,
      )) {
        return;
      }
      if (_isInvalidTokenError(error)) {
        await _resetStoredSession();
        change(null, status: RxStatus.success());
        return;
      }
      if (_isUploadKeyFailure(error)) {
        _debugLog(
          'Stored crypto session could not upload keys, resetting session.',
        );
        await _resetStoredSession();
        change(null, status: RxStatus.success());
        return;
      }

      _client = await _createClient();
      change(null, status: RxStatus.error(error.toString()));
    }
  }

  Future<void> login(
    String username,
    String password,
    String homeserver,
  ) async {
    change(null, status: RxStatus.loading());
    try {
      await _clearMatrixCache();
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
      _setupVerificationListener();
      change(loginResponse.userId, status: RxStatus.success());
      _runInBackground(() async {
        await PushNotificationService().bindClient(_client);
        await _maybeRegisterPusher();
        await _runFreshLoginOnboarding();
      }, label: 'post-login setup');
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
      await _storage.write(key: _storageDeviceNameKey, value: deviceName);
    } catch (e, st) {
      _debugLog('persistDeviceName failed: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
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
    PushNotificationService().unbindClient();
    try {
      await _clearStoredSession();
    } catch (e, st) {
      _debugLog('logout cleanup failed: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
    }
    clearBrokenAvatarSources();
    _verificationSubscription?.cancel();
    _verificationSubscription = null;
    _client = await _createClient();
    change(null, status: RxStatus.success());
  }

  Future<void> _maybeRegisterPusher() async {
    try {
      final settingsController = Get.find<SettingsController>();
      final settings = settingsController.state;
      final url = await settingsController.ensurePushGatewayUrl();
      if (settings?.notificationsEnabled == true &&
          url != null &&
          url.isNotEmpty) {
        await PushNotificationService().registerPusher(url);
      } else {
        await PushNotificationService().unregisterPusher();
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

      var settings = settingsController.state;
      if (settings != null && settings.needsDeviceSetup) {
        await Get.to(
          () => const DeviceSetupScreen(launchedFromOnboarding: true),
          preventDuplicates: false,
        );
        await settingsController.refreshSettings();
        settings = settingsController.state;
      }

      if (settings != null && !settings.notificationsPromptSeen) {
        await _promptForNotificationOptIn(settingsController);
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

  Future<void> _promptForNotificationOptIn(
    SettingsController settingsController,
  ) async {
    final enableNotifications = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Turn on notifications?'),
        content: const Text(
          'DotMatrix can alert you when new messages or mentions arrive. '
          'You can change this any time in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Turn on'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (enableNotifications == true) {
      final granted = await settingsController.enableNotifications(
        markPromptSeen: true,
      );
      if (!granted) {
        await _showInfoDialog(
          title: 'Notifications stay off',
          message:
              'DotMatrix could not get notification permission. You can turn '
              'it on later from Settings > Notifications.',
        );
      }
      return;
    }

    await settingsController.disableNotifications(markPromptSeen: true);
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
      if (isCurrentSessionVerified(_client)) return;

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

      final settingsController = Get.find<SettingsController>();
      final session = await chooseDeviceVerificationTarget(
        settingsController: settingsController,
      );
      if (session == null) return;

      final request = await settingsController.startDeviceVerification(
        deviceId: session.deviceId,
      );
      await Get.dialog(
        barrierDismissible: false,
        DeviceVerificationDialog(request: request),
      );

      if (request.state == KeyVerificationState.done) {
        await encryption.ssss.maybeRequestAll();
        await Get.find<RoomController>().requestMissingEncryptionKeys();
        await Get.find<RoomController>().refreshRooms(rebuildTimelines: true);
        await settingsController.refreshSettings();
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
      await _storage.write(key: _storageTokenKey, value: accessToken);
      await _storage.write(key: _storageUserIdKey, value: userId);
      await _storage.write(key: _storageHomeserverKey, value: homeserver);
      await _storage.write(key: _storageDeviceIdKey, value: deviceId);
      await _storage.write(key: _storageDeviceNameKey, value: deviceName);
    } catch (e, st) {
      _debugLog('persisting session failed: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
      rethrow;
    }
  }

  Future<void> _clearStoredSession() async {
    try {
      await _storage.delete(key: _storageTokenKey);
      await _storage.delete(key: _storageUserIdKey);
      await _storage.delete(key: _storageHomeserverKey);
      await _storage.delete(key: _storageDeviceIdKey);
      await _storage.delete(key: _storageDeviceNameKey);
    } catch (e, st) {
      _debugLog('clearing stored session failed: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
      rethrow;
    }
  }
}
