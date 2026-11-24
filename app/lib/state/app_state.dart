import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  /// Stockage de session et client HTTP injectables (tests uniquement) :
  /// par défaut, le stockage sécurisé et un vrai client HTTP.
  AppState({SessionStore? store, http.Client? client})
      : _store = store ?? SessionStore(),
        _client = client;

  final SessionStore _store;
  final http.Client? _client;

  late ApiService _api;
  bool _initialized = false;

  /// Vrai quand la dernière restauration de session a échoué sans preuve
  /// de révocation (serveur injoignable, délai dépassé, erreur serveur) :
  /// les jetons stockés sont conservés, mais l'utilisateur n'est pas
  /// connecté pour cette session. Faux après une restauration réussie,
  /// une connexion, une déconnexion ou une révocation prouvée (401).
  bool _horsLigne = false;
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

  /// Vrai quand le dernier démarrage (ou réessai) n'a pas pu joindre le
  /// serveur alors qu'une session était stockée : les jetons sont
  /// conservés, mais l'utilisateur n'est pas connecté pour cette session.
  /// L'écran de connexion peut alors proposer un bouton « Réessayer »
  /// ([reessayerConnexion]) au lieu d'exiger une nouvelle connexion.
  bool get horsLigne => _horsLigne;
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

  /// Appelé au début de [logout] (et de [setApiBaseUrl]), avant la
  /// révocation de session côté serveur : le service de notifications
  /// push y retire son jeton FCM tant que l'appel reste authentifié.
  /// Un échec du crochet n'empêche jamais la déconnexion.
  Future<void> Function()? onAvantDeconnexion;

  ApiService _buildApi() {
    final api = HttpApiService(
      baseUrl: _apiBaseUrl,
      token: _token,
      refreshToken: _refreshToken,
      client: _client,
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
      await _restaurerSession();
    }
    _initialized = true;
    notifyListeners();
  }

  /// Tente de restaurer la session stockée (`/moi`, puis rotation du jeton
  /// si besoin). Renvoie vrai si la session est restaurée.
  ///
  /// Seul un 401 prouve que le serveur a révoqué la session : les jetons
  /// stockés sont alors effacés (déconnexion propre). Tout autre échec —
  /// transport (`statusCode` null, code `hors_ligne`), 5xx, réponse
  /// inattendue — conserve les jetons : la session longue durée survit
  /// au démarrage hors ligne ([horsLigne] passe à vrai) et sera réessayée
  /// au prochain démarrage ou par [reessayerConnexion]. Sans cette
  /// distinction, un simple démarrage hors ligne détruisait
  /// définitivement la session (faille basse n° 11, audit 14/11).
  Future<bool> _restaurerSession() async {
    try {
      final me = await _api.me();
      _applyMe(me);
      await _chargerAbonnement();
      _horsLigne = false;
      return true;
    } catch (_) {
      // JWT expiré : une rotation suffit, sans ressaisir le mot de passe.
      // Les jetons sont persistés par `onTokensRefreshed`.
      try {
        final refreshed = await _api.refresh();
        _applyAuth(refreshed);
        await _chargerAbonnement();
        _horsLigne = false;
        return true;
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          // Révocation prouvée par le serveur : la session est finie.
          await _effacerSessionStockee();
          _horsLigne = false;
        } else {
          // Échec de transport ou erreur serveur : sans preuve de
          // révocation, on conserve les jetons stockés.
          _horsLigne = true;
        }
        return false;
      } catch (_) {
        // Erreur inattendue (réponse illisible, ...) : sans preuve de
        // révocation, on conserve les jetons comme pour un échec de
        // transport.
        _horsLigne = true;
        return false;
      }
    }
  }

  /// Efface la session stockée (mémoire + stockage sécurisé). Appelé
  /// uniquement sur révocation prouvée (401) : jamais sur un échec de
  /// transport, qui conserve les jetons.
  Future<void> _effacerSessionStockee() async {
    _token = null;
    _refreshToken = null;
    await _store.clearToken();
    await _store.clearRefreshToken();
  }

  /// Réessaie la restauration de session après un démarrage hors ligne
  /// ([horsLigne]) : même séquence que [init], sans relire les réglages.
  /// Renvoie vrai si la session est restaurée. Sans effet (faux) quand
  /// il n'y a rien à réessayer.
  Future<bool> reessayerConnexion() async {
    if (!_horsLigne) return isLoggedIn;
    final sauve = await _store.readToken();
    if (sauve == null) {
      _horsLigne = false;
      notifyListeners();
      return false;
    }
    _token = sauve;
    (_api as HttpApiService).setToken(sauve);
    (_api as HttpApiService).setRefreshToken(_refreshToken);
    final restauree = await _restaurerSession();
    notifyListeners();
    return restauree;
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
    _horsLigne = false;
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
      await onAvantDeconnexion?.call();
    } catch (_) {
      // Le retrait du jeton push ne bloque jamais la déconnexion.
    }
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
    _abonnement = null;
    await _store.clearToken();
    await _store.clearRefreshToken();
    _horsLigne = false;
    notifyListeners();
  }

  /// Change l'URL de l'API. La session est fermée.
  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return;
    try {
      await onAvantDeconnexion?.call();
    } catch (_) {
      // Le retrait du jeton push ne bloque jamais le changement d'URL.
    }
    _apiBaseUrl = cleaned;
    await _store.saveApiUrl(cleaned);
    _token = null;
    _refreshToken = null;
    _user = null;
    _church = null;
    _role = null;
    _eglises = [];
    _abonnement = null;
    await _store.clearToken();
    await _store.clearRefreshToken();
    _horsLigne = false;
    _api = _buildApi();
    notifyListeners();
  }
}
