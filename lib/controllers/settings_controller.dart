import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../config/push_defaults.dart';
import '../models/device_session_info.dart';
import '../models/settings_state.dart';
import '../utils/current_session_trust.dart';
import 'auth_controller.dart';
import 'room_controller.dart';
import '../services/push_notification_service.dart';

class DeviceSessionReauthRequired implements Exception {
  const DeviceSessionReauthRequired({
    required this.deviceId,
    this.session,
    required this.supportsPassword,
  });

  final String deviceId;
  final String? session;
  final bool supportsPassword;

  @override
  String toString() {
    if (supportsPassword) {
      return 'Confirm your password to remove this session.';
    }
    return 'This homeserver requires extra authentication to remove a session, and DotMatrix cannot complete that flow here yet.';
  }
}

class SettingsController extends GetxController with StateMixin<SettingsState> {
  static const _boxName = 'dot_matrix_settings';
  static const _notificationsKey = 'notifications_enabled';
  static const _notificationsPromptSeenKey = 'notifications_prompt_seen';
  static const _pushGatewayUrlKey = 'push_gateway_url';
  static const _encryptMessagesKey = 'encrypt_messages';
  static const _appearanceKey = 'appearance';
  static const _chatSortOrderKey = 'chat_sort_order';
  static const _activeStatusKey = 'active_status_enabled';
  static const _customPrimaryColorKey = 'custom_primary_color';
  static const _alsoMeUserIdsKey = 'also_me_user_ids';

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void onInit() {
    super.onInit();
    Get.find<AuthController>().addListener(() {
      refreshSettings();
    });
    refreshSettings();
  }

