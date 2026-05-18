enum DeviceVerificationLabel { verified, unverified, blocked, unknown }

class DeviceSessionInfo {
  const DeviceSessionInfo({
    required this.deviceId,
    required this.displayName,
    required this.lastSeenTs,
    required this.isCurrentDevice,
    required this.verification,
  });

  final String deviceId;
  final String? displayName;
  final int? lastSeenTs;
  final bool isCurrentDevice;
  final DeviceVerificationLabel verification;
}
