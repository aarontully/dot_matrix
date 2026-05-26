import 'package:matrix/matrix.dart';

/// MSC3860: opt into redirect-capable media fetches (CDN, etc.).
Uri withMatrixMediaAllowRedirect(Uri uri) {
  if (uri.queryParameters['allow_redirect'] == 'true') {
    return uri;
  }
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'allow_redirect': 'true',
    },
  );
}

/// MSC3916: authenticated client-server media (replaces deprecated
/// `/_matrix/media/v3/download` for servers that freeze unauthenticated media).
Uri mxcToClientV1MediaDownload(Uri mxcUri, Client client) {
  if (!mxcUri.isScheme('mxc')) return mxcUri;
  final homeserver = client.homeserver;
  if (homeserver == null) return Uri();
  return homeserver.resolve(
    '_matrix/client/v1/media/download/${mxcUri.host}${mxcUri.hasPort ? ':${mxcUri.port}' : ''}${mxcUri.path}',
  );
}

/// MSC3916 thumbnail counterpart to [mxcToClientV1MediaDownload].
Uri mxcToClientV1MediaThumbnail(
  Uri mxcUri,
  Client client, {
  num? width,
  num? height,
  ThumbnailMethod? method = ThumbnailMethod.crop,
  bool? animated = false,
}) {
  if (!mxcUri.isScheme('mxc')) return mxcUri;
  final homeserver = client.homeserver;
  if (homeserver == null) return Uri();
  return Uri(
    scheme: homeserver.scheme,
    host: homeserver.host,
    port: homeserver.port,
    path:
        '/_matrix/client/v1/media/thumbnail/${mxcUri.host}${mxcUri.hasPort ? ':${mxcUri.port}' : ''}${mxcUri.path}',
    queryParameters: {
      if (width != null) 'width': width.round().toString(),
      if (height != null) 'height': height.round().toString(),
      if (method != null) 'method': method.toString().split('.').last,
      if (animated != null) 'animated': animated.toString(),
    },
  );
}

/// Rewrites URLs produced by the `matrix` package (`getDownloadLink` /
/// `getThumbnail`) to MSC3916 client endpoints. Used for encrypted attachment
/// fetches where the SDK still emits `/_matrix/media/v3/...`.
Uri upgradeMatrixMediaV3UrlToClientV1(Uri url) {
  if (url.path.startsWith('/_matrix/media/v3/download/')) {
    return url.replace(
      path: url.path.replaceFirst(
        '/_matrix/media/v3/download/',
        '/_matrix/client/v1/media/download/',
      ),
    );
  }
  if (url.path.startsWith('/_matrix/media/v3/thumbnail/')) {
    return url.replace(
      path: url.path.replaceFirst(
        '/_matrix/media/v3/thumbnail/',
        '/_matrix/client/v1/media/thumbnail/',
      ),
    );
  }
  return url;
}

/// Uses Matrix's token query authentication for media endpoints so redirects do
/// not forward a bearer Authorization header to third-party CDNs.
Uri authenticatedMatrixMediaUri(Uri uri, Client client) {
  final accessToken = client.accessToken;
  if (accessToken == null || accessToken.isEmpty) {
    return uri;
  }

  final isMatrixMediaPath =
      uri.path.startsWith('/_matrix/client/v1/media/') ||
      uri.path.startsWith('/_matrix/media/v3/');
  final sameHost =
      client.homeserver != null &&
      uri.host == client.homeserver!.host &&
      uri.scheme == client.homeserver!.scheme;
  if (!isMatrixMediaPath || !sameHost) {
    return uri;
  }

  if (uri.queryParameters['access_token'] == accessToken) {
    return uri;
  }

  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'access_token': accessToken,
    },
  );
}
