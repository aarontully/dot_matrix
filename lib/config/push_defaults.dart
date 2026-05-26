const String _defaultPushGatewayUrl = String.fromEnvironment(
  'DOT_MATRIX_DEFAULT_PUSH_GATEWAY_URL',
  defaultValue: '',
);
const String _allowedPushGatewayHosts = String.fromEnvironment(
  'DOT_MATRIX_ALLOWED_PUSH_GATEWAY_HOSTS',
  defaultValue: '',
);

String? defaultPushGatewayUrl() {
  final trimmed = _defaultPushGatewayUrl.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> configuredPushGatewayHosts() {
  return _allowedPushGatewayHosts
      .split(',')
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toList(growable: false);
}
