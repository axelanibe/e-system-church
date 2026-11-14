import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/abonnement.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../models/fidele.dart';
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

  /// Jeton de rafraîchissement (un par appareil) : la session dure
  /// jusqu'à déconnexion manuelle.
  String? _refreshToken;
  AppUser? _user;
  Church? _church;
  String? _role;
  List<Membership> _eglises = [];

  /// Abonnement de l'église active, chargé après connexion (T13, D04).
  /// Null tant qu'il n'a pas été chargé : la lecture seule n'est alors
  /// jamais supposée.
  Abonnement? _abonnement;
  Abonnement? get abonnement => _abonnement;

  /// Vrai quand l'abonnement est expiré et la grâce de 30 jours passée :
  /// l'application passe en lecture seule (consultation possible,
  /// écritures bloquées). Faux par défaut, jamais supposé.
  bool get lectureSeule => _abonnement?.lectureSeule ?? false;

  // Tous les modules sont affichés pour toutes les églises (règle
  // du 11/11/2026) : plus de chargement ni de filtre par module.
  bool get initialized => _initialized;
  String get apiBaseUrl => _apiBaseUrl;
  ApiService get api => _api;

  bool get isLoggedIn => _token != null && _church != null;
  AppUser? get user => _user;
  Church? get church => _church;
  String? get role => _role;
  List<Membership> get eglises => List.unmodifiable(_eglises);

  /// Devise de l'église active (« FCFA » par défaut).
  String get devise => _church?.devise ?? 'FCFA';

  /// L'utilisateur peut gérer les membres (création comprise).
  /// Jamais en lecture seule (abonnement expiré) : les FAB « Ajouter »
  /// et « Nouveau membre » disparaissent alors d'eux-mêmes, partout où
  /// ils sont déjà conditionnés à ce droit (T13, D04).
  bool get canManageMembers =>
      !lectureSeule &&
      (_role == 'admin_eglise' || _role == 'responsable_culte');

  /// L'utilisateur peut voir et saisir les finances.
  /// Jamais en lecture seule (T13, D04).
  bool get canManageFinances =>
      !lectureSeule && (_role == 'admin_eglise' || _role == 'tresorier');

  /// L'utilisateur peut lire les finances.
  bool get canReadFinances =>
      _role == 'admin_eglise' ||
      _role == 'tresorier' ||
      _role == 'responsable_culte';

  /// L'utilisateur est un fidèle (rôle `membre`) : accueil fidèle, sans
  /// les écrans d'administration.
  bool get isMembre => _role == 'membre';

  /// Aperçu de l'espace fidèle par un administrateur (« Voir l'espace
  /// fidèle » sur l'accueil admin, tranche P1) : la coquille fidèle
  /// s'affiche sans changer de session ni de rôle. Les lectures
  /// réservées au rôle `membre` ne sont pas appelées en aperçu, les
  /// sections montrent leurs états vides. « Voir l'espace admin »
  /// dans le menu Plus du fidèle quitte l'aperçu.
  bool _apercuFidele = false;
  bool get apercuFidele => _apercuFidele;

  void entrerApercuFidele() {
    _apercuFidele = true;
    notifyListeners();
  }

  void sortirApercuFidele() {
    _apercuFidele = false;
    notifyListeners();
  }

  /// L'utilisateur est admin de son église.
  bool get isAdmin => _role == 'admin_eglise';

  /// L'utilisateur est admin de la plateforme (chiffres globaux seulement).
  bool get isSuperAdmin => _role == 'super_admin';

  /// L'utilisateur est aide Plateforme : droits limités choisis par Axel.
  bool get isAidePlateforme => _role == 'aide_plateforme';

  /// L'utilisateur est connecté à la Plateforme (admin ou aide) : sa
  /// session ouvre directement l'écran Plateforme, jamais une église.
  bool get isPlateforme => isSuperAdmin || isAidePlateforme;

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
      case 'aide_plateforme':
        return 'Aide Plateforme';
      default:
        return _role ?? '—';
    }
  }

  ApiService _buildApi() {
    final api = HttpApiService(
      baseUrl: _apiBaseUrl,
      token: _token,
      refreshToken: _refreshToken,
    );
    // Rotation réussie (reprise sur 401 ou changement d'église) : les
    // deux jetons sont persistés tout de suite.
    api.onTokensRefreshed = (token, refreshToken) async {
      _token = token;
      _refreshToken = refreshToken;
      await _store.saveToken(token);
      if (refreshToken != null) {
        await _store.saveRefreshToken(refreshToken);
      }
    };
    return api;
  }

  /// Chargement initial : réglages persistés, puis restauration de session.
  Future<void> init() async {
    _apiBaseUrl = await _store.readApiUrl();
    _refreshToken = await _store.readRefreshToken();
    _api = _buildApi();
    final savedToken = await _store.readToken();
    if (savedToken != null) {
      // Mode API réelle : on tente de restaurer la session.
      _token = savedToken;
      (_api as HttpApiService).setToken(savedToken);
      try {
        final me = await _api.me();
        _applyMe(me);
        await _chargerAbonnement();
      } catch (_) {
        // JWT expiré : une rotation suffit, sans ressaisir le mot de passe.
        // Les jetons sont persistés par `onTokensRefreshed`.
        try {
          final refreshed = await _api.refresh();
          _applyAuth(refreshed);
          await _chargerAbonnement();
        } catch (_) {
          _token = null;
          _refreshToken = null;
          await _store.clearToken();
          await _store.clearRefreshToken();
        }
      }
    }
    _initialized = true;
    notifyListeners();
  }

  void _applyAuth(AuthResult result) {
    _token = result.token;
    _refreshToken = result.refreshToken;
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

  /// Charge l'abonnement de l'église active (T13, D04). Sans jamais
  /// faire échouer la connexion : hors ligne, rôle sans abonnement ou
  /// route indisponible laissent simplement la lecture seule à faux.
  Future<void> _chargerAbonnement() async {
    try {
      _abonnement = await _api.getMonAbonnement();
    } catch (_) {
      _abonnement = null;
    }
  }

  /// Recharge l'abonnement (après renouvellement, par exemple).
  Future<void> refreshAbonnement() async {
    await _chargerAbonnement();
    notifyListeners();
  }

  Future<void> login(
      {required String identifiant,
      required String password,
      bool plateforme = false,
      String? code2fa}) async {
    final result = await _api.login(
      identifiant: identifiant,
      password: password,
      plateforme: plateforme,
      code2fa: code2fa,
    );
    _applyAuth(result);
    await _chargerAbonnement();
    await _store.saveToken(result.token);
    if (result.refreshToken != null) {
      await _store.saveRefreshToken(result.refreshToken!);
    }
    notifyListeners();
  }

  Future<AuthResult> register({
    required String churchName,
    required String city,
    String? churchPhone,
    String? churchEmail,
    required String adminName,
    required String adminEmail,
    String? adminPhone,
    required String password,
    String? parentCode,
    String? logoBase64,
    String? logoFilename,
  }) async {
    final result = await _api.register(
      churchName: churchName,
      city: city,
      churchPhone: churchPhone,
      churchEmail: churchEmail,
      adminName: adminName,
      adminEmail: adminEmail,
      adminPhone: adminPhone,
      password: password,
      parentCode: parentCode,
      logoBase64: logoBase64,
      logoFilename: logoFilename,
    );
    _applyAuth(result);
    await _chargerAbonnement();
    await _store.saveToken(result.token);
    if (result.refreshToken != null) {
      await _store.saveRefreshToken(result.refreshToken!);
    }
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
      await _chargerAbonnement();
      await _store.saveToken(result.auth!.token);
      if (result.auth!.refreshToken != null) {
        await _store.saveRefreshToken(result.auth!.refreshToken!);
      }
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
    String? birthDate,
    String? sexe,
    String? department,
    String? fonction,
  }) async {
    final result = await _api.registerMembreParCode(
      nomPrenom: nomPrenom,
      email: email,
      telephone: telephone,
      password: password,
      codeEglise: codeEglise,
      birthDate: birthDate,
      sexe: sexe,
      department: department,
      fonction: fonction,
    );
    if (result.auth != null) {
      _applyAuth(result.auth!);
      await _chargerAbonnement();
      await _store.saveToken(result.auth!.token);
      if (result.auth!.refreshToken != null) {
        await _store.saveRefreshToken(result.auth!.refreshToken!);
      }
      notifyListeners();
    }
    return result;
  }

  /// Recharge mon église et mon rôle depuis l'API.
  Future<void> refreshMe() async {
    final me = await _api.me();
    _applyMe(me);
    await _chargerAbonnement();
    notifyListeners();
  }

  /// Bascule l'église active (sélecteur d'église) : le jeton est renouvelé
  /// par l'API, puis on recharge mon église et mon rôle.
  Future<void> switchChurch(String churchId) async {
    await _api.switchChurch(churchId);
    await refreshMe();
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {
      // Hors ligne : la déconnexion locale a lieu quand même.
    }
    _token = null;
    _refreshToken = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    _apercuFidele = false;
    _abonnement = null;
    await _store.clearToken();
    await _store.clearRefreshToken();
    notifyListeners();
  }

  /// Change l'URL de l'API. La session est fermée.
  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return;
    _apiBaseUrl = cleaned;
    await _store.saveApiUrl(cleaned);
    _token = null;
    _refreshToken = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    _apercuFidele = false;
    _abonnement = null;
    await _store.clearToken();
    await _store.clearRefreshToken();
    _api = _buildApi();
    notifyListeners();
  }
}
