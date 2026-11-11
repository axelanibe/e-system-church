import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../services/api_service.dart';
import '../services/http_api_service.dart';
import '../services/mock_api_service.dart';
import '../services/session_store.dart';

/// État global de l'application : session, église active, mode démo / API.
///
/// - Mode démo (par défaut) : [MockApiService], données « Grâce Divine ».
/// - Mode API réelle : [HttpApiService] vers l'URL configurée, jeton JWT
///   persisté en stockage sécurisé.
class AppState extends ChangeNotifier {
  final SessionStore _store = SessionStore();

  late ApiService _api;
  bool _initialized = false;
  bool _demoMode = true;
  String _apiBaseUrl = AppConfig.defaultApiBaseUrl;

  String? _token;
  AppUser? _user;
  Church? _church;
  String? _role;
  List<Membership> _eglises = [];

  bool get initialized => _initialized;
  bool get demoMode => _demoMode;
  String get apiBaseUrl => _apiBaseUrl;
  ApiService get api => _api;

  bool get isLoggedIn => _token != null && _church != null;
  AppUser? get user => _user;
  Church? get church => _church;
  String? get role => _role;
  List<Membership> get eglises => List.unmodifiable(_eglises);

  /// L'utilisateur peut gérer les membres (création comprise).
  bool get canManageMembers =>
      _role == 'admin_eglise' || _role == 'responsable_culte';

  /// L'utilisateur peut voir et saisir les finances.
  bool get canManageFinances =>
      _role == 'admin_eglise' || _role == 'tresorier';

  /// L'utilisateur peut lire les finances.
  bool get canReadFinances =>
      _role == 'admin_eglise' ||
      _role == 'tresorier' ||
      _role == 'responsable_culte';

  /// L'utilisateur est admin de son église.
  bool get isAdmin => _role == 'admin_eglise';

  /// L'utilisateur est admin de la plateforme (chiffres globaux seulement).
  bool get isSuperAdmin => _role == 'super_admin';

  String get roleLabel {
    switch (_role) {
      case 'admin_eglise':
        return 'Admin d’église';
      case 'tresorier':
        return 'Trésorier';
      case 'responsable_culte':
        return 'Responsable de culte';
      case 'membre':
        return 'Membre';
      case 'super_admin':
        return 'Admin plateforme';
      default:
        return _role ?? '—';
    }
  }

  ApiService _buildApi() {
    if (_demoMode) return MockApiService();
    return HttpApiService(baseUrl: _apiBaseUrl, token: _token);
  }

  /// Chargement initial : réglages persistés, puis restauration de session.
  Future<void> init() async {
    _demoMode = await _store.readDemoMode();
    _apiBaseUrl = await _store.readApiUrl();
    _api = _buildApi();
    final savedToken = await _store.readToken();
    if (savedToken != null && !_demoMode) {
      // Mode API réelle : on tente de restaurer la session.
      _token = savedToken;
      (_api as HttpApiService).setToken(savedToken);
      try {
        final me = await _api.me();
        _applyMe(me);
      } catch (_) {
        _token = null;
        await _store.clearToken();
      }
    }
    _initialized = true;
    notifyListeners();
  }

  void _applyAuth(AuthResult result) {
    _token = result.token;
    _user = result.user;
    _church = result.church;
    _role = result.church.role;
    _eglises = result.eglises;
  }

  void _applyMe(MeResult me) {
    _user = me.user;
    _church = me.church;
    _role = me.role;
    _eglises = me.eglises;
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _api.login(email: email, password: password);
    _applyAuth(result);
    if (!_demoMode) await _store.saveToken(result.token);
    notifyListeners();
  }

  Future<AuthResult> register({
    required String churchName,
    required String city,
    String? churchPhone,
    String? churchEmail,
    required String adminName,
    required String adminEmail,
    required String password,
    String? parentCode,
  }) async {
    final result = await _api.register(
      churchName: churchName,
      city: city,
      churchPhone: churchPhone,
      churchEmail: churchEmail,
      adminName: adminName,
      adminEmail: adminEmail,
      password: password,
      parentCode: parentCode,
    );
    _applyAuth(result);
    if (!_demoMode) await _store.saveToken(result.token);
    notifyListeners();
    return result;
  }

  /// Recharge mon église et mon rôle depuis l'API.
  Future<void> refreshMe() async {
    final me = await _api.me();
    _applyMe(me);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    await _store.clearToken();
    notifyListeners();
  }

  /// Bascule mode démo / API réelle. La session est fermée (les données
  /// de démo vivent en mémoire et sont réinitialisées).
  Future<void> setDemoMode(bool value) async {
    if (value == _demoMode) return;
    _demoMode = value;
    await _store.saveDemoMode(value);
    _token = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    await _store.clearToken();
    _api = _buildApi();
    notifyListeners();
  }

  /// Change l'URL de l'API (mode API réelle). La session est fermée.
  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return;
    _apiBaseUrl = cleaned;
    await _store.saveApiUrl(cleaned);
    _token = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    await _store.clearToken();
    _api = _buildApi();
    notifyListeners();
  }
}
