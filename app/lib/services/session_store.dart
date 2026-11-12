import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Persistance locale : jeton JWT + jeton de rafraîchissement + URL de l'API.
/// `flutter_secure_storage` fonctionne aussi sur le web.
class SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'esystem_token';
  static const _refreshTokenKey = 'esystem_refresh_token';
  static const _apiUrlKey = 'esystem_api_url';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshTokenKey);

  Future<String> readApiUrl() async =>
      (await _storage.read(key: _apiUrlKey)) ?? AppConfig.defaultApiBaseUrl;

  Future<void> saveApiUrl(String url) =>
      _storage.write(key: _apiUrlKey, value: url);
}
