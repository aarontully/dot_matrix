import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'secure_storage_recovery.dart';

const String _configuredTlsPins = String.fromEnvironment(
  'DOT_MATRIX_TLS_PINS',
  defaultValue: '',
);

final FlutterSecureStorage _tlsStorage = const FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: true),
);

http.Client createPinnedHttpClient() {
  return _PinnedHttpClient();
}

HttpClient createPinnedIoHttpClient() {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  return client;
}

Future<void> validatePinnedTlsCertificate(
  Uri url,
  X509Certificate? certificate,
) async {
  if (certificate == null) {
    return;
  }

  final fingerprint = _fingerprintHex(certificate.sha1);
  final configuredPins = _configuredPinsForHost(url.host);
  if (configuredPins.isNotEmpty && !configuredPins.contains(fingerprint)) {
    throw HandshakeException('TLS pin mismatch for ${url.host}');
  }

  final storageKey = 'tls_pin::${url.host.toLowerCase()}';
  String? storedPin;
  try {
    storedPin = await _tlsStorage.read(key: storageKey);
  } catch (error) {
    if (isSecureStorageDecryptionError(error)) {
      try {
        await _tlsStorage.delete(key: storageKey);
      } catch (_) {
        // Best effort cleanup for a broken stored pin.
      }
      storedPin = null;
    } else {
      rethrow;
    }
  }
  if (storedPin == null || storedPin.isEmpty) {
    await _tlsStorage.write(key: storageKey, value: fingerprint);
    return;
  }

  if (configuredPins.isEmpty && storedPin != fingerprint) {
    throw HandshakeException(
      'TLS certificate changed unexpectedly for ${url.host}',
    );
  }
}

Set<String> _configuredPinsForHost(String host) {
  final normalizedHost = host.toLowerCase();
  final pins = <String>{};
  for (final hostEntry in _configuredTlsPins.split(';')) {
    final trimmedEntry = hostEntry.trim();
    if (trimmedEntry.isEmpty) continue;

    final separator = trimmedEntry.indexOf('=');
    if (separator <= 0 || separator == trimmedEntry.length - 1) continue;

    final entryHost = trimmedEntry.substring(0, separator).trim().toLowerCase();
    if (entryHost != normalizedHost) continue;

    final rawPins = trimmedEntry.substring(separator + 1);
    for (final pin in rawPins.split(',')) {
      final normalizedPin = pin.trim().toLowerCase().replaceAll(':', '');
      if (normalizedPin.isNotEmpty) {
        pins.add(normalizedPin);
      }
    }
  }
  return pins;
}

String _fingerprintHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

class _PinnedHttpClient extends http.BaseClient {
  _PinnedHttpClient() : _inner = createPinnedIoHttpClient();

  final HttpClient _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final stream = request.finalize();
      final ioRequest = await _inner.openUrl(request.method, request.url)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = request.contentLength ?? -1
        ..persistentConnection = request.persistentConnection;
      request.headers.forEach(ioRequest.headers.set);

      final response = await stream.pipe(ioRequest) as HttpClientResponse;
      final effectiveUrl = response.redirects.isNotEmpty
          ? response.redirects.last.location
          : request.url;
      await validatePinnedTlsCertificate(effectiveUrl, response.certificate);

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.map((value) => value.trimRight()).join(',');
      });

      return http.StreamedResponse(
        response.handleError((Object error) {
          final httpException = error as HttpException;
          throw http.ClientException(httpException.message, httpException.uri);
        }, test: (error) => error is HttpException),
        response.statusCode,
        contentLength: response.contentLength == -1
            ? null
            : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    }
  }

  @override
  void close() {
    _inner.close(force: true);
  }
}
