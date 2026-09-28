import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps auth tokens in the Keychain (iOS) / EncryptedSharedPreferences
/// (Android), with an in-memory cache so every request doesn't hit disk.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'fanitt.accessToken';
  static const _refreshKey = 'fanitt.refreshToken';

  String? _accessToken;
  String? _refreshToken;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    _loaded = true;
  }

  Future<String?> get accessToken async {
    await _ensureLoaded();
    return _accessToken;
  }

  Future<String?> get refreshToken async {
    await _ensureLoaded();
    return _refreshToken;
  }

  Future<void> save({required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    await _storage.write(key: _accessKey, value: accessToken);
    if (refreshToken != null) {
      _refreshToken = refreshToken;
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
    _loaded = true;
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