  Future<void> refreshSettings() async {
    change(null, status: RxStatus.loading());
    final box = await _openBox();
    final auth = Get.find<AuthController>();
    final client = auth.client;
    final appearance = AppAppearanceX.fromStorage(
      box.get(_appearanceKey) as String?,
    );
    final chatSortOrder = ChatSortOrderX.fromStorage(
      box.get(_chatSortOrderKey) as String?,
    );
    final customColorValue = box.get(_customPrimaryColorKey) as int?;
    final customPrimaryColor = customColorValue != null
        ? Color(customColorValue)
        : null;
    Get.changeThemeMode(appearance.themeMode);
    final notificationsEnabled = (box.get(_notificationsKey) as bool?) ?? false;
    final notificationsPromptSeen =
        (box.get(_notificationsPromptSeenKey) as bool?) ??
        box.containsKey(_notificationsKey);
    var pushGatewayUrl = box.get(_pushGatewayUrlKey) as String?;
    final encryptMessages = (box.get(_encryptMessagesKey) as bool?) ?? true;
    final alsoMeRaw = box.get(_alsoMeUserIdsKey) as List<dynamic>?;
    final alsoMeUserIds =
        alsoMeRaw?.cast<String>().toList() ?? const <String>[];
    if (auth.state == null || client.userID == null) {
      change(null, status: RxStatus.success());
      return;
    }

    if (pushGatewayUrl == null || pushGatewayUrl.isEmpty) {
      pushGatewayUrl = await _discoverExistingPushGatewayUrl(
        client,
        persistToState: false,
      );
    }

    try {
      final userId = client.userID!;
      final profile = await client.fetchOwnProfileFromServer(
        useServerCache: false,
      );

      GetPresenceResponse? presence;
      try {
        presence = await client.getPresence(userId);
      } catch (_) {
        presence = null;
      }

      Device? device;
      final deviceId = client.deviceID;
      if (deviceId != null && deviceId.isNotEmpty) {
        try {
          device = await client.getDevice(deviceId);
        } catch (_) {
          device = null;
        }
      }

      final defaultActiveStatus = presence == null
          ? true
          : presence.presence != PresenceType.offline;
      final encryption = client.encryption;
      final secureBackupAvailable = encryption?.ssss.defaultKeyId != null;
      final keyBackupEnabled = encryption?.keyManager.enabled ?? false;
      final encryptedHistoryReady = encryption == null
          ? false
          : await encryption.keyManager.isCached();
      var isCurrentDeviceVerified = false;
      var hasOtherDeviceSessions = false;
      var hasOtherVerifiedDeviceSessions = false;

      if (encryption != null &&
          client.deviceID != null &&
          client.deviceID!.isNotEmpty) {
        try {
          await client.updateUserDeviceKeys(additionalUsers: {userId});
          await client.userDeviceKeysLoading;
          final ownKeys = client.userDeviceKeys[userId];
          isCurrentDeviceVerified = isCurrentSessionTrusted(client);
          final otherDeviceKeys =
              ownKeys?.deviceKeys.values
                  .where((dk) => dk.deviceId != client.deviceID)
                  .toList() ??
              const [];
          hasOtherDeviceSessions = otherDeviceKeys.isNotEmpty;
          hasOtherVerifiedDeviceSessions = otherDeviceKeys.any(
            (dk) => dk.verified,
          );
        } catch (_) {
          isCurrentDeviceVerified = false;
          hasOtherDeviceSessions = false;
          hasOtherVerifiedDeviceSessions = false;
        }
      }

      change(
        SettingsState(
          displayName: _nonEmptyOrFallback(
            profile.displayName,
            userId.localpart ?? userId,
          ),
          statusMessage: presence?.statusMsg ?? '',
          avatarUrl: profile.avatarUrl,
          userId: userId,
          homeserver: client.homeserver?.toString() ?? '',
          deviceId: client.deviceID ?? 'Unknown device',
          deviceName: _nonEmptyOrFallback(
            device?.displayName,
            'DotMatrix Device',
          ),
          notificationsEnabled: notificationsEnabled,
          notificationsPromptSeen: notificationsPromptSeen,
          pushGatewayUrl: pushGatewayUrl,
          encryptMessages: encryptMessages,
          activeStatusEnabled:
              (box.get(_activeStatusKey) as bool?) ?? defaultActiveStatus,
          appearance: appearance,
          chatSortOrder: chatSortOrder,
          encryptionEnabled: client.encryptionEnabled,
          secureBackupAvailable: secureBackupAvailable,
          keyBackupEnabled: keyBackupEnabled,
          encryptedHistoryReady: encryptedHistoryReady,
          isCurrentDeviceVerified: isCurrentDeviceVerified,
          hasOtherDeviceSessions: hasOtherDeviceSessions,
          hasOtherVerifiedDeviceSessions: hasOtherVerifiedDeviceSessions,
          customPrimaryColor: customPrimaryColor,
          alsoMeUserIds: alsoMeUserIds,
        ),
        status: RxStatus.success(),
      );
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }
  }

