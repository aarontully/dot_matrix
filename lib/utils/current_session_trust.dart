import 'package:matrix/matrix.dart';

bool isCurrentSessionTrusted(Client client) {
  final userId = client.userID;
  final deviceId = client.deviceID;
  if (userId == null ||
      userId.isEmpty ||
      deviceId == null ||
      deviceId.isEmpty) {
    return false;
  }

  return client.userDeviceKeys[userId]?.deviceKeys[deviceId]?.signed == true;
}

bool isCurrentSessionVerified(Client client) {
  final userId = client.userID;
  final deviceId = client.deviceID;
  if (userId == null ||
      userId.isEmpty ||
      deviceId == null ||
      deviceId.isEmpty) {
    return false;
  }

  return client.userDeviceKeys[userId]?.deviceKeys[deviceId]?.verified == true;
}
