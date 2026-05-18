import 'package:flutter/material.dart';

enum AppAppearance { light, dark, system }

enum ChatSortOrder { newest, unreadFirst }

extension AppAppearanceX on AppAppearance {
  String get label => switch (this) {
    AppAppearance.light => 'Light',
    AppAppearance.dark => 'Dark',
    AppAppearance.system => 'System',
  };

  ThemeMode get themeMode => switch (this) {
    AppAppearance.light => ThemeMode.light,
    AppAppearance.dark => ThemeMode.dark,
    AppAppearance.system => ThemeMode.system,
  };

  static AppAppearance fromStorage(String? value) {
    for (final appearance in AppAppearance.values) {
      if (appearance.name == value) {
        return appearance;
      }
    }
    return AppAppearance.light;
  }

  static AppAppearance fromThemeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => AppAppearance.light,
      ThemeMode.dark => AppAppearance.dark,
      ThemeMode.system => AppAppearance.system,
    };
  }
}

extension ChatSortOrderX on ChatSortOrder {
  String get label => switch (this) {
    ChatSortOrder.newest => 'Newest to oldest',
    ChatSortOrder.unreadFirst => 'Unread first',
  };

  static ChatSortOrder fromStorage(String? value) {
    for (final order in ChatSortOrder.values) {
      if (order.name == value) {
        return order;
      }
    }
    return ChatSortOrder.newest;
  }
}

class SettingsState {
  const SettingsState({
    required this.displayName,
    required this.statusMessage,
    required this.userId,
    required this.homeserver,
    required this.deviceId,
    required this.deviceName,
    required this.notificationsEnabled,
    required this.activeStatusEnabled,
    required this.appearance,
    required this.chatSortOrder,
    required this.encryptionEnabled,
    required this.secureBackupAvailable,
    required this.keyBackupEnabled,
    required this.encryptedHistoryReady,
    this.avatarUrl,
    this.isSavingProfile = false,
    this.isUploadingAvatar = false,
    this.isRestoringEncryption = false,
    this.customPrimaryColor,
  });

  final String displayName;
  final String statusMessage;
  final Uri? avatarUrl;
  final String userId;
  final String homeserver;
  final String deviceId;
  final String deviceName;
  final bool notificationsEnabled;
  final bool activeStatusEnabled;
  final AppAppearance appearance;
  final ChatSortOrder chatSortOrder;
  final bool encryptionEnabled;
  final bool secureBackupAvailable;
  final bool keyBackupEnabled;
  final bool encryptedHistoryReady;
  final bool isSavingProfile;
  final bool isUploadingAvatar;
  final bool isRestoringEncryption;
  final Color? customPrimaryColor;

  String get initials {
    final source = displayName.trim().isNotEmpty ? displayName.trim() : userId;
    final pieces = source
        .split(RegExp(r'\s+'))
        .where((piece) => piece.isNotEmpty)
        .take(2)
        .toList();
    if (pieces.isEmpty) {
      return 'DM';
    }
    return pieces.map((piece) => piece[0].toUpperCase()).join();
  }

  SettingsState copyWith({
    String? displayName,
    String? statusMessage,
    Uri? avatarUrl,
    bool clearAvatarUrl = false,
    String? userId,
    String? homeserver,
    String? deviceId,
    String? deviceName,
    bool? notificationsEnabled,
    bool? activeStatusEnabled,
    AppAppearance? appearance,
    ChatSortOrder? chatSortOrder,
    bool? encryptionEnabled,
    bool? secureBackupAvailable,
    bool? keyBackupEnabled,
    bool? encryptedHistoryReady,
    bool? isSavingProfile,
    bool? isUploadingAvatar,
    bool? isRestoringEncryption,
    Color? customPrimaryColor,
    bool clearCustomPrimaryColor = false,
  }) {
    return SettingsState(
      displayName: displayName ?? this.displayName,
      statusMessage: statusMessage ?? this.statusMessage,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      userId: userId ?? this.userId,
      homeserver: homeserver ?? this.homeserver,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      activeStatusEnabled: activeStatusEnabled ?? this.activeStatusEnabled,
      appearance: appearance ?? this.appearance,
      chatSortOrder: chatSortOrder ?? this.chatSortOrder,
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      secureBackupAvailable:
          secureBackupAvailable ?? this.secureBackupAvailable,
      keyBackupEnabled: keyBackupEnabled ?? this.keyBackupEnabled,
      encryptedHistoryReady:
          encryptedHistoryReady ?? this.encryptedHistoryReady,
      isSavingProfile: isSavingProfile ?? this.isSavingProfile,
      isUploadingAvatar: isUploadingAvatar ?? this.isUploadingAvatar,
      isRestoringEncryption:
          isRestoringEncryption ?? this.isRestoringEncryption,
      customPrimaryColor: clearCustomPrimaryColor
          ? null
          : customPrimaryColor ?? this.customPrimaryColor,
    );
  }
}
