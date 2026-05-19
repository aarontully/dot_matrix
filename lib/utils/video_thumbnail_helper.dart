import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

final FcNativeVideoThumbnail _videoThumbnailer = FcNativeVideoThumbnail();

bool get supportsVideoThumbnailGeneration {
  if (kIsWeb) return false;
  return Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
}

Future<Uint8List?> generateVideoThumbnailBytesFromFile(
  String videoPath, {
  int maxWidth = 320,
  int maxHeight = 320,
  int quality = 80,
}) async {
  if (!supportsVideoThumbnailGeneration) return null;

  try {
    return await _videoThumbnailer.saveThumbnailToBytes(
      srcFile: videoPath,
      width: maxWidth,
      height: maxHeight,
      format: 'jpeg',
      quality: quality,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> generateVideoThumbnailBytesFromBytes(
  Uint8List videoBytes, {
  required String fileName,
  int maxWidth = 320,
  int maxHeight = 320,
  int quality = 80,
}) async {
  if (!supportsVideoThumbnailGeneration) return null;

  final tempDir = await getTemporaryDirectory();
  final extension = _extensionFor(fileName, fallback: 'mp4');
  final tempFile = File(
    '${tempDir.path}/video_thumb_${DateTime.now().microsecondsSinceEpoch}.$extension',
  );

  try {
    await tempFile.writeAsBytes(videoBytes, flush: true);
    return await generateVideoThumbnailBytesFromFile(
      tempFile.path,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {
      // Ignore temp-file cleanup failures.
    }
  }
}

Future<MatrixImageFile?> createMatrixVideoThumbnail(
  String videoPath, {
  required String fileName,
  int maxWidth = 320,
  int maxHeight = 320,
  int quality = 80,
}) async {
  final bytes = await generateVideoThumbnailBytesFromFile(
    videoPath,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    quality: quality,
  );
  if (bytes == null || bytes.isEmpty) return null;

  return MatrixImageFile.create(
    bytes: bytes,
    name: _thumbnailNameFor(fileName),
    mimeType: 'image/jpeg',
  );
}

Future<({int? width, int? height, int? durationMs})> loadVideoMetadata(
  File file,
) async {
  final controller = VideoPlayerController.file(file);

  try {
    await controller.initialize();
    final size = controller.value.size;
    final duration = controller.value.duration;
    return (
      width: size.width > 0 ? size.width.round() : null,
      height: size.height > 0 ? size.height.round() : null,
      durationMs: duration.inMilliseconds > 0 ? duration.inMilliseconds : null,
    );
  } catch (_) {
    return (width: null, height: null, durationMs: null);
  } finally {
    await controller.dispose();
  }
}

String _thumbnailNameFor(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  return '${baseName}_thumb.jpg';
}

String _extensionFor(String fileName, {required String fallback}) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return fallback;
  }
  return fileName.substring(dotIndex + 1);
}
