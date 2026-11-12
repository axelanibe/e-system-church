// État global de la version DÉMO.
//
// Sous-classe de [AppState] qui remplace le service HTTP par
// [MockApiService] (données fictives en mémoire) et ne persiste RIEN :
// ni jeton, ni URL d'API — chaque lancement de la démo repart d'une
// session vide. Les écrans ne voient que le type [AppState] : ils
// fonctionnent tels quels, sans aucune modification.
// Utilisé uniquement par `lib/main_demo.dart`.

import '../models/auth.dart';
import '../models/church.dart';
import '../models/fidele.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import 'mock_api_service.dart';

class DemoAppState extends AppState {
  final MockApiService _demoApi = MockApiService();

  bool _demoInitialized = false;
  AppUser? _demoUser;
  Church? _demoChurch;
  String? _demoRole;
  List<Membership> _demoEglises = [];

  @override
  ApiService get api => _demoApi;

  @override
  bool get initialized => _demoInitialized;

  /// La démo n'a pas d'URL d'API : tout est local.
  @override
  String get apiBaseUrl => 'demo';

  @override
  bool get isLoggedIn => _demoUser != null && _demoChurch != null;

  @override
  AppUser? get user => _demoUser;

  @override
  Church? get church => _demoChurch;

  @override
  String? get role => _demoRole;

  @override
  List<Membership> get eglises => List.unmodifiable(_demoEglises);

  @override
  String get devise => _demoChurch?.devise ?? 'FCFA';

  @override
  bool get canManageMembers =>
      _demoRole == 'admin_eglise' || _demoRole == 'responsable_culte';

  @override
  bool get canManageFinances =>
      _demoRole == 'admin_eglise' || _demoRole == 'tresorier';

  @override
  bool get canReadFinances =>
      _demoRole == 'admin_eglise' ||
      _demoRole == 'tresorier' ||
      _demoRole == 'responsable_culte';

  @override
  bool get isMembre => _demoRole == 'membre';

  @override
  bool get isAdmin => _demoRole == 'admin_eglise';

  @override
  bool get isSuperAdmin => _demoRole == 'super_admin';

  @override
  String get roleLabel {
    switch (_demoRole) {
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
        return _demoRole ?? '—';
    }
  }

  /// Chargement initial de la démo : aucune session à restaurer, aucune
  /// lecture du stockage — la démo démarre toujours déconnectée.
  @override
  Future<void> init() async {
    _demoInitialized = true;
    notifyListeners();
  }

  void _applyAuth(AuthResult result) {
    _demoUser = result.user;
    _demoChurch = result.church;
    _demoRole = result.church.role;
    _demoEglises = result.eglises;
  }

  void _applyMe(MeResult me) {
    _demoUser = me.user;
    _demoChurch = me.church;
    _demoRole = me.role;
    _demoEglises = me.eglises;
  }

  @override
  Future<void> login(
      {required String identifiant, required String password}) async {
    final result =
        await _demoApi.login(identifiant: identifiant, password: password);
    _applyAuth(result);
    notifyListeners();
  }

  @override
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
    final result = await _demoApi.register(
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
    notifyListeners();
    return result;
  }

  @override
  Future<FideleInscriptionResult> registerFidele({
    required String email,
    required String password,
    required String matricule,
  }) async {
    final result = await _demoApi.registerFidele(
      email: email,
      password: password,
      matricule: matricule,
    );
    if (result.auth != null) {
      _applyAuth(result.auth!);
      notifyListeners();
    }
    return result;
  }

  @override
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
    final result = await _demoApi.registerMembreParCode(
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
      notifyListeners();
    }
    return result;
  }

  @override
  Future<void> refreshMe() async {
    final me = await _demoApi.me();
    _applyMe(me);
    notifyListeners();
  }

  @override
  Future<void> switchChurch(String churchId) async {
    await _demoApi.switchChurch(churchId);
    await refreshMe();
  }

  @override
  Future<void> logout() async {
    await _demoApi.logout();
    _demoUser = null;
    _demoChurch = null;
    _demoRole = null;
    _demoEglises = [];
    notifyListeners();
  }

  /// Sans effet en démo : il n'y a pas d'URL d'API à changer.
  @override
  Future<void> setApiBaseUrl(String url) async {}
}
