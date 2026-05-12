import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

class AuthController extends GetxController with StateMixin<String?> {
  static const _storageTokenKey = 'matrix_token';
  static const _storageUserIdKey = 'matrix_user_id';
  static const _storageHomeserverKey = 'matrix_homeserver';
  static const _storageDeviceIdKey = 'matrix_device_id';
  static const _storageDeviceNameKey = 'matrix_device_name';
  static const _defaultDeviceName = 'DotMatrix';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Client _client = Client('Dot Matrix');
  bool isDummy = false;

  Client get client => _client;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<Client> _createClient() async {
    final dir = await getApplicationSupportDirectory();
    return Client(
      'Dot Matrix',
      databaseBuilder: (_) async {
        final db = HiveCollectionsDatabase('matrix', dir.path);
        await db.open();
        return db;
      },
    );
  }

  Future<void> _init() async {
    change(null, status: RxStatus.loading());
    try {
      final storedValues = await _storage.readAll();
      final accessToken = storedValues[_storageTokenKey];
      final userId = storedValues[_storageUserIdKey];
      final homeserver = storedValues[_storageHomeserverKey];
      final deviceId = storedValues[_storageDeviceIdKey];
      final deviceName =
          storedValues[_storageDeviceNameKey] ?? _defaultDeviceName;

      if (accessToken == null ||
          userId == null ||
          homeserver == null ||
          deviceId == null) {
        change(null, status: RxStatus.success());
        return;
      }

      _client = await _createClient();
      await _client.init(
        newToken: accessToken,
        newHomeserver: Uri.parse(homeserver),
        newUserID: userId,
        newDeviceID: deviceId,
        newDeviceName: deviceName,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      isDummy = false;
      change(userId, status: RxStatus.success());
    } catch (error) {
      await _clearStoredSession();
      _client = await _createClient();
      change(null, status: RxStatus.error(error.toString()));
      // Fallback to success with null to show login screen
      change(null, status: RxStatus.success());
    }
  }

  Future<void> login(
    String username,
    String password,
    String homeserver,
  ) async {
    change(null, status: RxStatus.loading());
    try {
      _client = await _createClient();
      await _client.checkHomeserver(Uri.parse(homeserver));
      final resolvedHomeserver = _client.homeserver ?? Uri.parse(homeserver);
      final matrixApi = MatrixApi(homeserver: resolvedHomeserver);
      final loginResponse = await matrixApi.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: _defaultDeviceName,
      );

      await _client.init(
        newToken: loginResponse.accessToken,
        newHomeserver: resolvedHomeserver,
        newUserID: loginResponse.userId,
        newDeviceID: loginResponse.deviceId,
        newDeviceName: _defaultDeviceName,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );

      await _persistSession(
        accessToken: loginResponse.accessToken,
        userId: loginResponse.userId,
        homeserver: resolvedHomeserver.toString(),
        deviceId: loginResponse.deviceId,
        deviceName: _defaultDeviceName,
      );

      isDummy = false;
      change(loginResponse.userId, status: RxStatus.success());
    } catch (error) {
      change(null, status: RxStatus.error(error.toString()));
    }
  }

  Future<void> continueWithDemo() async {
    change(null, status: RxStatus.loading());
    await _clearStoredSession();
    _client = await _createClient();
    isDummy = true;
    change('dummy_user', status: RxStatus.success());
  }

  Future<void> persistDeviceName(String deviceName) async {
    await _storage.write(key: _storageDeviceNameKey, value: deviceName);
  }

  Future<void> logout() async {
    change(state, status: RxStatus.loading());
    try {
      if (!isDummy) {
        await _client.logout();
      }
    } catch (_) {
      // Best effort logout. Local cleanup still matters more here.
    }

    await _clearStoredSession();
    _client = await _createClient();
    isDummy = false;
    change(null, status: RxStatus.success());
  }

  Future<void> _persistSession({
    required String accessToken,
    required String userId,
    required String homeserver,
    required String deviceId,
    required String deviceName,
  }) async {
    await _storage.write(key: _storageTokenKey, value: accessToken);
    await _storage.write(key: _storageUserIdKey, value: userId);
    await _storage.write(key: _storageHomeserverKey, value: homeserver);
    await _storage.write(key: _storageDeviceIdKey, value: deviceId);
    await _storage.write(key: _storageDeviceNameKey, value: deviceName);
  }

  Future<void> _clearStoredSession() async {
    await _storage.delete(key: _storageTokenKey);
    await _storage.delete(key: _storageUserIdKey);
    await _storage.delete(key: _storageHomeserverKey);
    await _storage.delete(key: _storageDeviceIdKey);
    await _storage.delete(key: _storageDeviceNameKey);
  }
}
