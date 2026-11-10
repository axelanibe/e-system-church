import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Persistance locale : jeton JWT + réglages (mode démo, URL de l'API).
/// `flutter_secure_storage` fonctionne aussi sur le web.
class SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'esystem_token';
  static const _demoKey = 'esystem_demo_mode';
  static const _apiUrlKey = 'esystem_api_url';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  /// Mode démo par défaut (true) : l'appli fonctionne sans serveur,
  /// avec les données « Grâce Divine ».
  Future<bool> readDemoMode() async =>
      (await _storage.read(key: _demoKey)) != 'false';

  Future<void> saveDemoMode(bool value) =>
      _storage.write(key: _demoKey, value: value.toString());

  Future<String> readApiUrl() async =>
      (await _storage.read(key: _apiUrlKey)) ?? AppConfig.defaultApiBaseUrl;

  Future<void> saveApiUrl(String url) =>
      _storage.write(key: _apiUrlKey, value: url);
}
