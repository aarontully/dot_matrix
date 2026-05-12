import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../models/settings_state.dart';
import 'auth_controller.dart';
import 'room_controller.dart';

class SettingsController extends GetxController with StateMixin<SettingsState> {
  static const _boxName = 'dot_matrix_settings';
  static const _notificationsKey = 'notifications_enabled';
  static const _appearanceKey = 'appearance';
  static const _chatSortOrderKey = 'chat_sort_order';
  static const _activeStatusKey = 'active_status_enabled';
  static const _demoDisplayNameKey = 'demo_display_name';
  static const _demoStatusMessageKey = 'demo_status_message';
  static const _demoDeviceNameKey = 'demo_device_name';

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
    Get.changeThemeMode(appearance.themeMode);
    final notificationsEnabled = (box.get(_notificationsKey) as bool?) ?? true;

    if (auth.isDummy || client.userID == null) {
      change(
        SettingsState(
          displayName:
              (box.get(_demoDisplayNameKey) as String?) ?? 'DotMatrix Demo',
          statusMessage:
              (box.get(_demoStatusMessageKey) as String?) ??
              'Exploring the app',
          userId: 'dummy_user',
          homeserver: 'Demo mode',
          deviceId: 'simulator',
          deviceName: (box.get(_demoDeviceNameKey) as String?) ?? 'Demo Device',
          notificationsEnabled: notificationsEnabled,
          activeStatusEnabled: (box.get(_activeStatusKey) as bool?) ?? true,
          appearance: appearance,
          chatSortOrder: chatSortOrder,
          encryptionEnabled: false,
          secureBackupAvailable: false,
          keyBackupEnabled: false,
          encryptedHistoryReady: false,
          isDemoMode: true,
        ),
        status: RxStatus.success(),
      );
      return;
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
          activeStatusEnabled:
              (box.get(_activeStatusKey) as bool?) ?? defaultActiveStatus,
          appearance: appearance,
          chatSortOrder: chatSortOrder,
          encryptionEnabled: client.encryptionEnabled,
          secureBackupAvailable: secureBackupAvailable,
          keyBackupEnabled: keyBackupEnabled,
          encryptedHistoryReady: encryptedHistoryReady,
          isDemoMode: false,
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

  Future<void> setNotificationsEnabled(bool enabled) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_notificationsKey, enabled);
    change(
      current.copyWith(notificationsEnabled: enabled),
      status: RxStatus.success(),
    );
  }

  Future<void> setActiveStatus(bool enabled) async {
    final current = state;
    if (current == null) return;

    final box = await _openBox();
    await box.put(_activeStatusKey, enabled);

    if (!current.isDemoMode) {
      final client = Get.find<AuthController>().client;
      await client.setPresence(
        current.userId,
        enabled ? PresenceType.online : PresenceType.offline,
        statusMsg: _normalizedOrNull(current.statusMessage),
      );
    }

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
      if (current.isDemoMode) {
        final box = await _openBox();
        await box.put(_demoDisplayNameKey, trimmedDisplayName);
        await box.put(_demoStatusMessageKey, trimmedStatusMessage);
        await box.put(_demoDeviceNameKey, trimmedDeviceName);

        change(
          current.copyWith(
            displayName: trimmedDisplayName,
            statusMessage: trimmedStatusMessage,
            deviceName: trimmedDeviceName,
            isSavingProfile: false,
          ),
          status: RxStatus.success(),
        );
        return;
      }

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
    if (current.isDemoMode) {
      throw Exception(
        'Connect to a Matrix account to update your device label.',
      );
    }

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
    if (current.isDemoMode) {
      throw Exception('Connect to a Matrix account to sync your avatar.');
    }

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
    if (current.isDemoMode) {
      throw Exception('Connect to a Matrix account to remove your avatar.');
    }

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
    if (current.isDemoMode) {
      throw Exception(
        'Connect to a Matrix account before restoring encryption keys.',
      );
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

  Future<String> requestEncryptedHistoryFromVerifiedDevices() async {
    final current = state;
    if (current == null) {
      throw Exception('Settings are not ready yet.');
    }
    if (current.isDemoMode) {
      throw Exception('Connect to a Matrix account before requesting keys.');
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
      await client.userDeviceKeysLoading;
      await encryption.ssss.maybeRequestAll();
      await Get.find<RoomController>().requestMissingEncryptionKeys();
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

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
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
