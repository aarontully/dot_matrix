import 'package:matrix/matrix.dart';

import 'matrix_media_uri.dart';

final Set<String> _brokenAvatarSources = <String>{};

String? resolveAvatarImageUrl(
  Uri? avatarUri,
  Client client, {
  required int size,
}) {
  if (avatarUri == null) {
    return null;
  }

  final sourceKey = avatarUri.toString();
  if (sourceKey.isEmpty || _brokenAvatarSources.contains(sourceKey)) {
    return null;
  }

  final resolvedUri = avatarUri.isScheme('mxc')
      ? withMatrixMediaAllowRedirect(mxcToClientV1MediaThumbnail(
          avatarUri,
          client,
          width: size,
          height: size,
          method: ThumbnailMethod.crop,
        ))
      : avatarUri;
  final resolvedValue = resolvedUri.toString();
  return resolvedValue.isEmpty ? null : resolvedValue;
}

void markAvatarSourceBroken(Uri? avatarUri) {
  final sourceKey = avatarUri?.toString();
  if (sourceKey == null || sourceKey.isEmpty) {
    return;
  }
  _brokenAvatarSources.add(sourceKey);
}

void clearBrokenAvatarSources() {
  _brokenAvatarSources.clear();
}