  Future<void> setAppearance(AppAppearance appearance) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_appearanceKey, appearance.name);
    Get.changeThemeMode(appearance.themeMode);
    change(
      current.copyWith(appearance: appearance),
      status: RxStatus.success(),
    );
  }

  Future<void> setChatSortOrder(ChatSortOrder order) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_chatSortOrderKey, order.name);
    change(current.copyWith(chatSortOrder: order), status: RxStatus.success());
  }

  Future<void> setCustomPrimaryColor(Color color) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_customPrimaryColorKey, color.toARGB32());
    change(
      current.copyWith(customPrimaryColor: color),
      status: RxStatus.success(),
    );
  }

  Future<void> clearCustomPrimaryColor() async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.delete(_customPrimaryColorKey);
    change(
      current.copyWith(clearCustomPrimaryColor: true),
      status: RxStatus.success(),
    );
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final current = state;
    if (current == null) return;
    await _persistNotificationsState(
      enabled: enabled,
      promptSeen: current.notificationsPromptSeen,
    );
  }

  Future<bool> enableNotifications({
    bool requestPermission = true,
    bool markPromptSeen = true,
  }) async {
    final current = state;
    if (current == null) return false;

    var granted = true;
    if (requestPermission) {
      granted = await PushNotificationService().requestPermission();
    }

    await _persistNotificationsState(
      enabled: granted,
      promptSeen: markPromptSeen || current.notificationsPromptSeen,
    );
    return granted;
  }

  Future<void> disableNotifications({bool markPromptSeen = true}) async {
    final current = state;
    if (current == null) return;

    await _persistNotificationsState(
      enabled: false,
      promptSeen: markPromptSeen || current.notificationsPromptSeen,
    );
  }

  Future<void> markNotificationsPromptSeen() async {
    final current = state;
    if (current == null || current.notificationsPromptSeen) return;

    await _persistNotificationsState(
      enabled: current.notificationsEnabled,
      promptSeen: true,
    );
  }

  Future<void> setEncryptMessages(bool enabled) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_encryptMessagesKey, enabled);
    change(
      current.copyWith(encryptMessages: enabled),
      status: RxStatus.success(),
    );
  }

  Future<void> setPushGatewayUrl(String? url) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    if (url == null || url.isEmpty) {
      await box.delete(_pushGatewayUrlKey);
      change(
        current.copyWith(clearPushGatewayUrl: true),
        status: RxStatus.success(),
      );
    } else {
      await box.put(_pushGatewayUrlKey, url);
      change(current.copyWith(pushGatewayUrl: url), status: RxStatus.success());
    }

    final auth = Get.find<AuthController>();
    if (auth.state != null &&
        current.notificationsEnabled &&
        url != null &&
        url.isNotEmpty) {
      await PushNotificationService().registerPusher(url);
    } else if (auth.state != null) {
      await PushNotificationService().unregisterPusher();
    }
  }

  Future<String?> ensurePushGatewayUrl() async {
    final current = state;
    final existing = current?.pushGatewayUrl;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final discovered = await _discoverExistingPushGatewayUrl(
      Get.find<AuthController>().client,
    );
    if (discovered != null && discovered.isNotEmpty) {
      return discovered;
    }

    return _useDefaultPushGatewayUrl();
  }

  Future<String?> _discoverExistingPushGatewayUrl(
    Client client, {
    bool persistToState = true,
  }) async {
    if (client.accessToken == null) return null;

    try {
      final pushers = await client.getPushers();
      final discoveredUrl = _pickExistingPushGatewayUrl(pushers);
      if (discoveredUrl == null || discoveredUrl.isEmpty) {
        return null;
      }

      final box = await _openBox();
      final existing = box.get(_pushGatewayUrlKey) as String?;
      if (existing == discoveredUrl) {
        return discoveredUrl;
      }

      await box.put(_pushGatewayUrlKey, discoveredUrl);
      if (persistToState) {
        final current = state;
        if (current != null) {
          change(
            current.copyWith(pushGatewayUrl: discoveredUrl),
            status: RxStatus.success(),
          );
        }
      }
      debugPrint(
        '[Push] Reusing push gateway from existing Matrix pusher: '
        '$discoveredUrl',
      );
      return discoveredUrl;
    } catch (error) {
      debugPrint('[Push] Could not discover existing push gateway: $error');
      return null;
    }
  }

  Future<String?> _useDefaultPushGatewayUrl() async {
    final configuredDefault = defaultPushGatewayUrl();
    if (configuredDefault == null) {
      return null;
    }

    final box = await _openBox();
    final existing = box.get(_pushGatewayUrlKey) as String?;
    if (existing != configuredDefault) {
      await box.put(_pushGatewayUrlKey, configuredDefault);
    }

    final current = state;
    if (current != null && current.pushGatewayUrl != configuredDefault) {
      change(
        current.copyWith(pushGatewayUrl: configuredDefault),
        status: RxStatus.success(),
      );
    }

    debugPrint(
      '[Push] Using DotMatrix default push gateway: $configuredDefault',
    );
    return configuredDefault;
  }

  String? _pickExistingPushGatewayUrl(List<Pusher>? pushers) {
    if (pushers == null || pushers.isEmpty) return null;

    Pusher? preferred;
    Pusher? fallback;
    for (final pusher in pushers) {
      final url = pusher.data.url?.toString();
      if (pusher.kind != 'http' || url == null || url.isEmpty) {
        continue;
      }

      if (pusher.appId == 'com.housetully.dotmatrix') {
        preferred = pusher;
        break;
      }
      fallback ??= pusher;
    }

    return preferred?.data.url?.toString() ?? fallback?.data.url?.toString();
  }

  Future<void> addAlsoMeUser(String userId) async {
    final current = state;
    if (current == null) return;

    final trimmed = userId.trim();
    if (trimmed.isEmpty) return;

    final box = await _openBox();
    final list = List<String>.from(current.alsoMeUserIds);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await box.put(_alsoMeUserIdsKey, list);
      change(current.copyWith(alsoMeUserIds: list), status: RxStatus.success());
      try {
        await Get.find<RoomController>().refreshRooms();
      } catch (_) {}
    }
  }

  Future<void> removeAlsoMeUser(String userId) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    final list = List<String>.from(current.alsoMeUserIds);
    if (list.remove(userId)) {
      await box.put(_alsoMeUserIdsKey, list);
      change(current.copyWith(alsoMeUserIds: list), status: RxStatus.success());
      try {
        await Get.find<RoomController>().refreshRooms();
      } catch (_) {}
    }
  }

  Future<void> setActiveStatus(bool enabled) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_activeStatusKey, enabled);
    final client = Get.find<AuthController>().client;
    await client.setPresence(
      current.userId,
      enabled ? PresenceType.online : PresenceType.offline,
      statusMsg: _normalizedOrNull(current.statusMessage),
    );

    change(
      current.copyWith(activeStatusEnabled: enabled),
      status: RxStatus.success(),
    );
  }

  Future<void> saveProfile({
    required String displayName,
    required String statusMessage,
    required String deviceName,
  }) async {
    final current = state;
    if (current == null) return;

    final trimmedDisplayName = displayName.trim();
    final trimmedStatusMessage = statusMessage.trim();
    final trimmedDeviceName = deviceName.trim();

    change(current.copyWith(isSavingProfile: true), status: RxStatus.success());

    try {
      final auth = Get.find<AuthController>();
      final client = auth.client;

      await client.setDisplayName(
        current.userId,
        _normalizedOrNull(trimmedDisplayName),
      );
      await client.setPresence(
        current.userId,
        current.activeStatusEnabled
            ? PresenceType.online
            : PresenceType.offline,
        statusMsg: _normalizedOrNull(trimmedStatusMessage),
      );

      if (current.deviceId.isNotEmpty) {
        await client.updateDevice(
          current.deviceId,
          displayName: _nonEmptyOrFallback(
            trimmedDeviceName,
            'DotMatrix Device',
          ),
        );
        await auth.persistDeviceName(
          _nonEmptyOrFallback(trimmedDeviceName, 'DotMatrix Device'),
        );
      }

      change(
        current.copyWith(
          displayName: _nonEmptyOrFallback(trimmedDisplayName, current.userId),
          statusMessage: trimmedStatusMessage,
          deviceName: _nonEmptyOrFallback(
            trimmedDeviceName,
            'DotMatrix Device',
          ),
          isSavingProfile: false,
        ),
        status: RxStatus.success(),
      );
    } catch (error) {
      change(
        current.copyWith(isSavingProfile: false),
        status: RxStatus.error(error.toString()),
      );
      rethrow;
    }
  }

  Future<void> saveDeviceName(String deviceName) async {
    final current = state;
    if (current == null) return;

    final trimmedDeviceName = deviceName.trim();
    final resolvedName = _nonEmptyOrFallback(
      trimmedDeviceName,
      'DotMatrix Device',
    );

    change(current.copyWith(isSavingProfile: true), status: RxStatus.success());

    try {
      final auth = Get.find<AuthController>();
      final client = auth.client;
      if (current.deviceId.isNotEmpty) {
        await client.updateDevice(current.deviceId, displayName: resolvedName);
        await auth.persistDeviceName(resolvedName);
      }

      change(
        current.copyWith(deviceName: resolvedName, isSavingProfile: false),
        status: RxStatus.success(),
      );
    } catch (error) {
      change(
        current.copyWith(isSavingProfile: false),
        status: RxStatus.error(error.toString()),
      );
      rethrow;
    }
  }

  Future<void> pickAvatar() async {
    final current = state;
    if (current == null) return;

    final selected = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (selected == null) return;

    change(
      current.copyWith(isUploadingAvatar: true),
      status: RxStatus.success(),
    );

    try {
      final bytes = await selected.readAsBytes();
      final file = MatrixFile.fromMimeType(bytes: bytes, name: selected.name);
      final client = Get.find<AuthController>().client;
      await client.setAvatar(file);

      await refreshSettings();
      final refreshed = state;
      if (refreshed != null) {
        change(
          refreshed.copyWith(isUploadingAvatar: false),
          status: RxStatus.success(),
        );
      }
    } catch (error) {
      change(
        current.copyWith(isUploadingAvatar: false),
        status: RxStatus.error(error.toString()),
      );
      rethrow;
    }
  }

  Future<void> clearAvatar() async {
    final current = state;
    if (current == null) return;

    change(
      current.copyWith(isUploadingAvatar: true),
      status: RxStatus.success(),
    );

    try {
      final client = Get.find<AuthController>().client;
      await client.setAvatar(null);
      change(
        current.copyWith(clearAvatarUrl: true, isUploadingAvatar: false),
        status: RxStatus.success(),
      );
    } catch (error) {
      change(
        current.copyWith(isUploadingAvatar: false),
        status: RxStatus.error(error.toString()),
      );
      rethrow;
    }
  }

  Future<String> restoreEncryptedHistory(String keyOrPassphrase) async {
    final current = state;
    if (current == null) {
      throw Exception('Settings are not ready yet.');
    }

    final trimmedSecret = keyOrPassphrase.trim();
    if (trimmedSecret.isEmpty) {
      throw Exception('Enter your recovery key or passphrase first.');
    }

    final client = Get.find<AuthController>().client;
    final encryption = client.encryption;
    if (encryption == null || !client.encryptionEnabled) {
      throw Exception(
        'Encryption is not available on this device yet. Rebuild the app and sign in again.',
      );
    }

    await client.accountDataLoading;
    final defaultKeyId = encryption.ssss.defaultKeyId;
    if (defaultKeyId == null) {
      throw Exception(
        'This account does not expose a Secure Backup key. Use another verified device instead.',
      );
    }

    change(
      current.copyWith(isRestoringEncryption: true),
      status: RxStatus.success(),
    );

    try {
      final openSsss = encryption.ssss.open(defaultKeyId);
      await openSsss.unlock(keyOrPassphrase: trimmedSecret);

      if (!encryption.keyManager.enabled) {
        await refreshSettings();
        final refreshed = state;
        if (refreshed != null) {
          change(
            refreshed.copyWith(isRestoringEncryption: false),
            status: RxStatus.success(),
          );
        }
        return 'Secure Backup unlocked, but this account has no room-key backup to restore.';
      }

      await encryption.keyManager.loadAllKeys();
      await Get.find<RoomController>().refreshRooms(rebuildTimelines: true);
      await refreshSettings();
      final refreshed = state;
      if (refreshed != null) {
        change(
          refreshed.copyWith(isRestoringEncryption: false),
          status: RxStatus.success(),
        );
      }
      return 'Encrypted history restored. Reopen any chat that was already on screen.';
    } catch (error) {
      change(
        current.copyWith(isRestoringEncryption: false),
        status: RxStatus.success(),
      );
      rethrow;
    }
  }

  Future<List<DeviceSessionInfo>> fetchDeviceSessions() async {
    final auth = Get.find<AuthController>();
    final client = auth.client;
    final userId = client.userID;
    if (userId == null) {
      return const [];
    }

    await client.updateUserDeviceKeys(additionalUsers: {userId});
    await client.userDeviceKeysLoading;

    final devices = await client.getDevices() ?? [];
    final ownKeys = client.userDeviceKeys[userId];
    final currentId = client.deviceID;

    final list = devices.map((d) {
      final dk = ownKeys?.deviceKeys[d.deviceId];
      final DeviceVerificationLabel v;
      if (dk == null) {
        v = DeviceVerificationLabel.unknown;
      } else if (dk.blocked) {
        v = DeviceVerificationLabel.blocked;
      } else if (d.deviceId == currentId && dk.signed != true) {
        v = DeviceVerificationLabel.unverified;
      } else if (dk.verified) {
        v = DeviceVerificationLabel.verified;
      } else {
        v = DeviceVerificationLabel.unverified;
      }
      return DeviceSessionInfo(
        deviceId: d.deviceId,
        displayName: d.displayName,
        lastSeenTs: d.lastSeenTs,
        isCurrentDevice: d.deviceId == currentId,
        verification: v,
      );
    }).toList();

    list.sort((a, b) {
      if (a.isCurrentDevice != b.isCurrentDevice) {
        return a.isCurrentDevice ? -1 : 1;
      }
      final ta = a.lastSeenTs ?? 0;
      final tb = b.lastSeenTs ?? 0;
      return tb.compareTo(ta);
    });

    return list;
  }

  Future<void> deleteDeviceSession(
    String deviceId, {
    String? password,
    String? authSession,
  }) async {
    final client = Get.find<AuthController>().client;
    final userId = client.userID;
    final trimmedPassword = password?.trim();

    try {
      AuthenticationData? auth;
      if (trimmedPassword != null &&
          trimmedPassword.isNotEmpty &&
          userId != null) {
        auth = AuthenticationPassword(
          identifier: AuthenticationUserIdentifier(user: userId),
          password: trimmedPassword,
          session: authSession,
        );
      }

      await client.deleteDevice(deviceId, auth: auth);
    } on MatrixException catch (error) {
      if (error.requireAdditionalAuthentication) {
        if (trimmedPassword != null && trimmedPassword.isNotEmpty) {
          throw Exception(
            'Failed to confirm your password: ${error.errorMessage}',
          );
        }
        final supportsPassword =
            error.authenticationFlows?.any(
              (flow) => flow.stages.contains(AuthenticationTypes.password),
            ) ??
            false;
        throw DeviceSessionReauthRequired(
          deviceId: deviceId,
          session: error.session,
          supportsPassword: supportsPassword,
        );
      }
      throw Exception('Failed to remove session: ${error.errorMessage}');
    } catch (error) {
      throw Exception('Failed to remove session: $error');
    }
  }

  /// Rotates the Matrix Secure Backup (4s key) passphrase using the Matrix SDK
  /// bootstrap flow. Requires an existing backup on the account.
  Future<String> changeRecoveryPassphrase({
    required String currentSecret,
    required String newPassphrase,
  }) async {
    final trimmedNew = newPassphrase.trim();
    if (trimmedNew.length < 8) {
      throw Exception('Choose a new passphrase with at least 8 characters.');
    }

    final client = Get.find<AuthController>().client;
    final encryption = client.encryption;
    if (encryption == null || !client.encryptionEnabled) {
      throw Exception(
        'Encryption is not available on this device. Rebuild the app and sign in again.',
      );
    }

    await client.accountDataLoading;
    if (encryption.ssss.defaultKeyId == null) {
      throw Exception(
        'This account has no Secure Backup key yet. Set up encryption in another Matrix client, then try again.',
      );
    }

    final completer = Completer<String>();

    void fail(Object e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    encryption.bootstrap(
      onUpdate: (bootstrap) {
        Future<void> step() async {
          try {
            switch (bootstrap.state) {
              case BootstrapState.askWipeSsss:
                bootstrap.wipeSsss(false);
                return;
              case BootstrapState.askUseExistingSsss:
                bootstrap.useExistingSsss(false);
                return;
              case BootstrapState.askBadSsss:
                bootstrap.ignoreBadSecrets(true);
                return;
              case BootstrapState.askUnlockSsss:
                final keys = bootstrap.oldSsssKeys;
                if (keys == null || keys.isEmpty) {
                  throw Exception('Could not read existing backup keys.');
                }
                for (final open in keys.values) {
                  await open.unlock(keyOrPassphrase: currentSecret.trim());
                }
                bootstrap.unlockedSsss();
                return;
              case BootstrapState.askNewSsss:
                if (bootstrap.oldSsssKeys == null &&
                    encryption.ssss.defaultKeyId != null) {
                  throw Exception(
                    'Cannot change the recovery key from this state. Open App settings and finish encrypted history setup first.',
                  );
                }
                await bootstrap.newSsss(trimmedNew);
                return;
              case BootstrapState.askWipeCrossSigning:
                await bootstrap.wipeCrossSigning(false);
                return;
              case BootstrapState.askSetupCrossSigning:
                await bootstrap.askSetupCrossSigning();
                return;
              case BootstrapState.askWipeOnlineKeyBackup:
                bootstrap.wipeOnlineKeyBackup(false);
                return;
              case BootstrapState.askSetupOnlineKeyBackup:
                await bootstrap.askSetupOnlineKeyBackup(false);
                return;
              case BootstrapState.done:
                await refreshSettings();
                if (!completer.isCompleted) {
                  completer.complete('Recovery passphrase updated.');
                }
                return;
              case BootstrapState.error:
                if (!completer.isCompleted) {
                  completer.completeError(
                    Exception(
                      'Recovery key change failed. Check your current recovery key or passphrase.',
                    ),
                  );
                }
                return;
              default:
                return;
            }
          } catch (e) {
            fail(e is Exception ? e : Exception(e.toString()));
          }
        }

        unawaited(step());
      },
    );

    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException(
        'Recovery key change timed out. Check your network and try again.',
      ),
    );
  }

  Future<String> requestEncryptedHistoryFromVerifiedDevices() async {
    final current = state;
    if (current == null) {
      throw Exception('Settings are not ready yet.');
    }

    final client = Get.find<AuthController>().client;
    final encryption = client.encryption;
    if (encryption == null || !client.encryptionEnabled) {
      throw Exception(
        'Encryption is not available on this device yet. Rebuild the app and sign in again.',
      );
    }

    change(
      current.copyWith(isRestoringEncryption: true),
      status: RxStatus.success(),
    );

    try {
      final userId = client.userID;
      if (userId != null) {
        await client.updateUserDeviceKeys(additionalUsers: {userId});
      }
      await client.userDeviceKeysLoading;

      final ownKeys = userId != null ? client.userDeviceKeys[userId] : null;
      final currentDeviceId = client.deviceID;
      final otherDevices =
          ownKeys?.deviceKeys.values
              .where((dk) => dk.deviceId != currentDeviceId)
              .toList() ??
          [];
      final hasOtherDevice = otherDevices.isNotEmpty;
      final hasOtherVerifiedDevice = otherDevices.any((dk) => dk.verified);

      debugPrint(
        '[KeyRequest] currentDevice=$currentDeviceId totalOthers=${otherDevices.length} verifiedOthers=${otherDevices.where((dk) => dk.verified).length}',
      );
      for (final dk in otherDevices) {
        debugPrint(
          '[KeyRequest] device=${dk.deviceId} verified=${dk.verified} blocked=${dk.blocked}',
        );
      }

      if (!hasOtherDevice) {
        change(
          current.copyWith(isRestoringEncryption: false),
          status: RxStatus.success(),
        );
        return 'No other devices found on this account. Sign in on another Matrix app first, or use your recovery key below.';
      }

      if (!hasOtherVerifiedDevice) {
        change(
          current.copyWith(isRestoringEncryption: false),
          status: RxStatus.success(),
        );
        return 'Other devices exist but none are verified. Verify one of them (e.g., in Element Desktop settings > Sessions) then try again, or use your recovery key below.';
      }

      await encryption.ssss.maybeRequestAll();
      await Get.find<RoomController>().requestMissingEncryptionKeys();
      debugPrint(
        '[KeyRequest] Sent requests via ssss.maybeRequestAll and roomController.requestMissingEncryptionKeys',
      );
      await refreshSettings();
      final refreshed = state;
      if (refreshed != null) {
        change(
          refreshed.copyWith(isRestoringEncryption: false),
          status: RxStatus.success(),
        );
      }
      return 'Sent key requests to your verified devices. Keep the other Matrix app open for a moment.';
    } catch (error) {
      change(
        current.copyWith(isRestoringEncryption: false),
        status: RxStatus.success(),
      );
      rethrow;
    }
  }

  Future<void> refreshAfterDeviceVerification() async {
    final client = Get.find<AuthController>().client;
    final encryption = client.encryption;
    if (encryption != null) {
      await encryption.ssss.maybeRequestAll();
    }
    await Get.find<RoomController>().requestMissingEncryptionKeys();
    await Get.find<RoomController>().refreshRooms(rebuildTimelines: true);
    await refreshSettings();
  }

  Future<KeyVerification> startDeviceVerification() async {
    final client = Get.find<AuthController>().client;
    final encryption = client.encryption;
    if (encryption == null) {
      throw Exception('Encryption is not available.');
    }
    final userId = client.userID;
    if (userId == null) {
      throw Exception('Not signed in.');
    }

    await client.updateUserDeviceKeys(additionalUsers: {userId});
    await client.userDeviceKeysLoading;

    final ownKeys = client.userDeviceKeys[userId];
    final otherKeys =
        ownKeys?.deviceKeys.values
            .where((dk) => dk.deviceId != client.deviceID)
            .toList() ??
        [];

    if (otherKeys.isEmpty) {
      throw Exception('No other devices found on this account.');
    }

    final serverDevices = await client.getDevices() ?? [];
    final currentId = client.deviceID;
    final candidates = serverDevices
        .where((d) => d.deviceId != currentId)
        .toList();
    candidates.sort((a, b) {
      final ta = a.lastSeenTs ?? 0;
      final tb = b.lastSeenTs ?? 0;
      return tb.compareTo(ta);
    });

    final targetDeviceId = candidates.isNotEmpty
        ? candidates.first.deviceId
        : otherKeys.first.deviceId;

    final request = KeyVerification(
      encryption: encryption,
      userId: userId,
      deviceId: targetDeviceId,
    );
    await request.start();
    encryption.keyVerificationManager.addRequest(request);
    return request;
  }

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  Future<void> _persistNotificationsState({
    required bool enabled,
    required bool promptSeen,
  }) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_notificationsKey, enabled);
    await box.put(_notificationsPromptSeenKey, promptSeen);
    change(
      current.copyWith(
        notificationsEnabled: enabled,
        notificationsPromptSeen: promptSeen,
      ),
      status: RxStatus.success(),
    );

    final auth = Get.find<AuthController>();
    if (auth.state == null) return;

    final pushGatewayUrl = current.pushGatewayUrl;
    if (enabled) {
      final effectivePushGatewayUrl =
          (pushGatewayUrl != null && pushGatewayUrl.isNotEmpty)
          ? pushGatewayUrl
          : await ensurePushGatewayUrl();
      if (effectivePushGatewayUrl != null &&
          effectivePushGatewayUrl.isNotEmpty) {
        await PushNotificationService().registerPusher(effectivePushGatewayUrl);
        return;
      }
      debugPrint(
        '[Push] Notifications enabled, but no Matrix push gateway could be '
        'discovered for background delivery.',
      );
      return;
    } else {
      await PushNotificationService().unregisterPusher();
    }
  }

  String _nonEmptyOrFallback(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String? _normalizedOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
