import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

bool isSecureStorageDecryptionError(Object error) {
  final message = switch (error) {
    PlatformException() =>
      '${error.code} ${error.message ?? ''} ${error.details ?? ''}',
    _ => error.toString(),
  };
  final normalized = message.toLowerCase();

  return normalized.contains('bad_decrypt') ||
      normalized.contains('badpaddingexception') ||
      normalized.contains('aeadbadtagexception') ||
      normalized.contains('failed to unwrap keyset') ||
      normalized.contains('keystore operation failed');
}

Future<void> clearSecureStorageSafely(FlutterSecureStorage storage) async {
  try {
    await storage.deleteAll();
  } catch (_) {
    // Best effort recovery for corrupted secure storage.
  }
}
