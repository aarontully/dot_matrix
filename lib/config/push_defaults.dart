const String _defaultPushGatewayUrl = String.fromEnvironment(
  'DOT_MATRIX_DEFAULT_PUSH_GATEWAY_URL',
  defaultValue: '',
);

String? defaultPushGatewayUrl() {
  final trimmed = _defaultPushGatewayUrl.trim();
  return trimmed.isEmpty ? null : trimmed;
}
