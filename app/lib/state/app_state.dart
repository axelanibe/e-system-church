import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../models/fidele.dart';
import '../models/module_eglise.dart';
import '../services/api_service.dart';
import '../services/http_api_service.dart';
import '../services/session_store.dart';

/// État global de l'application : session et église active.
///
/// Mode API réelle uniquement : [HttpApiService] vers l'URL configurée,
/// jeton JWT persisté en stockage sécurisé. Aucune donnée de démonstration :
/// tout vient de l'API, les listes vides restent vides.
class AppState extends ChangeNotifier {
  final SessionStore _store = SessionStore();

  late ApiService _api;
  bool _initialized = false;
  String _apiBaseUrl = AppConfig.defaultApiBaseUrl;

  String? _token;
  AppUser? _user;
  Church? _church;
  String? _role;
  List<Membership> _eglises = [];

  /// Modules de l'église active (US1). Vide tant qu'ils ne sont pas chargés :
  /// [isModuleActif] ouvre alors tout, le serveur restant l'autorité.
  List<ModuleEglise> _modules = [];

  bool get initialized => _initialized;
  String get apiBaseUrl => _apiBaseUrl;
  ApiService get api => _api;

  List<ModuleEglise> get modules => List.unmodifiable(_modules);

  /// Vrai si le module est actif pour l'église active (le noyau l'est
  /// toujours ; un code inconnu est ouvert, le serveur reste l'autorité).
  bool isModuleActif(String code) {
    if (CodesModules.noyau.contains(code)) return true;
    if (_modules.isEmpty) return true;
    for (final module in _modules) {
      if (module.code == code) return module.actif;
    }
    return true;
  }

  /// Recharge les modules de l'église active. Silencieux en cas d'échec :
  /// l'affichage reste ouvert, le serveur bloque les appels interdits.
  Future<void> refreshModules() async {
    if (_token == null || _church == null) return;
    try {
      _modules = await api.getModules();
      notifyListeners();
    } catch (_) {
      // Modules non chargés : isModuleActif ouvre tout par défaut.
    }
  }

  bool get isLoggedIn => _token != null && _church != null;
  AppUser? get user => _user;
  Church? get church => _church;
  String? get role => _role;
  List<Membership> get eglises => List.unmodifiable(_eglises);

  /// Devise de l'église active (« FCFA » par défaut).
  String get devise => _church?.devise ?? 'FCFA';

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

  /// L'utilisateur est un fidèle (rôle `membre`) : accueil fidèle, sans
  /// les écrans d'administration.
  bool get isMembre => _role == 'membre';

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

  ApiService _buildApi() => HttpApiService(baseUrl: _apiBaseUrl, token: _token);

  /// Chargement initial : réglages persistés, puis restauration de session.
  Future<void> init() async {
    _apiBaseUrl = await _store.readApiUrl();
    _api = _buildApi();
    final savedToken = await _store.readToken();
    if (savedToken != null) {
      // Mode API réelle : on tente de restaurer la session.
      _token = savedToken;
      (_api as HttpApiService).setToken(savedToken);
      try {
        final me = await _api.me();
        _applyMe(me);
        await refreshModules();
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
    await _store.saveToken(result.token);
    await refreshModules();
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
    await _store.saveToken(result.token);
    await refreshModules();
    notifyListeners();
    return result;
  }

  /// Inscription fidèle par matricule : si la liaison est immédiate,
  /// la session est appliquée (connexion) ; sinon, le résultat porte le
  /// message « demande envoyée » et l'écran l'affiche.
  Future<FideleInscriptionResult> registerFidele({
    required String email,
    required String password,
    required String matricule,
  }) async {
    final result = await _api.registerFidele(
      email: email,
      password: password,
      matricule: matricule,
    );
    if (result.auth != null) {
      _applyAuth(result.auth!);
      await _store.saveToken(result.auth!.token);
      await refreshModules();
      notifyListeners();
    }
    return result;
  }

  /// Inscription membre par code d'église, sans validation : le code fait
  /// foi, le matricule est attribué automatiquement, la session est
  /// appliquée tout de suite (connexion).
  Future<FideleInscriptionResult> registerMembreParCode({
    required String nomPrenom,
    required String email,
    required String telephone,
    required String password,
    required String codeEglise,
  }) async {
    final result = await _api.registerMembreParCode(
      nomPrenom: nomPrenom,
      email: email,
      telephone: telephone,
      password: password,
      codeEglise: codeEglise,
    );
    if (result.auth != null) {
      _applyAuth(result.auth!);
      await _store.saveToken(result.auth!.token);
      await refreshModules();
      notifyListeners();
    }
    return result;
  }

  /// Recharge mon église et mon rôle depuis l'API.
  Future<void> refreshMe() async {
    final me = await _api.me();
    _applyMe(me);
    await refreshModules();
    notifyListeners();
  }

  /// Bascule l'église active (sélecteur d'église) : le jeton est renouvelé
  /// par l'API, puis on recharge mon église et mon rôle.
  Future<void> switchChurch(String churchId) async {
    await _api.switchChurch(churchId);
    await refreshMe();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    _modules = [];
    await _store.clearToken();
    notifyListeners();
  }

  /// Change l'URL de l'API. La session est fermée.
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
