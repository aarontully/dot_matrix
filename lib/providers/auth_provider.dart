import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<String?>>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AsyncValue<String?>> {
  Client _client = Client('Dot Matrix');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool isDummy = true;

  AuthNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    // Dummy login for testing
    _client = Client('Dot Matrix');
    state = AsyncValue.data('dummy_user');
  }

  Future<void> login(String username, String password, String homeserver) async {
    state = const AsyncValue.loading();
    try {
      _client = Client('Dot Matrix');
      await _client.checkHomeserver(Uri.parse(homeserver));
      final loginResponse = await _client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
      );

      await _storage.write(key: 'matrix_token', value: loginResponse.accessToken);
      await _storage.write(key: 'matrix_user_id', value: loginResponse.userId);
      await _storage.write(key: 'matrix_homeserver', value: homeserver);

      state = AsyncValue.data(loginResponse.userId);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> logout() async {
    try {
      await _client.logout();
    } catch (_) {}
    await _storage.delete(key: 'matrix_token');
    await _storage.delete(key: 'matrix_user_id');
    await _storage.delete(key: 'matrix_homeserver');
    state = const AsyncValue.data(null);
  }

  Client get client => _client;
}