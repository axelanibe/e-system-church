// Service API factice — DÉMO UNIQUEMENT.
//
// Implémente la même interface que le vrai [ApiService] (`lib/services/`)
// mais ne fait AUCUN appel réseau : tout est en mémoire, sur les données
// fictives de `mock_data.dart` (réseau « Grâce Divine »).
// Utilisé uniquement par `lib/main_demo.dart` via `DemoAppState`.
// L'application réelle (`lib/main.dart`) n'importe jamais ce fichier.

import 'dart:typed_data';

import '../models/attestation.dart';
import '../models/annexe.dart';
import '../models/anniversaire.dart';
import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/biens.dart';
import '../models/church.dart';
import '../models/code_tutelle.dart';
import '../models/campagne.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/checkin_enfant.dart';
import '../models/enfants.dart';
import '../models/fidele.dart';
import '../models/finances.dart';
import '../models/frequentation.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../models/nettoyage_test.dart';
import '../models/paiements.dart';
import '../models/parametres.dart';
import '../models/pastoral.dart';
import '../models/plateforme.dart';
import '../models/presences.dart';
import '../models/prieres.dart';
import '../models/profil.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';
import '../models/serviteurs.dart';
import '../models/stats.dart';
import '../models/transfert.dart';
import '../services/api_service.dart';
import 'mock_data.dart';

class MockApiService implements ApiService {
  final DemoSeed _data = DemoSeed();

  /// Église de chaque élément du seed ou créé en démo, par identifiant.
  /// Tout le seed appartient à Plateau ; chaque création est rattachée à
  /// l'église active au moment de sa création. Sert le filtre d'isolation :
  /// une église ne voit que ses propres données (une nouvelle église voit
  /// donc toutes ses listes vides).
  final Map<String, String> _itemChurch = {};

  MockApiService() {
    _tagSeed();
  }

  void _tagSeed() {
    void tag<T>(List<T> list, String Function(T) idOf) {
      for (final item in list) {
        _itemChurch[idOf(item)] = DemoIds.plateau;
      }
    }

    tag(_data.cultes, (c) => c.id);
    tag(_data.culteTypes, (t) => t.id);
    tag(_data.ordreCulte, (o) => o.id);
    tag(_data.evenements, (e) => e.id);
    tag(_data.presences, (p) => p.id);
    tag(_data.annonces, (a) => a.id);
    tag(_data.familles, (f) => f.id);
    tag(_data.departements, (d) => d.id);
    tag(_data.cellules, (c) => c.id);
    tag(_data.baptemes, (b) => b.id);
    tag(_data.liens, (l) => l.id);
    tag(_data.statuts, (s) => s.id);
    tag(_data.postes, (p) => p.id);
    tag(_data.budgets, (b) => b.id);
    tag(_data.depenses, (d) => d.id);
    tag(_data.caisseMouvements, (m) => m.id);
    tag(_data.prieres, (p) => p.id);
    tag(_data.messages, (m) => m.id);
    tag(_data.parcours, (p) => p.id);
    tag(_data.visites, (v) => v.id);
    tag(_data.accompagnements, (a) => a.id);
    tag(_data.serviteurs, (s) => s.id);
    tag(_data.planning, (p) => p.id);
    tag(_data.classesEnfants, (c) => c.id);
    tag(_data.autorisations, (a) => a.id);
    tag(_data.activitesJeunesse, (a) => a.id);
    tag(_data.predications, (p) => p.id);
    tag(_data.plansLecture, (p) => p.id);
    tag(_data.livres, (l) => l.id);
    tag(_data.pretsLivres, (p) => p.id);
    tag(_data.salles, (s) => s.id);
    tag(_data.reservationsSalles, (r) => r.id);
    tag(_data.materiel, (m) => m.id);
    tag(_data.maintenances, (m) => m.id);
    tag(_data.roles, (r) => r.userId);
    tag(_data.audit, (a) => a.id);
    tag(_data.paiements, (p) => p.id);
    tag(_data.demandesLiaison, (d) => d.id);
    // Chaque antenne du réseau a ses propres copies des types de culte,
    // sinon elle ne pourrait pas créer de culte.
    for (final id in [
      DemoIds.yopougon,
      DemoIds.bouake,
      DemoIds.yamoussoukro,
      DemoIds.sanPedro,
    ]) {
      _dupliquerTypesCultes(id);
    }
  }

  /// Copie les types de culte du seed pour une église (nouvelle église ou
  /// antenne) : sans type, la création de culte serait impossible.
  void _dupliquerTypesCultes(String churchId) {
    for (final type in _data.culteTypes
        .where((t) => _itemChurch[t.id] == DemoIds.plateau)
        .toList()) {
      final copie = CulteType(
        id: _nextId('type'),
        nom: type.nom,
        heureDebut: type.heureDebut,
        lieu: type.lieu,
      );
      _data.culteTypes.add(copie);
      _tag(copie.id);
      _tagPour(churchId, copie.id);
    }
  }

  /// Rattache un élément créé à l'église active.
  void _tag(String id) {
    _itemChurch[id] = _churchId;
  }

  /// Rattache un élément créé à une église donnée (inscription, transfert).
  void _tagPour(String churchId, String id) {
    _itemChurch[id] = churchId;
  }

  /// Éléments visibles pour une église donnée. Un élément sans rattachement
  /// (oubli) n'est visible que depuis Plateau, l'église du seed — jamais
  /// depuis une autre église (isolation stricte).
  List<T> _visiblePour<T>(
      List<T> list, String Function(T) idOf, String churchId) {
    return list
        .where((e) =>
            _itemChurch[idOf(e)] == churchId ||
            (_itemChurch[idOf(e)] == null && churchId == DemoIds.plateau))
        .toList();
  }

  /// Éléments visibles pour l'église active.
  List<T> _visible<T>(List<T> list, String Function(T) idOf) =>
      _visiblePour(list, idOf, _churchId);

  /// Dépenses du module Budget & caisse d'une église, hors refusées,
  /// éventuellement sur une période [debut, fin[ (dates « AAAA-MM-JJ »).
  int _depensesBudget(String churchId, {String? debut, String? fin}) {
    return _visiblePour(_data.depenses, (d) => d.id, churchId)
        .where((d) =>
            d.statut != 'refusee' &&
            (debut == null ||
                (d.dateDepense != null &&
                    d.dateDepense!.compareTo(debut) >= 0)) &&
            (fin == null ||
                (d.dateDepense != null && d.dateDepense!.compareTo(fin) < 0)))
        .fold<int>(0, (s, d) => s + d.montantFcfa);
  }

  /// Nombre de dépenses du module Budget & caisse (même périmètre).
  int _nombreDepensesBudget(String churchId, {String? debut, String? fin}) {
    return _visiblePour(_data.depenses, (d) => d.id, churchId)
        .where((d) =>
            d.statut != 'refusee' &&
            (debut == null ||
                (d.dateDepense != null &&
                    d.dateDepense!.compareTo(debut) >= 0)) &&
            (fin == null ||
                (d.dateDepense != null && d.dateDepense!.compareTo(fin) < 0)))
        .length;
  }

  /// « Dépenses confirmées » : contributions de type dépense + dépenses du
  /// module Budget & caisse (hors refusées). Sans ça, le tableau de bord
  /// affichait 0 alors que Budget & caisse contenait des dépenses.
  int _depensesConfirmees(String churchId, {String? debut, String? fin}) {
    final contributions = _confirmedOf(churchId)
        .where((c) => c.type == 'depense')
        .where((c) =>
            debut == null ||
            (c.createdAt != null &&
                c.createdAt!
                        .toIso8601String()
                        .substring(0, 10)
                        .compareTo(debut) >=
                    0))
        .where((c) =>
            fin == null ||
            (c.createdAt != null &&
                c.createdAt!
                        .toIso8601String()
                        .substring(0, 10)
                        .compareTo(fin) <
                    0))
        .fold<int>(0, (s, c) => s + c.amountFcfa);
    return contributions + _depensesBudget(churchId, debut: debut, fin: fin);
  }

  String _churchId = DemoIds.plateau;
  AppUser? _user;
  String? _role;
  List<Membership> _eglises = [];
  String _adminPassword = DemoAccounts.password;
  String _membrePassword = DemoAccounts.password;
  int _seq = 1000;

  Future<void> _latence() =>
      Future.delayed(const Duration(milliseconds: 120));

  String _nextId(String prefix) => 'demo-$prefix-${_seq++}';

  Church get _church {
    final eglise = _data.churchById(_churchId) ?? _data.plateau;
    return _withRole(eglise, _role ?? 'admin_eglise');
  }

  Church _withRole(Church eglise, String role) => Church(
        id: eglise.id,
        code: eglise.code,
        name: eglise.name,
        parentChurchId: eglise.parentChurchId,
        city: eglise.city,
        status: eglise.status,
        role: role,
        logoUrl: eglise.logoUrl,
        couleurPrincipale: eglise.couleurPrincipale,
        devise: eglise.devise,
        fuseauHoraire: eglise.fuseauHoraire,
        description: eglise.description,
        horairesCultes: eglise.horairesCultes,
      );

  void _requireAuth() {
    if (_user == null) throw const ApiException('Non connecté (démo).');
  }

  AuthResult _buildAuth(AppUser user, Church church, String role) {
    final memberships = _eglises.isEmpty
        ? [Membership(church: _withRole(church, role), role: role)]
        : _eglises;
    return AuthResult(
      token: 'demo-token-${user.id}',
      user: user,
      church: _withRole(church, role),
      eglises: memberships,
    );
  }

  void _applyAuth(AuthResult result) {
    _user = result.user;
    _role = result.church.role;
    _churchId = result.church.id;
    _eglises = result.eglises;
  }

  Member? _findMember(String id) {
    for (final list in _data.membersByChurch.values) {
      for (final m in list) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  Member? _findMemberByMatricule(String matricule, {String? churchId}) {
    final lists = churchId == null
        ? _data.membersByChurch.values
        : [_data.membersOf(churchId)];
    for (final list in lists) {
      for (final m in list) {
        if (m.matricule == matricule) return m;
      }
    }
    return null;
  }

  List<Contribution> _confirmedOf(String churchId) => _data
      .contributionsOf(churchId)
      .where((c) => c.status == 'confirme')
      .toList();

  RapportChiffres _chiffres(String churchId) {
    final membres =
        _data.membersOf(churchId).where((m) => m.status != 'inactif').length;
    final contributions = _confirmedOf(churchId);
    return RapportChiffres(
      membresActifs: membres,
      nombreContributions: contributions.length,
      totalFcfa: contributions.fold<int>(
          0, (sum, c) => sum + (c.type == 'depense' ? 0 : c.amountFcfa)),
    );
  }

  Map<String, ContributionTotals> _totaux(List<Contribution> list,
      {int depensesBudget = 0, int nombreDepensesBudget = 0}) {
    final map = <String, ContributionTotals>{};
    for (final c in list) {
      if (c.status != 'confirme') continue;
      final precedent = map[c.type];
      map[c.type] = ContributionTotals(
        totalFcfa: (precedent?.totalFcfa ?? 0) + c.amountFcfa,
        nombre: (precedent?.nombre ?? 0) + 1,
      );
    }
    // Les dépenses du module Budget & caisse comptent dans « Dépenses
    // confirmées », sinon le tableau de bord affichait 0 alors que Budget &
    // caisse contenait des dépenses.
    if (depensesBudget > 0 || nombreDepensesBudget > 0) {
      final precedent = map['depense'];
      map['depense'] = ContributionTotals(
        totalFcfa: (precedent?.totalFcfa ?? 0) + depensesBudget,
        nombre: (precedent?.nombre ?? 0) + nombreDepensesBudget,
      );
    }
    return map;
  }

  /// Bornes [debut, fin[ et libellé d'une période (mois, trimestre, année),
  /// ancrée sur le mois « AAAA-MM » (mois courant par défaut).
  ({String debut, String fin, String label}) _bornesPeriode(
      String periode, String moisAncre) {
    final annee = int.parse(moisAncre.substring(0, 4));
    final mois = int.parse(moisAncre.substring(5, 7));
    const noms = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];
    String iso(int a, int m) => '$a-${m.toString().padLeft(2, '0')}-01';
    if (periode == 'annee') {
      return (
        debut: iso(annee, 1),
        fin: iso(annee + 1, 1),
        label: 'Année $annee'
      );
    }
    if (periode == 'trimestre') {
      final trimestre = (mois - 1) ~/ 3 + 1;
      final debutMois = (trimestre - 1) * 3 + 1;
      final finMois = debutMois + 3;
      final finA = finMois > 12 ? annee + 1 : annee;
      final finM = finMois > 12 ? finMois - 12 : finMois;
      return (
        debut: iso(annee, debutMois),
        fin: iso(finA, finM),
        label: '$trimestre${trimestre == 1 ? 'er' : 'e'} trimestre $annee'
      );
    }
    final finMois = mois + 1;
    final finA = finMois > 12 ? annee + 1 : annee;
    final finM = finMois > 12 ? 1 : finMois;
    final nom = noms[mois - 1];
    return (
      debut: iso(annee, mois),
      fin: iso(finA, finM),
      label: '${nom[0].toUpperCase()}${nom.substring(1)} $annee'
    );
  }

  /// Vrai si [date] tombe dans [debut, fin[ (dates « AAAA-MM-JJ »).
  bool _dansPeriode(DateTime? date, String debut, String fin) {
    if (date == null) return false;
    final jour = date.toIso8601String().substring(0, 10);
    return jour.compareTo(debut) >= 0 && jour.compareTo(fin) < 0;
  }

  /// Memberships de l'admin démo sur tout le réseau (mère + antennes).
  List<Membership> _reseauMemberships(String role) {
    return [
      DemoIds.plateau,
      DemoIds.yopougon,
      DemoIds.bouake,
      DemoIds.yamoussoukro,
      DemoIds.sanPedro,
    ]
        .map((id) => Membership(
              church: _withRole(_data.churchById(id)!, role),
              role: role,
            ))
        .toList();
  }

  // -- Authentification -----------------------------------------------------

  /// Normalisation démo, même règle que le serveur : espaces, tirets,
  /// points et parenthèses retirés, 0… → +225…, 225… → +225….
  String? _normaliserTelephone(String v) {
    final nettoye = v.replaceAll(RegExp(r'[\s\-.()]'), '');
    if (nettoye.startsWith('+')) {
      if (RegExp(r'^\+2250[0-9]{7,9}$').hasMatch(nettoye)) {
        return '+225${nettoye.substring(5)}';
      }
      return RegExp(r'^\+[0-9]{8,15}$').hasMatch(nettoye) ? nettoye : null;
    }
    if (RegExp(r'^0[0-9]{7,9}$').hasMatch(nettoye)) {
      return '+225${nettoye.substring(1)}';
    }
    if (RegExp(r'^2250[0-9]{7,9}$').hasMatch(nettoye)) {
      return '+225${nettoye.substring(4)}';
    }
    if (RegExp(r'^225[0-9]{7,9}$').hasMatch(nettoye)) {
      return '+$nettoye';
    }
    return null;
  }

  @override
  Future<AuthResult> login(
      {required String identifiant, required String password}) async {
    await _latence();
    final idBrut = identifiant.trim();
    final mail = idBrut.toLowerCase();
    final tel =
        idBrut.contains('@') ? null : _normaliserTelephone(idBrut);
    if ((mail == DemoAccounts.adminEmail || tel == '+2257470001') &&
        password == _adminPassword) {
      const user = AppUser(
        id: 'demo-user-admin',
        fullName: 'Admin Grâce Divine',
        email: DemoAccounts.adminEmail,
        phone: '+225 07 47 00 01',
      );
      final church = _data.plateau;
      // L'admin démo administre tout le réseau : le sélecteur « Mes églises »
      // permet de basculer vers chaque antenne (et donc de décider un
      // transfert côté arrivée, ce qui était impossible avant).
      _eglises = _reseauMemberships('admin_eglise');
      final result = _buildAuth(user, church, 'admin_eglise');
      _applyAuth(result);
      return result;
    }
    if ((mail == DemoAccounts.plateformeEmail || tel == '+2257470002') &&
        password == _adminPassword) {
      const user = AppUser(
        id: 'demo-user-plateforme',
        fullName: 'Plateforme e-System Church',
        email: DemoAccounts.plateformeEmail,
        phone: '+225 07 47 00 02',
      );
      final church = _data.plateau;
      _eglises = _reseauMemberships('super_admin');
      final result = _buildAuth(user, church, 'super_admin');
      _applyAuth(result);
      return result;
    }
    if ((mail == DemoAccounts.membreEmail || tel == '+225747123401') &&
        password == _membrePassword) {
      const user = AppUser(
        id: 'demo-user-membre',
        fullName: 'Awa Koné',
        email: DemoAccounts.membreEmail,
        phone: '+225 07 47 12 34 01',
      );
      final church = _data.plateau;
      _eglises = [Membership(church: _withRole(church, 'membre'), role: 'membre')];
      final result = _buildAuth(user, church, 'membre');
      _applyAuth(result);
      return result;
    }
    throw const ApiException(
        'Identifiant ou mot de passe incorrect (démo). Utilisez « Entrer dans la démo ».');
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
    await _latence();
    Church? parent;
    if (parentCode != null && parentCode.isNotEmpty) {
      parent = _data.churchByCode(parentCode.trim().toUpperCase());
      if (parent == null) {
        throw const ApiException('Code d’église mère introuvable (démo).');
      }
    }
    final base = city
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '')
        .padRight(3, 'X')
        .substring(0, 3);
    var code = 'GD-$base';
    var n = 2;
    while (_data.churchByCode(code) != null) {
      code = 'GD-$base$n';
      n++;
    }
    final eglise = Church(
      id: _nextId('eglise'),
      code: code,
      name: churchName,
      parentChurchId: parent?.id,
      city: city,
      status: 'active',
      devise: 'FCFA',
      fuseauHoraire: 'Africa/Abidjan',
    );
    _data.churches.add(eglise);
    _data.membersByChurch[eglise.id] = [];
    _data.contributionsByChurch[eglise.id] = [];
    // Une nouvelle église démarre avec des types de culte par défaut et des
    // paramètres vides à son nom — sinon elle ne pourrait pas créer de culte
    // et verrait les paramètres de Plateau.
    _dupliquerTypesCultes(eglise.id);
    _data.parametresByChurch[eglise.id] = EgliseParametres(
      egliseNom: churchName,
      egliseCode: code,
      ville: city,
      telephone: churchPhone,
      email: churchEmail,
      devise: 'FCFA',
      fuseauHoraire: 'Africa/Abidjan',
    );
    final user = AppUser(
      id: _nextId('user'),
      fullName: adminName,
      email: adminEmail,
      phone: adminPhone ?? churchPhone,
    );
    _eglises = [
      Membership(church: _withRole(eglise, 'admin_eglise'), role: 'admin_eglise')
    ];
    final result = _buildAuth(user, eglise, 'admin_eglise');
    _applyAuth(result);
    return result;
  }

  @override
  Future<MeResult> me() async {
    await _latence();
    _requireAuth();
    return MeResult(
      user: _user!,
      church: _church,
      role: _role!,
      eglises: _eglises,
    );
  }

  // -- Mot de passe et accès fidèle ------------------------------------------

  @override
  Future<bool> forgotPassword({required String email}) async {
    await _latence();
    // En démo, aucun e-mail n'est envoyé : on simule l'envoi.
    return true;
  }

  @override
  Future<void> resetPassword(
      {required String token, required String password}) async {
    await _latence();
    if (token.isEmpty) throw const ApiException('Lien invalide (démo).');
    _adminPassword = password;
  }

  @override
  Future<void> initPassword(
      {required String token, required String password}) async {
    await _latence();
    if (token.isEmpty) throw const ApiException('Lien invalide (démo).');
    _membrePassword = password;
  }

  @override
  Future<void> changePassword(
      {required String ancien, required String nouveau}) async {
    await _latence();
    _requireAuth();
    final actuel =
        _role == 'membre' ? _membrePassword : _adminPassword;
    if (ancien != actuel) {
      throw const ApiException('Ancien mot de passe incorrect (démo).');
    }
    if (_role == 'membre') {
      _membrePassword = nouveau;
    } else {
      _adminPassword = nouveau;
    }
  }

  @override
  Future<String> inviter({
    required String email,
    required String role,
    String? memberId,
    String? fullName,
  }) async {
    await _latence();
    _requireAuth();
    return 'https://demo.esystem-church.local/invitation/${_nextId('inv')}';
  }

  @override
  Future<String> adminResetLink({required String email}) async {
    await _latence();
    _requireAuth();
    return 'https://demo.esystem-church.local/reinitialiser/${_nextId('rst')}';
  }

  @override
  Future<FideleInscriptionResult> registerFidele({
    required String email,
    required String password,
    required String matricule,
    // Démo : une seule église, le code fidèle est sans effet ici.
    String? codeFidele,
  }) async {
    await _latence();
    final membre = _findMemberByMatricule(matricule.trim().toUpperCase());
    if (membre == null) {
      throw const ApiException('Matricule introuvable (démo).');
    }
    if (membre.email != null &&
        membre.email!.toLowerCase() == email.trim().toLowerCase()) {
      final user = AppUser(
        id: _nextId('user'),
        fullName: membre.fullName,
        email: email.trim(),
        phone: membre.phone,
      );
      final eglise = _data.plateau;
      _eglises = [Membership(church: _withRole(eglise, 'membre'), role: 'membre')];
      final auth = _buildAuth(user, eglise, 'membre');
      _applyAuth(auth);
      return FideleInscriptionResult(
        lie: true,
        auth: auth,
        message: 'Compte lié à ${membre.fullName} (${membre.matricule}).',
      );
    }
    final demande = DemandeLiaison(
      id: _nextId('dem'),
      status: 'en_attente',
      memberId: membre.id,
      matricule: membre.matricule,
      membreNom: membre.fullName,
      membreEmail: membre.email,
      userId: _nextId('user'),
      userEmail: email.trim(),
      userNom: membre.fullName,
      createdAt: DateTime.now(),
    );
    _data.demandesLiaison.add(demande);
    _tag(demande.id);
    return const FideleInscriptionResult(
      lie: false,
      message:
          'Demande de liaison envoyée : un responsable doit la valider (démo).',
    );
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
    await _latence();
    final eglise = _data.plateau;
    if (codeEglise.trim().toUpperCase() != eglise.code.toUpperCase()) {
      throw const ApiException('Code d\u2019église invalide (démo).');
    }
    final membres = _data.membersOf(eglise.id);
    if (membres.any(
        (m) => m.email?.toLowerCase() == email.trim().toLowerCase())) {
      throw const ApiException('Cet e-mail est déjà utilisé (démo).');
    }
    final prefix = DemoSeed.matriculePrefix(eglise.id);
    final matricule =
        '$prefix-${(membres.length + 1).toString().padLeft(3, '0')}';
    final membre = Member(
      id: _nextId('membre'),
      matricule: matricule,
      fullName: nomPrenom.trim(),
      phone: telephone.trim(),
      email: email.trim().toLowerCase(),
      birthDate: birthDate,
      sexe: sexe,
      department: department,
      fonction: fonction == 'Aucun' ? null : fonction,
      status: 'actif',
      createdAt: DateTime.now(),
    );
    membres.add(membre);
    final user = AppUser(
      id: _nextId('user'),
      fullName: nomPrenom.trim(),
      email: email.trim(),
      phone: telephone.trim(),
    );
    _eglises = [Membership(church: _withRole(eglise, 'membre'), role: 'membre')];
    final auth = _buildAuth(user, eglise, 'membre');
    _applyAuth(auth);
    return FideleInscriptionResult(
      lie: true,
      auth: auth,
      matricule: matricule,
      message: 'Compte créé, votre matricule est $matricule.',
    );
  }

  @override
  Future<FideleProfil> getMoi() async {
    await _latence();
    _requireAuth();
    final isMembre = _role == 'membre';
    return FideleProfil(
      user: _user!,
      church: _church,
      role: _role!,
      memberId: isMembre ? 'demo-m-001' : null,
      matricule: isMembre ? DemoAccounts.membreMatricule : null,
    );
  }

  @override
  Future<List<DemandeLiaison>> getDemandesLiaison() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.demandesLiaison
        .where((d) => d.status == 'en_attente').toList(), (e) => e.id));
  }

  @override
  Future<void> decideDemandeLiaison(String id, {required bool accept}) async {
    await _latence();
    _requireAuth();
    _data.demandesLiaison
        .removeWhere((d) => d.id == id);
  }

  // -- Lectures fidèle -------------------------------------------------------

  @override
  Future<List<Announcement>> getMesAnnonces() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.annonces, (e) => e.id));
  }

  @override
  Future<int> getAnnoncesNonLues() async => 0;

  @override
  Future<void> marquerAnnonceLue(String id) async {}

  @override
  Future<List<Culte>> getMesCultes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.cultes, (e) => e.id));
  }

  @override
  Future<List<Presence>> getMesPresences() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.presences
        .where((p) => p.memberId == 'demo-m-001').toList(), (e) => e.id));
  }

  @override
  Future<List<Contribution>> getMesContributions() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data
        .contributionsOf(_churchId)
        .where((c) => c.memberId == 'demo-m-001'));
  }

  @override
  Future<List<Attestation>> getMesAttestations() async => [];

  // P1 : fil privé du fidèle et confirmation de présence au culte.
  // La démo ne garde pas de messages : le fil reste vide.
  @override
  Future<FilMessages> getMesMessages() async {
    await _latence();
    _requireAuth();
    return const FilMessages(messages: []);
  }

  @override
  Future<MessageFidele> envoyerMessageFidele(
      {required String corps}) async {
    await _latence();
    _requireAuth();
    return MessageFidele(
      id: 'demo-msg-${DateTime.now().millisecondsSinceEpoch}',
      auteur: 'membre',
      corps: corps,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> confirmerPresenceCulte(String culteId) async {
    await _latence();
    _requireAuth();
  }

  @override
  Future<void> annulerPresenceCulte(String culteId) async {
    await _latence();
    _requireAuth();
  }

  // US3 : pas d'attestations dans le seed démo.
  @override
  Future<List<Attestation>> getAttestations(
          {int? annee, String? type}) async =>
      [];

  @override
  Future<List<Attestation>> genererAttestations({required int annee}) async =>
      [];

  @override
  Future<Attestation> emettreAttestation({
    required String type,
    required String memberId,
    required String dateEvenement,
    String? lieu,
    String? officiant,
    String? conjointNom,
    String? pereNom,
    String? mereNom,
    String? parrainNom,
    String? marraineNom,
  }) async =>
      throw UnimplementedError('Attestations non gérées en démo.');

  @override
  Future<Attestation> corrigerAttestation(String id,
          {required String motif,
          String? dateEvenement,
          String? lieu,
          String? officiant,
          String? conjointNom,
          String? pereNom,
          String? mereNom,
          String? parrainNom,
          String? marraineNom}) async =>
      throw UnimplementedError('Attestations non gérées en démo.');

  @override
  Future<Uint8List> telechargerAttestationPdf(String id) async =>
      throw UnimplementedError('Attestations non gérées en démo.');

  @override
  Future<MaCarte> getMaCarte() async {
    await _latence();
    _requireAuth();
    if (_role != 'membre') {
      throw const ApiException('Aucune carte liée à ce compte (démo).');
    }
    final membre = _findMember('demo-m-001')!;
    return MaCarte(member: membre, church: _church);
  }

  // -- Églises et arborescence ----------------------------------------------

  ChurchNode _nodeOf(Church eglise) {
    final enfants = _data.churches
        .where((e) => e.parentChurchId == eglise.id)
        .map(_nodeOf)
        .toList();
    final membresActifs = _data
        .membersOf(eglise.id)
        .where((m) => m.status != 'inactif')
        .length;
    return ChurchNode(
      id: eglise.id,
      code: eglise.code,
      name: eglise.name,
      parentChurchId: eglise.parentChurchId,
      city: eglise.city,
      status: eglise.status,
      role: eglise.id == _churchId ? _role : null,
      devise: eglise.devise,
      fuseauHoraire: eglise.fuseauHoraire,
      description: eglise.description,
      membresActifs: membresActifs,
      children: enfants,
    );
  }

  @override
  Future<TreeResult> getTree() async {
    await _latence();
    _requireAuth();
    return TreeResult(
      arbre: _nodeOf(_racine()),
      demandesRattachement: List.unmodifiable(_visible(_data.rattachementsRecus
          .where((r) => r.status == 'en_attente').toList(), (e) => e.id)),
    );
  }

  /// Racine du réseau de l'église active (on remonte les mères). Avant, la
  /// racine était toujours Plateau : une nouvelle église voyait tout le
  /// réseau Grâce Divine dans son arborescence.
  Church _racine() {
    var eglise = _church;
    while (eglise.parentChurchId != null) {
      final parent = _data.churchById(eglise.parentChurchId!);
      if (parent == null) break;
      eglise = parent;
    }
    return eglise;
  }

  @override
  Future<Church> createSubChurch({
    required String name,
    required String city,
    String? phone,
    String? email,
  }) async {
    await _latence();
    _requireAuth();
    final base = city
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '')
        .padRight(3, 'X')
        .substring(0, 3);
    var code = 'GD-$base';
    var n = 2;
    while (_data.churchByCode(code) != null) {
      code = 'GD-$base$n';
      n++;
    }
    final eglise = Church(
      id: _nextId('eglise'),
      code: code,
      name: name,
      parentChurchId: _churchId,
      city: city,
      status: 'active',
      devise: 'FCFA',
      fuseauHoraire: 'Africa/Abidjan',
    );
    _data.churches.add(eglise);
    _data.membersByChurch[eglise.id] = [];
    _data.contributionsByChurch[eglise.id] = [];
    _dupliquerTypesCultes(eglise.id);
    _data.parametresByChurch[eglise.id] = EgliseParametres(
      egliseNom: name,
      egliseCode: code,
      ville: city,
      telephone: phone,
      email: email,
      devise: 'FCFA',
      fuseauHoraire: 'Africa/Abidjan',
    );
    return eglise;
  }

  // -- Rattachements et transferts -------------------------------------------

  @override
  Future<RattachementsResult> getRattachements() async {
    await _latence();
    _requireAuth();
    return RattachementsResult(
      recues: List.unmodifiable(_visible(_data.rattachementsRecus, (e) => e.id)),
      emises: List.unmodifiable(_visible(_data.rattachementsEmis, (e) => e.id)),
    );
  }

  @override
  Future<Rattachement> requestRattachement({
    required String parentCode,
    String? codeTutelle,
  }) async {
    await _latence();
    _requireAuth();
    final parent = _data.churchByCode(parentCode.trim().toUpperCase());
    if (parent == null) {
      throw const ApiException('Code d’église introuvable (démo).');
    }
    final demande = Rattachement(
      id: _nextId('ratt'),
      status: 'en_attente',
      egliseId: _churchId,
      egliseCode: _church.code,
      egliseNom: _church.name,
      egliseVille: _church.city,
      createdAt: DateTime.now(),
    );
    _data.rattachementsEmis.add(demande);
    _tag(demande.id);
    return demande;
  }

  @override
  Future<void> decideRattachement(String id, {required bool accept}) async {
    await _latence();
    _requireAuth();
    final index =
        _data.rattachementsRecus.indexWhere((r) => r.id == id);
    if (index < 0) throw const ApiException('Demande introuvable (démo).');
    final demande = _data.rattachementsRecus[index];
    _data.rattachementsRecus[index] = Rattachement(
      id: demande.id,
      status: accept ? 'acceptee' : 'refusee',
      egliseId: demande.egliseId,
      egliseCode: demande.egliseCode,
      egliseNom: demande.egliseNom,
      egliseVille: demande.egliseVille,
      createdAt: demande.createdAt,
    );
    if (accept) {
      final eglise = _data.churchById(demande.egliseId);
      if (eglise != null && eglise.parentChurchId == null) {
        final i = _data.churches.indexOf(eglise);
        _data.churches[i] = Church(
          id: eglise.id,
          code: eglise.code,
          name: eglise.name,
          parentChurchId: _churchId,
          city: eglise.city,
          status: eglise.status,
          devise: eglise.devise,
          fuseauHoraire: eglise.fuseauHoraire,
          description: eglise.description,
        );
      }
    }
  }

  // -- Annexes et codes de tutelle (démo : listes vides) --------------------
  @override
  Future<List<Annexe>> getAnnexes({String? q}) async {
    await _latence();
    _requireAuth();
    return const [];
  }

  @override
  Future<AnnexeDetail> getAnnexeDetail(String id) async {
    await _latence();
    _requireAuth();
    throw const ApiException('Annexe introuvable (démo).');
  }

  @override
  Future<List<CodeTutelle>> getCodesTutelle() async {
    await _latence();
    _requireAuth();
    return const [];
  }

  @override
  Future<CodeTutelle> createCodeTutelle() async {
    await _latence();
    _requireAuth();
    return CodeTutelle(
      id: _nextId('code'),
      code: 'ESC-T-DEMO01',
      status: 'actif',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> annulerCodeTutelle(String id) async {
    await _latence();
    _requireAuth();
  }

  @override
  Future<NettoyageTestApercu> getNettoyageTestApercu() async {
    await _latence();
    _requireAuth();
    // La démo n'a pas de données TEST : aperçu vide.
    return const NettoyageTestApercu(elements: []);
  }

  @override
  Future<NettoyageTestResultat> executerNettoyageTest() async {
    await _latence();
    _requireAuth();
    return const NettoyageTestResultat(supprimes: []);
  }

  @override
  Future<TransfertsResult> getTransferts() async {
    await _latence();
    _requireAuth();
    final list = _data.transferts;
    return TransfertsResult(
      aTraiter: list.where((t) => t.aTraiterPour(_churchId)).toList(),
      emises: list.where((t) => t.estDepartDe(_churchId)).toList(),
      recues: list
          .where((t) =>
              t.egliseArriveeId == _churchId && !t.estDepartDe(_churchId))
          .toList(),
      historique: list
          .where((t) =>
              t.status != 'en_attente' &&
              (t.estDepartDe(_churchId) ||
                  t.egliseArriveeId == _churchId))
          .toList(),
    );
  }

  @override
  Future<TransfertMembre> requestTransfert({
    required String matricule,
    required String destinationCode,
    String? motif,
  }) async {
    await _latence();
    _requireAuth();
    final membre = _findMemberByMatricule(matricule.trim().toUpperCase(),
        churchId: _churchId);
    if (membre == null) {
      throw const ApiException('Matricule introuvable dans mon église (démo).');
    }
    final destination =
        _data.churchByCode(destinationCode.trim().toUpperCase());
    if (destination == null) {
      throw const ApiException('Code de l’église d’arrivée introuvable (démo).');
    }
    if (destination.id == _churchId) {
      throw const ApiException(
          'L’église d’arrivée est la même que celle de départ (démo).');
    }
    final transfert = TransfertMembre(
      id: _nextId('tr'),
      membreId: membre.id,
      membreNom: membre.fullName,
      ancienMatricule: membre.matricule,
      egliseDepartId: _churchId,
      egliseDepartCode: _church.code,
      egliseDepartNom: _church.name,
      egliseDepartVille: _church.city,
      egliseArriveeId: destination.id,
      egliseArriveeCode: destination.code,
      egliseArriveeNom: destination.name,
      egliseArriveeVille: destination.city,
      motif: motif,
      status: 'en_attente',
      decisionDepart: 'en_attente',
      decisionArrivee: 'en_attente',
      createdAt: DateTime.now(),
    );
    _data.transferts.add(transfert);
    _tag(transfert.id);
    return transfert;
  }

  TransfertMembre _replaceTransfert(TransfertMembre t) {
    final i = _data.transferts.indexWhere((e) => e.id == t.id);
    if (i >= 0) _data.transferts[i] = t;
    return t;
  }

  @override
  Future<void> decideTransfert(String id, {required bool accept}) async {
    await _latence();
    _requireAuth();
    final t = _data.transferts
        .firstWhere((e) => e.id == id, orElse: () => throw const ApiException('Transfert introuvable (démo).'));
    var decisionDepart = t.decisionDepart;
    var decisionArrivee = t.decisionArrivee;
    if (t.egliseDepartId == _churchId) {
      decisionDepart = accept ? 'accepte' : 'refuse';
    } else if (t.egliseArriveeId == _churchId) {
      decisionArrivee = accept ? 'accepte' : 'refuse';
    } else {
      throw const ApiException('Ce transfert ne concerne pas mon église (démo).');
    }
    var status = t.status;
    if (decisionDepart == 'refuse' || decisionArrivee == 'refuse') {
      status = 'refuse';
    } else if (decisionDepart == 'accepte' && decisionArrivee == 'accepte') {
      status = 'accepte';
    }
    final maj = TransfertMembre(
      id: t.id,
      membreId: t.membreId,
      membreNom: t.membreNom,
      ancienMatricule: t.ancienMatricule,
      nouveauMatricule: t.nouveauMatricule,
      egliseDepartId: t.egliseDepartId,
      egliseDepartCode: t.egliseDepartCode,
      egliseDepartNom: t.egliseDepartNom,
      egliseDepartVille: t.egliseDepartVille,
      egliseArriveeId: t.egliseArriveeId,
      egliseArriveeCode: t.egliseArriveeCode,
      egliseArriveeNom: t.egliseArriveeNom,
      egliseArriveeVille: t.egliseArriveeVille,
      motif: t.motif,
      status: status,
      decisionDepart: decisionDepart,
      decisionArrivee: decisionArrivee,
      createdAt: t.createdAt,
      updatedAt: DateTime.now(),
    );
    _replaceTransfert(maj);
    if (status == 'accepte') {
      // Le membre change d'église et reçoit un nouveau matricule.
      final membre = _findMember(t.membreId);
      if (membre != null) {
        final prefix = DemoSeed.matriculePrefix(t.egliseArriveeId);
        final numero = _data.membersOf(t.egliseArriveeId).length + 1;
        final nouveau = Member(
          id: membre.id,
          matricule: '$prefix-${numero.toString().padLeft(3, '0')}',
          fullName: membre.fullName,
          phone: membre.phone,
          email: membre.email,
          birthDate: membre.birthDate,
          department: membre.department,
          cellGroup: membre.cellGroup,
          status: membre.status,
          createdAt: membre.createdAt,
        );
        _data.membersOf(t.egliseDepartId).removeWhere((m) => m.id == membre.id);
        _data.membersOf(t.egliseArriveeId).add(nouveau);
        _replaceTransfert(TransfertMembre(
          id: maj.id,
          membreId: maj.membreId,
          membreNom: maj.membreNom,
          ancienMatricule: maj.ancienMatricule,
          nouveauMatricule: nouveau.matricule,
          egliseDepartId: maj.egliseDepartId,
          egliseDepartCode: maj.egliseDepartCode,
          egliseDepartNom: maj.egliseDepartNom,
          egliseDepartVille: maj.egliseDepartVille,
          egliseArriveeId: maj.egliseArriveeId,
          egliseArriveeCode: maj.egliseArriveeCode,
          egliseArriveeNom: maj.egliseArriveeNom,
          egliseArriveeVille: maj.egliseArriveeVille,
          motif: maj.motif,
          status: maj.status,
          decisionDepart: maj.decisionDepart,
          decisionArrivee: maj.decisionArrivee,
          createdAt: maj.createdAt,
          updatedAt: maj.updatedAt,
        ));
      }
    }
  }

  @override
  Future<void> annulerTransfert(String id) async {
    await _latence();
    _requireAuth();
    final t = _data.transferts
        .firstWhere((e) => e.id == id, orElse: () => throw const ApiException('Transfert introuvable (démo).'));
    _replaceTransfert(TransfertMembre(
      id: t.id,
      membreId: t.membreId,
      membreNom: t.membreNom,
      ancienMatricule: t.ancienMatricule,
      nouveauMatricule: t.nouveauMatricule,
      egliseDepartId: t.egliseDepartId,
      egliseDepartCode: t.egliseDepartCode,
      egliseDepartNom: t.egliseDepartNom,
      egliseDepartVille: t.egliseDepartVille,
      egliseArriveeId: t.egliseArriveeId,
      egliseArriveeCode: t.egliseArriveeCode,
      egliseArriveeNom: t.egliseArriveeNom,
      egliseArriveeVille: t.egliseArriveeVille,
      motif: t.motif,
      status: 'annule',
      decisionDepart: t.decisionDepart,
      decisionArrivee: t.decisionArrivee,
      createdAt: t.createdAt,
      updatedAt: DateTime.now(),
    ));
  }

  // -- Membres ---------------------------------------------------------------

  @override
  Future<MemberPage> getMembers(
      {String? q, String? department, String? status}) async {
    await _latence();
    _requireAuth();
    var list = _data.membersOf(_churchId);
    if (q != null && q.trim().isNotEmpty) {
      final needle = q.trim().toLowerCase();
      list = list
          .where((m) =>
              m.fullName.toLowerCase().contains(needle) ||
              m.matricule.toLowerCase().contains(needle))
          .toList();
    }
    if (department != null && department.isNotEmpty) {
      list = list.where((m) => m.department == department).toList();
    }
    if (status != null && status.isNotEmpty) {
      list = list.where((m) => m.status == status).toList();
    }
    return MemberPage(total: list.length, membres: List.unmodifiable(list));
  }

  @override
  Future<Member> getMember(String id) async {
    await _latence();
    _requireAuth();
    final membre = _findMember(id);
    if (membre == null) throw const ApiException('Membre introuvable (démo).');
    return membre;
  }

  @override
  Future<Member> createMember({
    required String fullName,
    String? phone,
    String? email,
    String? birthDate,
    String? sexe,
    String? department,
    String? fonction,
    String? poste,
    String? cellGroup,
    String? status,
    String? dateMariage,
    String? dateConversion,
  }) async {
    await _latence();
    _requireAuth();
    final prefix = DemoSeed.matriculePrefix(_churchId);
    final numero = _data.membersOf(_churchId).length + 1;
    final membre = Member(
      id: _nextId('membre'),
      matricule: '$prefix-${numero.toString().padLeft(3, '0')}',
      fullName: fullName,
      phone: phone,
      email: email,
      birthDate: birthDate,
      sexe: sexe,
      department: department,
      fonction: fonction,
      poste: poste,
      cellGroup: cellGroup,
      status: status ?? 'actif',
      dateMariage: dateMariage,
      dateConversion: dateConversion,
      createdAt: DateTime.now(),
    );
    _data.membersOf(_churchId).add(membre);
    return membre;
  }

  @override
  Future<Member> updateMember(String id,
      {required String fullName,
      String? phone,
      String? email,
      String? birthDate,
      String? sexe,
      String? department,
      String? fonction,
      String? poste,
      String? cellGroup,
      String? status,
      String? dateMariage,
      String? dateConversion}) async {
    await _latence();
    _requireAuth();
    final list = _data.membersOf(_churchId);
    final index = list.indexWhere((m) => m.id == id);
    if (index == -1) {
      throw const ApiException('Membre introuvable (démo).');
    }
    final ancien = list[index];
    final maj = Member(
      id: ancien.id,
      matricule: ancien.matricule,
      fullName: fullName,
      phone: phone,
      email: email,
      birthDate: birthDate,
      sexe: sexe,
      department: department,
      fonction: fonction,
      poste: poste,
      cellGroup: cellGroup,
      status: status ?? ancien.status,
      statutRiche: ancien.statutRiche,
      dateMariage: dateMariage,
      dateConversion: dateConversion,
      photoUrl: ancien.photoUrl,
      createdAt: ancien.createdAt,
    );
    list[index] = maj;
    return maj;
  }

  @override
  Future<void> deleteMember(String id) async {
    await _latence();
    _requireAuth();
    _data.membersOf(_churchId).removeWhere((m) => m.id == id);
  }

  @override
  Future<List<Anniversaire>> getAnniversaires({int jours = 30}) async {
    await _latence();
    _requireAuth();
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final liste = <Anniversaire>[];
    for (final m in _data.membersOf(_churchId)) {
      final naissance = DateTime.tryParse(m.birthDate ?? '');
      if (naissance == null) continue;
      var prochain = DateTime(aujourdhui.year, naissance.month, naissance.day);
      if (prochain.isBefore(aujourdhui)) {
        prochain = DateTime(aujourdhui.year + 1, naissance.month, naissance.day);
      }
      final reste = prochain.difference(aujourdhui).inDays;
      if (reste <= jours) {
        liste.add(Anniversaire(
          id: m.id,
          fullName: m.fullName,
          matricule: m.matricule,
          birthDate: m.birthDate!,
          prochain: prochain,
          joursRestants: reste,
          ageAtteint: prochain.year - naissance.year,
        ));
      }
    }
    liste.sort((a, b) => a.joursRestants.compareTo(b.joursRestants));
    return liste;
  }

  @override
  Future<Frequentation> getFrequentation(String memberId) async {
    await _latence();
    _requireAuth();
    final cultes = {for (final c in _data.cultes) c.id: c};
    final evenements = {for (final e in _data.evenements) e.id: e};
    final items = _data.presences
        .where((p) => p.memberId == memberId)
        .map((p) {
          final culte = p.culteId == null ? null : cultes[p.culteId];
          final evenement = p.eventId == null ? null : evenements[p.eventId];
          final dateEvenement = culte?.date ??
              (evenement == null
                  ? null
                  : DateTime.tryParse(evenement.dateDebut)) ??
              p.pointeAt;
          return FrequentationItem(
            id: p.id,
            statut: p.statut,
            mode: p.mode,
            pointeAt: p.pointeAt,
            titre: culte?.titre ?? evenement?.titre,
            dateEvenement: dateEvenement,
            type: p.culteId != null ? 'culte' : 'evenement',
          );
        })
        .toList()
      ..sort((a, b) => (b.dateEvenement ?? DateTime(1900))
          .compareTo(a.dateEvenement ?? DateTime(1900)));
    return Frequentation(
      total: items.length,
      presents: items.where((i) => i.statut == 'present').length,
      items: items,
    );
  }

  // -- Import des fidèles (tranche A, non géré en démo) -----------------------
  @override
  Future<Uint8List> telechargerModeleImport() async =>
      throw UnimplementedError('Import non géré en démo.');

  @override
  Future<Map<String, dynamic>> apercuImport({
    String? contenuCsv,
    List<Map<String, String>>? lignes,
    Map<String, String>? mapping,
    String? nomFichier,
  }) async =>
      throw UnimplementedError('Import non géré en démo.');

  @override
  Future<Map<String, dynamic>> confirmerImport({
    String? contenuCsv,
    List<Map<String, String>>? lignes,
    Map<String, String>? mapping,
    String? nomFichier,
  }) async =>
      throw UnimplementedError('Import non géré en démo.');

  @override
  Future<List<Map<String, dynamic>>> historiqueImports() async =>
      throw UnimplementedError('Import non géré en démo.');

  // -- Membres (complément) --------------------------------------------------

  @override
  Future<List<Famille>> getFamilles() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.familles, (e) => e.id));
  }

  @override
  Future<Famille> createFamille({
    required String nom,
    String? chefFamilleId,
    String? adresse,
    String? telephone,
  }) async {
    await _latence();
    _requireAuth();
    final famille = Famille(
      id: _nextId('famille'),
      nom: nom,
      chefFamilleId: chefFamilleId,
      adresse: adresse,
      telephone: telephone,
      createdAt: DateTime.now(),
    );
    _data.familles.add(famille);
    _tag(famille.id);
    return famille;
  }

  @override
  Future<void> deleteFamille(String id) async {
    await _latence();
    _requireAuth();
    _data.familles.removeWhere((f) => f.id == id);
  }

  @override
  Future<List<MembreStatut>> getMembreStatuts(String memberId) async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(
        _data.statuts.where((s) => s.memberId == memberId).toList(),
        (e) => e.id));
  }

  @override
  Future<MembreStatut> changerStatutMembre(String memberId,
      {required String statut, String? motif}) async {
    await _latence();
    _requireAuth();
    final membre = _findMember(memberId);
    if (membre == null) throw const ApiException('Membre introuvable (démo).');
    final entree = MembreStatut(
      id: _nextId('statut'),
      memberId: memberId,
      statut: statut,
      ancienStatut: membre.status,
      motif: motif,
      createdAt: DateTime.now(),
    );
    _data.statuts.add(entree);
    _tag(entree.id);
    // Statut riche -> statut simple, comme le serveur : suspendu, parti et
    // ancien deviennent « inactif », le détail reste dans statutRiche.
    final nouveauStatut = statut == 'nouveau_converti'
        ? 'nouveau_converti'
        : (statut == 'suspendu' || statut == 'parti' || statut == 'ancien')
            ? 'inactif'
            : 'actif';
    final maj = Member(
      id: membre.id,
      matricule: membre.matricule,
      fullName: membre.fullName,
      phone: membre.phone,
      email: membre.email,
      birthDate: membre.birthDate,
      sexe: membre.sexe,
      department: membre.department,
      fonction: membre.fonction,
      poste: membre.poste,
      cellGroup: membre.cellGroup,
      status: nouveauStatut,
      statutRiche: statut,
      dateMariage: membre.dateMariage,
      dateConversion: membre.dateConversion,
      photoUrl: membre.photoUrl,
      createdAt: membre.createdAt,
    );
    for (final list in _data.membersByChurch.values) {
      final i = list.indexWhere((m) => m.id == memberId);
      if (i >= 0) list[i] = maj;
    }
    return entree;
  }

  @override
  Future<List<Bapteme>> getBaptemes({String? memberId}) async {
    await _latence();
    _requireAuth();
    var list = _data.baptemes;
    list = _visible(list, (e) => e.id);
    if (memberId != null) {
      list = list.where((b) => b.memberId == memberId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Bapteme> createBapteme({
    required String memberId,
    required String dateBapteme,
    String? lieu,
    String? pasteur,
    String? certificatNumero,
  }) async {
    await _latence();
    _requireAuth();
    if (_findMember(memberId) == null) {
      throw const ApiException('Membre introuvable (démo).');
    }
    final bapteme = Bapteme(
      id: _nextId('bapteme'),
      memberId: memberId,
      dateBapteme: dateBapteme,
      lieu: lieu,
      pasteur: pasteur,
      certificatNumero: certificatNumero,
      createdAt: DateTime.now(),
    );
    _data.baptemes.add(bapteme);
    _tag(bapteme.id);
    return bapteme;
  }

  @override
  Future<List<LienParentEnfant>> getLiensParentEnfant(
      {String? enfantMemberId, String? parentMemberId}) async {
    await _latence();
    _requireAuth();
    var list = _data.liens;
    list = _visible(list, (e) => e.id);
    if (enfantMemberId != null) {
      list = list.where((l) => l.enfantMemberId == enfantMemberId).toList();
    }
    if (parentMemberId != null) {
      list = list.where((l) => l.parentMemberId == parentMemberId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<LienParentEnfant> createLienParentEnfant({
    required String parentMemberId,
    required String enfantMemberId,
    required String lien,
  }) async {
    await _latence();
    _requireAuth();
    final item = LienParentEnfant(
      id: _nextId('lien'),
      parentMemberId: parentMemberId,
      enfantMemberId: enfantMemberId,
      lien: lien,
      statut: 'en_attente',
      createdAt: DateTime.now(),
    );
    _data.liens.add(item);
    _tag(item.id);
    return item;
  }

  @override
  Future<List<Departement>> getDepartements() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.departements, (e) => e.id));
  }

  @override
  Future<Departement> createDepartement({
    required String nom,
    String? description,
    String? responsableMemberId,
  }) async {
    await _latence();
    _requireAuth();
    final departement = Departement(
      id: _nextId('departement'),
      nom: nom,
      description: description,
      responsableMemberId: responsableMemberId,
      createdAt: DateTime.now(),
    );
    _data.departements.add(departement);
    _tag(departement.id);
    return departement;
  }

  @override
  Future<void> deleteDepartement(String id) async {
    await _latence();
    _requireAuth();
    _data.departements.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<Departement> updateDepartement(String id,
      {required String nom}) async {
    await _latence();
    _requireAuth();
    final index = _data.departements.indexWhere((e) => e.id == id);
    if (index == -1) throw const ApiException('Département introuvable (démo).');
    final ancien = _data.departements[index];
    final maj = Departement(
      id: ancien.id,
      nom: nom,
      description: ancien.description,
      responsableMemberId: ancien.responsableMemberId,
      createdAt: ancien.createdAt,
    );
    _data.departements[index] = maj;
    return maj;
  }

  @override
  Future<List<Fonction>> getFonctions() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.fonctions);
  }

  @override
  Future<Fonction> createFonction({required String nom}) async {
    await _latence();
    _requireAuth();
    final fonction = Fonction(id: _nextId('fonction'), nom: nom);
    _data.fonctions.add(fonction);
    return fonction;
  }

  @override
  Future<Fonction> updateFonction(String id, {required String nom}) async {
    await _latence();
    _requireAuth();
    final index = _data.fonctions.indexWhere((e) => e.id == id);
    if (index == -1) throw const ApiException('Fonction introuvable (démo).');
    final maj = Fonction(id: id, nom: nom);
    _data.fonctions[index] = maj;
    return maj;
  }

  @override
  Future<void> deleteFonction(String id) async {
    await _latence();
    _requireAuth();
    _data.fonctions.removeWhere((e) => e.id == id);
  }

  @override
  Future<List<Poste>> getPostes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.postesOrganisation);
  }

  @override
  Future<Poste> createPoste({required String nom}) async {
    await _latence();
    _requireAuth();
    final poste = Poste(id: _nextId('poste'), nom: nom);
    _data.postesOrganisation.add(poste);
    return poste;
  }

  @override
  Future<Poste> updatePoste(String id, {required String nom}) async {
    await _latence();
    _requireAuth();
    final index = _data.postesOrganisation.indexWhere((e) => e.id == id);
    if (index == -1) throw const ApiException('Poste introuvable (démo).');
    final maj = Poste(id: id, nom: nom);
    _data.postesOrganisation[index] = maj;
    return maj;
  }

  @override
  Future<void> deletePoste(String id) async {
    await _latence();
    _requireAuth();
    _data.postesOrganisation.removeWhere((e) => e.id == id);
  }

  @override
  Future<List<Cellule>> getCellules() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.cellules, (e) => e.id));
  }

  @override
  Future<Cellule> createCellule({
    required String nom,
    String? quartier,
    String? responsableMemberId,
    String? jourReunion,
    String? heureReunion,
  }) async {
    await _latence();
    _requireAuth();
    final cellule = Cellule(
      id: _nextId('cellule'),
      nom: nom,
      quartier: quartier,
      responsableMemberId: responsableMemberId,
      jourReunion: jourReunion,
      heureReunion: heureReunion,
      createdAt: DateTime.now(),
    );
    _data.cellules.add(cellule);
    _tag(cellule.id);
    return cellule;
  }

  @override
  Future<void> deleteCellule(String id) async {
    await _latence();
    _requireAuth();
    _data.cellules.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  Map<String, dynamic> _memberJson(Member m) => {
        'id': m.id,
        'matricule': m.matricule,
        'full_name': m.fullName,
        'phone': m.phone,
        'email': m.email,
        'birth_date': m.birthDate,
        'department': m.department,
        'cell_group': m.cellGroup,
        'status': m.status,
        'created_at': m.createdAt?.toIso8601String(),
      };

  @override
  Future<Map<String, dynamic>> getMembreComplet(String memberId) async {
    await _latence();
    _requireAuth();
    final membre = _findMember(memberId);
    if (membre == null) throw const ApiException('Membre introuvable (démo).');
    final statuts =
        _data.statuts.where((s) => s.memberId == memberId).toList();
    final bapteme = _data.baptemes
        .where((b) => b.memberId == memberId)
        .firstOrNull;
    return {
      'membre': _memberJson(membre),
      'historique_statuts': statuts
          .map((s) => {
                'id': s.id,
                'member_id': s.memberId,
                'statut': s.statut,
                'ancien_statut': s.ancienStatut,
                'motif': s.motif,
                'created_at': s.createdAt?.toIso8601String(),
              })
          .toList(),
      'bapteme': bapteme == null
          ? null
          : {
              'id': bapteme.id,
              'member_id': bapteme.memberId,
              'date_bapteme': bapteme.dateBapteme,
              'lieu': bapteme.lieu,
              'pasteur': bapteme.pasteur,
              'certificat_numero': bapteme.certificatNumero,
              'created_at': bapteme.createdAt?.toIso8601String(),
            },
      'departements': _data.departements
          .where((d) => d.responsableMemberId == memberId)
          .map((d) => {
                'id': d.id,
                'nom': d.nom,
                'description': d.description,
                'responsable_member_id': d.responsableMemberId,
              })
          .toList(),
      'cellules': _data.cellules
          .where((c) => c.responsableMemberId == memberId)
          .map((c) => {
                'id': c.id,
                'nom': c.nom,
                'quartier': c.quartier,
                'responsable_member_id': c.responsableMemberId,
                'jour_reunion': c.jourReunion,
                'heure_reunion': c.heureReunion,
              })
          .toList(),
      'enfants': _data.liens
          .where((l) => l.parentMemberId == memberId)
          .map((l) => {
                'id': l.id,
                'parent_member_id': l.parentMemberId,
                'enfant_member_id': l.enfantMemberId,
                'lien': l.lien,
                'statut': l.statut,
              })
          .toList(),
      'parents': _data.liens
          .where((l) => l.enfantMemberId == memberId)
          .map((l) => {
                'id': l.id,
                'parent_member_id': l.parentMemberId,
                'enfant_member_id': l.enfantMemberId,
                'lien': l.lien,
                'statut': l.statut,
              })
          .toList(),
    };
  }

  // -- Cultes et programmes --------------------------------------------------

  @override
  Future<List<CulteType>> getCulteTypes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.culteTypes, (e) => e.id));
  }

  @override
  Future<CulteType> createCulteType({
    required String nom,
    int? jourSemaine,
    String? heureDebut,
    int? dureeMinutes,
    String? lieu,
  }) async {
    await _latence();
    _requireAuth();
    final type = CulteType(
      id: _nextId('culte-type'),
      nom: nom,
      jourSemaine: jourSemaine,
      heureDebut: heureDebut,
      dureeMinutes: dureeMinutes,
      lieu: lieu,
      createdAt: DateTime.now(),
    );
    _data.culteTypes.add(type);
    _tag(type.id);
    return type;
  }

  @override
  Future<List<Culte>> getCultes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.cultes, (e) => e.id));
  }

  @override
  Future<Culte> createCulte({
    String? culteTypeId,
    required String titre,
    required String dateHeure,
    String? lieu,
    String? orateur,
    String? theme,
  }) async {
    await _latence();
    _requireAuth();
    final culte = Culte(
      id: _nextId('culte'),
      culteTypeId: culteTypeId,
      titre: titre,
      dateHeure: dateHeure,
      lieu: lieu,
      orateur: orateur,
      theme: theme,
      createdAt: DateTime.now(),
    );
    _data.cultes.add(culte);
    _tag(culte.id);
    return culte;
  }

  @override
  Future<void> deleteCulte(String id) async {
    await _latence();
    _requireAuth();
    _data.cultes.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<OrdreCulteItem>> getOrdreCulte(String culteId) async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(
        _data.ordreCulte.where((o) => o.culteId == culteId).toList(),
        (e) => e.id));
  }

  @override
  Future<OrdreCulteItem> createOrdreCulteItem({
    required String culteId,
    required String titre,
    int ordre = 0,
    String? description,
    String? intervenant,
    int? dureeMinutes,
  }) async {
    await _latence();
    _requireAuth();
    final item = OrdreCulteItem(
      id: _nextId('ordre'),
      culteId: culteId,
      ordre: ordre,
      titre: titre,
      description: description,
      intervenant: intervenant,
      dureeMinutes: dureeMinutes,
      createdAt: DateTime.now(),
    );
    _data.ordreCulte.add(item);
    _tag(item.id);
    return item;
  }

  @override
  Future<List<EvenementSpecial>> getEvenementsSpeciaux({String? type}) async {
    await _latence();
    _requireAuth();
    var list = _data.evenements;
    list = _visible(list, (e) => e.id);
    if (type != null && type.isNotEmpty) {
      list = list.where((e) => e.type == type).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<EvenementSpecial> createEvenementSpecial({
    required String type,
    required String titre,
    required String dateDebut,
    String? dateFin,
    String? description,
    String? lieu,
    String? responsable,
  }) async {
    await _latence();
    _requireAuth();
    final evenement = EvenementSpecial(
      id: _nextId('evenement'),
      type: type,
      titre: titre,
      description: description,
      dateDebut: dateDebut,
      dateFin: dateFin,
      lieu: lieu,
      responsable: responsable,
      createdAt: DateTime.now(),
    );
    _data.evenements.add(evenement);
    _tag(evenement.id);
    return evenement;
  }

  // -- Présences ---------------------------------------------------------------

  @override
  Future<List<Presence>> getPresences(
      {String? culteId, String? eventId, String? memberId}) async {
    await _latence();
    _requireAuth();
    var list = _data.presences;
    list = _visible(list, (e) => e.id);
    if (culteId != null) {
      list = list.where((p) => p.culteId == culteId).toList();
    }
    if (eventId != null) {
      list = list.where((p) => p.eventId == eventId).toList();
    }
    if (memberId != null) {
      list = list.where((p) => p.memberId == memberId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Presence> pointerPresence({
    String? matricule,
    String? memberId,
    String? culteId,
    String? eventId,
    String statut = 'present',
    String mode = 'scan_qr',
  }) async {
    await _latence();
    _requireAuth();
    Member? membre;
    if (memberId != null) {
      membre = _findMember(memberId);
    } else if (matricule != null) {
      membre = _findMemberByMatricule(matricule.trim().toUpperCase(),
          churchId: _churchId);
    }
    if (membre == null) {
      throw const ApiException(
          'Membre introuvable (démo) — vérifiez le matricule.');
    }
    final existant = _data.presences.indexWhere((p) =>
        p.memberId == membre!.id &&
        p.culteId == culteId &&
        p.eventId == eventId);
    final presence = Presence(
      id: existant >= 0 ? _data.presences[existant].id : _nextId('presence'),
      eventId: eventId,
      culteId: culteId,
      memberId: membre.id,
      statut: statut,
      mode: mode,
      pointeAt: DateTime.now(),
      membreNom: membre.fullName,
    );
    if (existant >= 0) {
      _data.presences[existant] = presence;
    } else {
      _data.presences.add(presence);
      _tag(presence.id);
    }
    return presence;
  }

  @override
  Future<PresenceStats> getPresenceStats({String? from, String? to}) async {
    await _latence();
    _requireAuth();
    final list = _data.presences;
    final presents = list.where((p) => p.statut == 'present').length;
    final absents = list.where((p) => p.statut == 'absent').length;
    final excuses = list.where((p) => p.statut == 'excuse').length;
    final parCulte = <Map<String, dynamic>>[];
    for (final culte in _data.cultes) {
      final items =
          list.where((p) => p.culteId == culte.id).toList();
      if (items.isEmpty) continue;
      parCulte.add({
        'culte_id': culte.id,
        'titre': culte.titre,
        'total': items.length,
        'presents': items.where((p) => p.statut == 'present').length,
      });
    }
    final parMembre = <Map<String, dynamic>>[];
    for (final membre in _data.membersOf(_churchId)) {
      final items =
          list.where((p) => p.memberId == membre.id).toList();
      if (items.isEmpty) continue;
      parMembre.add({
        'member_id': membre.id,
        'membre_nom': membre.fullName,
        'total': items.length,
        'presents': items.where((p) => p.statut == 'present').length,
      });
    }
    return PresenceStats(
      total: list.length,
      presents: presents,
      absents: absents,
      excuses: excuses,
      parCulte: parCulte,
      parMembre: parMembre,
    );
  }

  // -- Finances (module 4) ---------------------------------------------------

  @override
  Future<List<PosteBudgetaire>> getPostesBudgetaires({String? categorie}) async {
    await _latence();
    _requireAuth();
    var list = _data.postes;
    list = _visible(list, (e) => e.id);
    if (categorie != null && categorie.isNotEmpty) {
      list = list.where((p) => p.categorie == categorie).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<PosteBudgetaire> createPosteBudgetaire({
    required String nom,
    required String categorie,
    String? description,
  }) async {
    await _latence();
    _requireAuth();
    final poste = PosteBudgetaire(
      id: _nextId('poste'),
      nom: nom,
      categorie: categorie,
      description: description,
      createdAt: DateTime.now(),
    );
    _data.postes.add(poste);
    _tag(poste.id);
    return poste;
  }

  @override
  Future<void> deletePosteBudgetaire(String id) async {
    await _latence();
    _requireAuth();
    _data.postes.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<Budget>> getBudgets({int? annee}) async {
    await _latence();
    _requireAuth();
    var list = _data.budgets;
    list = _visible(list, (e) => e.id);
    if (annee != null) {
      list = list.where((b) => b.annee == annee).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Budget> createBudget({
    required String posteId,
    required int annee,
    required int montantPrevu,
  }) async {
    await _latence();
    _requireAuth();
    final budget = Budget(
      id: _nextId('budget'),
      posteId: posteId,
      annee: annee,
      montantPrevu: montantPrevu,
      createdAt: DateTime.now(),
    );
    _data.budgets.add(budget);
    _tag(budget.id);
    return budget;
  }

  @override
  Future<void> deleteBudget(String id) async {
    await _latence();
    _requireAuth();
    _data.budgets.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<Depense>> getDepenses({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.depenses;
    list = _visible(list, (e) => e.id);
    if (statut != null && statut.isNotEmpty) {
      list = list.where((d) => d.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Depense> createDepense({
    String? posteId,
    required int montantFcfa,
    required String motif,
    String? justificatifRef,
    String? dateDepense,
  }) async {
    await _latence();
    _requireAuth();
    final depense = Depense(
      id: _nextId('depense'),
      posteId: posteId,
      montantFcfa: montantFcfa,
      motif: motif,
      justificatifRef: justificatifRef,
      statut: 'soumise',
      dateDepense: dateDepense,
      createdAt: DateTime.now(),
    );
    _data.depenses.add(depense);
    _tag(depense.id);
    return depense;
  }

  @override
  Future<void> deleteDepense(String id) async {
    await _latence();
    _requireAuth();
    _data.depenses.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<Depense> setDepenseStatut(String id, String statut) async {
    await _latence();
    _requireAuth();
    final i = _data.depenses.indexWhere((d) => d.id == id);
    if (i < 0) throw const ApiException('Dépense introuvable (démo).');
    final d = _data.depenses[i];
    final maj = Depense(
      id: d.id,
      posteId: d.posteId,
      montantFcfa: d.montantFcfa,
      motif: d.motif,
      justificatifRef: d.justificatifRef,
      statut: statut,
      dateDepense: d.dateDepense,
      createdAt: d.createdAt,
    );
    _data.depenses[i] = maj;
    return maj;
  }

  @override
  Future<List<CaisseMouvement>> getCaisseMouvements({String? type}) async {
    await _latence();
    _requireAuth();
    var list = _data.caisseMouvements;
    list = _visible(list, (e) => e.id);
    if (type != null && type.isNotEmpty) {
      list = list.where((m) => m.type == type).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<CaisseMouvement> createCaisseMouvement({
    required String type,
    required int montantFcfa,
    required String motif,
    String? reference,
  }) async {
    await _latence();
    _requireAuth();
    final mouvement = CaisseMouvement(
      id: _nextId('caisse'),
      type: type,
      montantFcfa: montantFcfa,
      motif: motif,
      reference: reference,
      createdAt: DateTime.now(),
    );
    _data.caisseMouvements.add(mouvement);
    _tag(mouvement.id);
    return mouvement;
  }

  @override
  Future<CaisseSolde> getCaisseSolde() async {
    await _latence();
    _requireAuth();
    var entrees = 0;
    var sorties = 0;
    for (final m in _data.caisseMouvements) {
      if (m.type == 'entree') {
        entrees += m.montantFcfa;
      } else {
        sorties += m.montantFcfa;
      }
    }
    return CaisseSolde(
      entrees: entrees,
      sorties: sorties,
      solde: entrees - sorties,
      mouvements: _data.caisseMouvements.length,
    );
  }

  @override
  Future<RapportFinancier> getRapportFinancier({int? annee}) async {
    await _latence();
    _requireAuth();
    // Avant, un seul mois en dur ('2026-11') et des dépenses globales (toutes
    // églises) : désormais un mois par ligne pour l'année demandée, filtré
    // par l'église active.
    final anneeDemandee = annee ?? DateTime.now().year;
    final parMois = <Map<String, dynamic>>[];
    for (var m = 1; m <= 12; m++) {
      final debut =
          '$anneeDemandee-${m.toString().padLeft(2, '0')}-01';
      final finMois = m + 1;
      final finA = finMois > 12 ? anneeDemandee + 1 : anneeDemandee;
      final finM = finMois > 12 ? 1 : finMois;
      final fin = '$finA-${finM.toString().padLeft(2, '0')}-01';
      final contributionsMois = _confirmedOf(_churchId)
          .where((c) => _dansPeriode(c.createdAt, debut, fin))
          .toList();
      parMois.add({
        'mois':
            '$anneeDemandee-${m.toString().padLeft(2, '0')}',
        'entrees': contributionsMois
            .where((c) => c.type != 'depense')
            .fold<int>(0, (s, c) => s + c.amountFcfa),
        'depenses': _depensesConfirmees(_churchId, debut: debut, fin: fin),
      });
    }
    final parPoste = _visible(_data.postes, (p) => p.id)
        .map((p) => {
              'poste': p.nom,
              'montant': _visible(_data.depenses, (d) => d.id)
                  .where((d) => d.posteId == p.id)
                  .fold<int>(0, (s, d) => s + d.montantFcfa),
            })
        .toList();
    final parBranche = _data.churches
        .where((e) => e.parentChurchId == _churchId || e.id == _churchId)
        .map((e) => {
              'eglise_nom': e.name,
              'total_fcfa': _chiffres(e.id).totalFcfa,
            })
        .toList();
    return RapportFinancier(
      parMois: parMois,
      parPoste: parPoste,
      parBranche: parBranche,
    );
  }

  // -- Finances (contributions) ----------------------------------------------

  @override
  Future<ContributionPage> getContributions({String? type, String? status}) async {
    await _latence();
    _requireAuth();
    var list = _data.contributionsOf(_churchId);
    if (type != null && type.isNotEmpty) {
      list = list.where((c) => c.type == type).toList();
    }
    if (status != null && status.isNotEmpty) {
      list = list.where((c) => c.status == status).toList();
    }
    return ContributionPage(
      contributions: List.unmodifiable(list),
      totaux: _totaux(_data.contributionsOf(_churchId),
          depensesBudget: _depensesBudget(_churchId),
          nombreDepensesBudget: _nombreDepensesBudget(_churchId)),
    );
  }

  @override
  Future<Contribution> getReceipt(String id) async {
    await _latence();
    _requireAuth();
    final contribution = _data
        .contributionsOf(_churchId)
        .where((c) => c.id == id)
        .firstOrNull;
    if (contribution == null) {
      throw const ApiException('Reçu introuvable (démo).');
    }
    return contribution;
  }

  @override
  Future<Contribution> createContribution({
    required String type,
    required int amountFcfa,
    required String paymentMethod,
    String? paymentRef,
    String? memberId,
    String? campagneId,
    String? note,
  }) async {
    await _latence();
    _requireAuth();
    final membre = memberId == null ? null : _findMember(memberId);
    final contribution = Contribution(
      id: _nextId('contribution'),
      type: type,
      amountFcfa: amountFcfa,
      paymentMethod: paymentMethod,
      paymentRef: paymentRef,
      status: 'en_attente',
      note: note,
      memberId: memberId,
      membreNom: membre?.fullName,
      membreMatricule: membre?.matricule,
      createdAt: DateTime.now(),
      egliseNom: _church.name,
      egliseCode: _church.code,
    );
    _data.contributionsOf(_churchId).add(contribution);
    return contribution;
  }

  @override
  Future<Contribution> setContributionStatus(String id, String status) async {
    await _latence();
    _requireAuth();
    final list = _data.contributionsOf(_churchId);
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0) throw const ApiException('Contribution introuvable (démo).');
    final c = list[i];
    final maj = Contribution(
      id: c.id,
      type: c.type,
      amountFcfa: c.amountFcfa,
      paymentMethod: c.paymentMethod,
      paymentRef: c.paymentRef,
      status: status,
      note: c.note,
      memberId: c.memberId,
      membreNom: c.membreNom,
      membreMatricule: c.membreMatricule,
      createdAt: c.createdAt,
      egliseNom: c.egliseNom,
      egliseCode: c.egliseCode,
    );
    list[i] = maj;
    return maj;
  }

  // -- Campagnes de collecte (US2, démo : aucune campagne fictive) -----------

  @override
  Future<List<Campagne>> getCampagnes() async {
    await _latence();
    _requireAuth();
    return const [];
  }

  @override
  Future<Campagne> createCampagne({
    required String nom,
    required int objectifFcfa,
    required String dateDebut,
    required String dateFin,
    String statut = 'brouillon',
    bool visibleMembres = false,
  }) async {
    throw const ApiException('Campagnes non disponibles en démo.');
  }

  @override
  Future<Campagne> setCampagneStatut(String id, String statut) async {
    throw const ApiException('Campagnes non disponibles en démo.');
  }

  @override
  Future<void> cloturerCampagne(String id) async {
    throw const ApiException('Campagnes non disponibles en démo.');
  }

  @override
  Future<Contribution> affecterContributionCampagne(
      String id, String? campagneId) async {
    throw const ApiException('Campagnes non disponibles en démo.');
  }

  // -- Communication ---------------------------------------------------------

  @override
  Future<List<DemandePriere>> getDemandesPriere({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.prieres;
    list = _visible(list, (e) => e.id);
    if (statut != null && statut.isNotEmpty) {
      list = list.where((p) => p.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<DemandePriere> createDemandePriere({
    required String sujet,
    String? memberId,
    String? demandeurNom,
    String? details,
    bool confidentiel = false,
  }) async {
    await _latence();
    _requireAuth();
    final demande = DemandePriere(
      id: _nextId('priere'),
      memberId: memberId,
      demandeurNom: demandeurNom,
      sujet: sujet,
      details: details,
      confidentiel: confidentiel,
      statut: 'nouvelle',
      createdAt: DateTime.now(),
    );
    _data.prieres.add(demande);
    _tag(demande.id);
    return demande;
  }

  @override
  Future<void> deleteDemandePriere(String id) async {
    await _latence();
    _requireAuth();
    _data.prieres.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<DemandePriere> setDemandePriereStatut(String id, String statut) async {
    await _latence();
    _requireAuth();
    final i = _data.prieres.indexWhere((p) => p.id == id);
    if (i < 0) throw const ApiException('Demande introuvable (démo).');
    final p = _data.prieres[i];
    final maj = DemandePriere(
      id: p.id,
      memberId: p.memberId,
      demandeurNom: p.demandeurNom,
      sujet: p.sujet,
      details: p.details,
      confidentiel: p.confidentiel,
      statut: statut,
      createdAt: p.createdAt,
    );
    _data.prieres[i] = maj;
    return maj;
  }

  @override
  Future<List<MessageInterne>> getMessagesInternes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.messages, (e) => e.id));
  }

  @override
  Future<MessageInterne> createMessageInterne({
    required String sujet,
    required String corps,
    String? destinataireId,
  }) async {
    await _latence();
    _requireAuth();
    final message = MessageInterne(
      id: _nextId('message'),
      expediteurId: _user?.id ?? 'demo-user-admin',
      destinataireId: destinataireId,
      sujet: sujet,
      corps: corps,
      lu: false,
      createdAt: DateTime.now(),
    );
    _data.messages.add(message);
    _tag(message.id);
    return message;
  }

  // -- Suivi pastoral ----------------------------------------------------------

  @override
  Future<List<ParcoursNouveau>> getParcoursNouveaux({String? etape}) async {
    await _latence();
    _requireAuth();
    var list = _data.parcours;
    list = _visible(list, (e) => e.id);
    if (etape != null && etape.isNotEmpty) {
      list = list.where((p) => p.etape == etape).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<ParcoursNouveau> createParcoursNouveau({
    required String memberId,
    String etape = 'accueil',
    String? note,
  }) async {
    await _latence();
    _requireAuth();
    final parcours = ParcoursNouveau(
      id: _nextId('parcours'),
      memberId: memberId,
      etape: etape,
      note: note,
      createdAt: DateTime.now(),
    );
    _data.parcours.add(parcours);
    _tag(parcours.id);
    return parcours;
  }

  @override
  Future<ParcoursNouveau> setParcoursEtape(String id, String etape) async {
    await _latence();
    _requireAuth();
    final i = _data.parcours.indexWhere((p) => p.id == id);
    if (i < 0) throw const ApiException('Parcours introuvable (démo).');
    final p = _data.parcours[i];
    final maj = ParcoursNouveau(
      id: p.id,
      memberId: p.memberId,
      etape: etape,
      dateEtape: p.dateEtape,
      note: p.note,
      createdAt: p.createdAt,
    );
    _data.parcours[i] = maj;
    return maj;
  }

  @override
  Future<List<VisitePastorale>> getVisitesPastorales({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.visites;
    list = _visible(list, (e) => e.id);
    if (statut != null && statut.isNotEmpty) {
      list = list.where((v) => v.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<VisitePastorale> createVisitePastorale({
    required String memberId,
    required String dateVisite,
    String? motif,
    String? compteRendu,
  }) async {
    await _latence();
    _requireAuth();
    final visite = VisitePastorale(
      id: _nextId('visite'),
      memberId: memberId,
      dateVisite: dateVisite,
      motif: motif,
      compteRendu: compteRendu,
      statut: 'planifiee',
      createdAt: DateTime.now(),
    );
    _data.visites.add(visite);
    _tag(visite.id);
    return visite;
  }

  @override
  Future<List<Accompagnement>> getAccompagnements(
      {String? type, String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.accompagnements;
    list = _visible(list, (e) => e.id);
    if (type != null && type.isNotEmpty) {
      list = list.where((a) => a.type == type).toList();
    }
    if (statut != null && statut.isNotEmpty) {
      list = list.where((a) => a.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Accompagnement> createAccompagnement({
    required String memberId,
    required String type,
    String? description,
  }) async {
    await _latence();
    _requireAuth();
    final accompagnement = Accompagnement(
      id: _nextId('accompagnement'),
      memberId: memberId,
      type: type,
      description: description,
      statut: 'en_cours',
      createdAt: DateTime.now(),
    );
    _data.accompagnements.add(accompagnement);
    _tag(accompagnement.id);
    return accompagnement;
  }

  // -- Serviteurs --------------------------------------------------------------

  @override
  Future<List<Serviteur>> getServiteurs({String? departementId}) async {
    await _latence();
    _requireAuth();
    var list = _data.serviteurs;
    list = _visible(list, (e) => e.id);
    if (departementId != null && departementId.isNotEmpty) {
      list = list.where((s) => s.departementId == departementId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Serviteur> createServiteur({
    required String memberId,
    required String departementId,
    String role = 'serviteur',
    String? disponibilite,
  }) async {
    await _latence();
    _requireAuth();
    final serviteur = Serviteur(
      id: _nextId('serviteur'),
      memberId: memberId,
      departementId: departementId,
      role: role,
      disponibilite: disponibilite,
      createdAt: DateTime.now(),
    );
    _data.serviteurs.add(serviteur);
    _tag(serviteur.id);
    return serviteur;
  }

  @override
  Future<void> deleteServiteur(String id) async {
    await _latence();
    _requireAuth();
    _data.serviteurs.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<PlanningServiteur>> getPlanningServiteurs() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.planning, (e) => e.id));
  }

  @override
  Future<PlanningServiteur> createPlanningServiteur({
    required String serviteurId,
    required String dateService,
    String? culteId,
    String? roleService,
  }) async {
    await _latence();
    _requireAuth();
    final item = PlanningServiteur(
      id: _nextId('planning'),
      serviteurId: serviteurId,
      culteId: culteId,
      dateService: dateService,
      roleService: roleService,
      statut: 'prevu',
      createdAt: DateTime.now(),
    );
    _data.planning.add(item);
    _tag(item.id);
    return item;
  }

  // -- Enfants et jeunesse ------------------------------------------------------

  @override
  Future<List<ClasseEnfant>> getClassesEnfants() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.classesEnfants, (e) => e.id));
  }

  @override
  Future<ClasseEnfant> createClasseEnfant({
    required String nom,
    int? ageMin,
    int? ageMax,
    String? salle,
  }) async {
    await _latence();
    _requireAuth();
    final classe = ClasseEnfant(
      id: _nextId('classe'),
      nom: nom,
      ageMin: ageMin,
      ageMax: ageMax,
      salle: salle,
      createdAt: DateTime.now(),
    );
    _data.classesEnfants.add(classe);
    _tag(classe.id);
    return classe;
  }

  @override
  Future<void> deleteClasseEnfant(String id) async {
    await _latence();
    _requireAuth();
    _data.classesEnfants.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<AutorisationSortie>> getAutorisationsSorties(
      {String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.autorisations;
    list = _visible(list, (e) => e.id);
    if (statut != null && statut.isNotEmpty) {
      list = list.where((a) => a.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<AutorisationSortie> createAutorisationSortie({
    required String enfantMemberId,
    required String activite,
    required String dateSortie,
    String? parentMemberId,
  }) async {
    await _latence();
    _requireAuth();
    final autorisation = AutorisationSortie(
      id: _nextId('autorisation'),
      enfantMemberId: enfantMemberId,
      parentMemberId: parentMemberId,
      activite: activite,
      dateSortie: dateSortie,
      statut: 'en_attente',
      createdAt: DateTime.now(),
    );
    _data.autorisations.add(autorisation);
    _tag(autorisation.id);
    return autorisation;
  }

  @override
  Future<AutorisationSortie> setAutorisationStatut(
      String id, String statut) async {
    await _latence();
    _requireAuth();
    final i = _data.autorisations.indexWhere((a) => a.id == id);
    if (i < 0) throw const ApiException('Autorisation introuvable (démo).');
    final a = _data.autorisations[i];
    final maj = AutorisationSortie(
      id: a.id,
      enfantMemberId: a.enfantMemberId,
      parentMemberId: a.parentMemberId,
      activite: a.activite,
      dateSortie: a.dateSortie,
      statut: statut,
      createdAt: a.createdAt,
    );
    _data.autorisations[i] = maj;
    return maj;
  }

  @override
  Future<List<ActiviteJeunesse>> getActivitesJeunesse() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.activitesJeunesse, (e) => e.id));
  }

  @override
  Future<ActiviteJeunesse> createActiviteJeunesse({
    required String titre,
    required String dateActivite,
    String? description,
    String? lieu,
    String? responsableMemberId,
  }) async {
    await _latence();
    _requireAuth();
    final activite = ActiviteJeunesse(
      id: _nextId('activite'),
      titre: titre,
      description: description,
      dateActivite: dateActivite,
      lieu: lieu,
      responsableMemberId: responsableMemberId,
      createdAt: DateTime.now(),
    );
    _data.activitesJeunesse.add(activite);
    _tag(activite.id);
    return activite;
  }

  // -- Check-ins enfants, double QR ECODIM (repli démo : liste vide, sans effet) --

  @override
  Future<CheckinEnfant> checkinEnfant({
    required String enfantMemberId,
    required String parentMemberId,
    required String codeParent,
    required String codeEnfant,
    String? salle,
    String? allergie,
  }) async {
    throw const ApiException('Check-in enfants non disponible en démo.');
  }

  @override
  Future<CheckinEnfant> sortieEnfant({
    required String checkinId,
    required String codeEnfant,
    required String codeParent,
  }) async {
    throw const ApiException('Sortie enfants non disponible en démo.');
  }

  @override
  Future<CheckinEnfant> alerteCheckinEnfant({
    required String checkinId,
    required String message,
  }) async {
    throw const ApiException('Alerte silencieuse non disponible en démo.');
  }

  @override
  Future<List<CheckinEnfant>> getCheckinsEnfantsJour({String? salle}) async {
    await _latence();
    _requireAuth();
    return const <CheckinEnfant>[];
  }

  // -- Médias et enseignements ---------------------------------------------------

  @override
  Future<List<Predication>> getPredications() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.predications, (e) => e.id));
  }

  @override
  Future<Predication> createPredication({
    required String titre,
    required String datePredication,
    String? orateur,
    String? serie,
    String? urlAudio,
    String? urlVideo,
  }) async {
    await _latence();
    _requireAuth();
    final predication = Predication(
      id: _nextId('predication'),
      titre: titre,
      orateur: orateur,
      datePredication: datePredication,
      serie: serie,
      urlAudio: urlAudio,
      urlVideo: urlVideo,
      createdAt: DateTime.now(),
    );
    _data.predications.add(predication);
    _tag(predication.id);
    return predication;
  }

  @override
  Future<List<PlanLecture>> getPlansLecture() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.plansLecture, (e) => e.id));
  }

  @override
  Future<PlanLecture> createPlanLecture({
    required String nom,
    String? description,
    int? dureeJours,
  }) async {
    await _latence();
    _requireAuth();
    final plan = PlanLecture(
      id: _nextId('plan'),
      nom: nom,
      description: description,
      dureeJours: dureeJours,
      createdAt: DateTime.now(),
    );
    _data.plansLecture.add(plan);
    _tag(plan.id);
    return plan;
  }

  @override
  Future<List<Livre>> getLivres() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.livres, (e) => e.id));
  }

  @override
  Future<Livre> createLivre({
    required String titre,
    String? auteur,
    String? categorie,
    int exemplaires = 1,
  }) async {
    await _latence();
    _requireAuth();
    final livre = Livre(
      id: _nextId('livre'),
      titre: titre,
      auteur: auteur,
      categorie: categorie,
      exemplaires: exemplaires,
      createdAt: DateTime.now(),
    );
    _data.livres.add(livre);
    _tag(livre.id);
    return livre;
  }

  @override
  Future<void> deleteLivre(String id) async {
    await _latence();
    _requireAuth();
    _data.livres.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<PretLivre>> getPretsLivres({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.pretsLivres;
    list = _visible(list, (e) => e.id);
    if (statut != null && statut.isNotEmpty) {
      list = list.where((p) => p.statut == statut).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<PretLivre> createPretLivre({
    required String livreId,
    required String memberId,
    String? dateRetourPrevue,
  }) async {
    await _latence();
    _requireAuth();
    final pret = PretLivre(
      id: _nextId('pret'),
      livreId: livreId,
      memberId: memberId,
      datePret: DateTime.now().toIso8601String().substring(0, 10),
      dateRetourPrevue: dateRetourPrevue,
      statut: 'en_cours',
      createdAt: DateTime.now(),
    );
    _data.pretsLivres.add(pret);
    _tag(pret.id);
    return pret;
  }

  @override
  Future<PretLivre> rendreLivre(String id) async {
    await _latence();
    _requireAuth();
    final i = _data.pretsLivres.indexWhere((p) => p.id == id);
    if (i < 0) throw const ApiException('Prêt introuvable (démo).');
    final p = _data.pretsLivres[i];
    final maj = PretLivre(
      id: p.id,
      livreId: p.livreId,
      memberId: p.memberId,
      datePret: p.datePret,
      dateRetourPrevue: p.dateRetourPrevue,
      dateRetour: DateTime.now().toIso8601String().substring(0, 10),
      statut: 'rendu',
      createdAt: p.createdAt,
    );
    _data.pretsLivres[i] = maj;
    return maj;
  }

  // -- Biens et inventaire -------------------------------------------------------

  @override
  Future<List<Salle>> getSalles() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.salles, (e) => e.id));
  }

  @override
  Future<Salle> createSalle({
    required String nom,
    int? capacite,
    String? description,
  }) async {
    await _latence();
    _requireAuth();
    final salle = Salle(
      id: _nextId('salle'),
      nom: nom,
      capacite: capacite,
      description: description,
      createdAt: DateTime.now(),
    );
    _data.salles.add(salle);
    _tag(salle.id);
    return salle;
  }

  @override
  Future<void> deleteSalle(String id) async {
    await _latence();
    _requireAuth();
    _data.salles.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  @override
  Future<List<ReservationSalle>> getReservationsSalles({String? salleId}) async {
    await _latence();
    _requireAuth();
    var list = _data.reservationsSalles;
    list = _visible(list, (e) => e.id);
    if (salleId != null && salleId.isNotEmpty) {
      list = list.where((r) => r.salleId == salleId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<ReservationSalle> createReservationSalle({
    required String salleId,
    required String titre,
    required String debut,
    required String fin,
    String? reservePar,
  }) async {
    await _latence();
    _requireAuth();
    final reservation = ReservationSalle(
      id: _nextId('reservation'),
      salleId: salleId,
      titre: titre,
      debut: debut,
      fin: fin,
      reservePar: reservePar,
      statut: 'confirmee',
      createdAt: DateTime.now(),
    );
    _data.reservationsSalles.add(reservation);
    _tag(reservation.id);
    return reservation;
  }

  @override
  Future<List<Materiel>> getMateriel({String? etat}) async {
    await _latence();
    _requireAuth();
    var list = _data.materiel;
    list = _visible(list, (e) => e.id);
    if (etat != null && etat.isNotEmpty) {
      list = list.where((m) => m.etat == etat).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<Materiel> createMateriel({
    required String nom,
    String? categorie,
    int quantite = 1,
    String etat = 'bon',
    String? responsableMemberId,
  }) async {
    await _latence();
    _requireAuth();
    final item = Materiel(
      id: _nextId('materiel'),
      nom: nom,
      categorie: categorie,
      quantite: quantite,
      etat: etat,
      responsableMemberId: responsableMemberId,
      createdAt: DateTime.now(),
    );
    _data.materiel.add(item);
    _tag(item.id);
    return item;
  }

  @override
  Future<List<MaintenanceMateriel>> getMaintenanceMateriel(
      {String? materielId}) async {
    await _latence();
    _requireAuth();
    var list = _data.maintenances;
    list = _visible(list, (e) => e.id);
    if (materielId != null && materielId.isNotEmpty) {
      list = list.where((m) => m.materielId == materielId).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<MaintenanceMateriel> createMaintenanceMateriel({
    required String materielId,
    required String description,
    String? dateMaintenance,
    int? coutFcfa,
    String? realisePar,
  }) async {
    await _latence();
    _requireAuth();
    final maintenance = MaintenanceMateriel(
      id: _nextId('maintenance'),
      materielId: materielId,
      dateMaintenance: dateMaintenance,
      description: description,
      coutFcfa: coutFcfa,
      realisePar: realisePar,
      createdAt: DateTime.now(),
    );
    _data.maintenances.add(maintenance);
    _tag(maintenance.id);
    return maintenance;
  }

  // -- Statistiques et export ------------------------------------------------------

  @override
  Future<StatsGlobales> getStatsGlobales() async {
    await _latence();
    _requireAuth();
    // Avant, les compteurs « ce mois-ci » étaient des totaux permanents
    // sans filtre de date, toutes églises confondues : désormais le mois
    // courant, pour l'église active uniquement.
    final maintenant = DateTime.now();
    final moisAncre =
        '${maintenant.year}-${maintenant.month.toString().padLeft(2, '0')}';
    final bornes = _bornesPeriode('mois', moisAncre);
    final debut = bornes.debut;
    final fin = bornes.fin;
    final membres = _data.membersOf(_churchId);
    final recettes = _confirmedOf(_churchId)
        .where((c) =>
            c.type != 'depense' && _dansPeriode(c.createdAt, debut, fin))
        .fold<int>(0, (s, c) => s + c.amountFcfa);
    final depenses =
        _depensesConfirmees(_churchId, debut: debut, fin: fin);
    final reseau = _data.churches
        .where((e) => e.parentChurchId == _churchId)
        .map((e) => RapportSousEglise(
              egliseId: e.id,
              egliseNom: e.name,
              niveau: 1,
              membresActifs: _chiffres(e.id).membresActifs,
              nombreContributions: _chiffres(e.id).nombreContributions,
              totalFcfa: _chiffres(e.id).totalFcfa,
            ))
        .toList();
    return StatsGlobales(
      membresActifs: membres.where((m) => m.status != 'inactif').length,
      nouveauxConvertis:
          membres.where((m) => m.status == 'nouveau_converti').length,
      baptemes: _visible(_data.baptemes, (b) => b.id)
          .where((b) =>
              b.dateBapteme.compareTo(debut) >= 0 &&
              b.dateBapteme.compareTo(fin) < 0)
          .length,
      cultesMois: _visible(_data.cultes, (c) => c.id)
          .where((c) =>
              _dansPeriode(DateTime.tryParse(c.dateHeure), debut, fin))
          .length,
      presencesMois: _visible(_data.presences, (p) => p.id)
          .where((p) =>
              p.statut == 'present' &&
              _dansPeriode(p.pointeAt, debut, fin))
          .length,
      recettesMoisFcfa: recettes,
      depensesMoisFcfa: depenses,
      reseau: reseau,
    );
  }

  @override
  Future<String> exportCsv(String type) async {
    await _latence();
    _requireAuth();
    final tampon = StringBuffer();
    if (type == 'membres') {
      tampon.writeln('matricule;nom;email;telephone;departement;statut');
      for (final m in _data.membersOf(_churchId)) {
        tampon.writeln(
            '${m.matricule};${m.fullName};${m.email ?? ''};${m.phone ?? ''};${m.department ?? ''};${m.status}');
      }
    } else if (type == 'contributions') {
      tampon.writeln('date;type;montant_fcfa;moyen;statut;membre');
      for (final c in _data.contributionsOf(_churchId)) {
        tampon.writeln(
            '${c.createdAt?.toIso8601String().substring(0, 10) ?? ''};${c.type};${c.amountFcfa};${c.paymentMethod};${c.status};${c.membreNom ?? ''}');
      }
    } else {
      throw const ApiException('Export inconnu (démo).');
    }
    return tampon.toString();
  }

  // -- Exports PDF (tranche C) : non gérés en démo, comme les attestations.
  @override
  Future<Uint8List> exporterFinancesDetailPdf(
          {String? from, String? to}) async =>
      throw UnimplementedError('Exports PDF non gérés en démo.');

  @override
  Future<Uint8List> exporterFinancesResumePdf(
          {String? from, String? to, int? annee}) async =>
      throw UnimplementedError('Exports PDF non gérés en démo.');

  @override
  Future<Uint8List> exporterCultesPdf({String? from, String? to}) async =>
      throw UnimplementedError('Exports PDF non gérés en démo.');

  @override
  Future<Uint8List> exporterRapportConsolidePdf() async =>
      throw UnimplementedError('Exports PDF non gérés en démo.');

  // -- Administration --------------------------------------------------------------

  @override
  Future<EgliseParametres> getParametres() async {
    await _latence();
    _requireAuth();
    return _data.parametresByChurch.putIfAbsent(
        _churchId, () => _defaultParametres());
  }

  /// Paramètres vides à son nom pour une église sans paramètres.
  EgliseParametres _defaultParametres() => EgliseParametres(
        egliseNom: _church.name,
        egliseCode: _church.code,
        ville: _church.city,
        devise: _church.devise,
        fuseauHoraire: _church.fuseauHoraire,
      );

  @override
  Future<EgliseParametres> saveParametres({
    String? adresse,
    String? ville,
    String? telephone,
    String? email,
    String? logoUrl,
    String? waveNumero,
    String? orangeNumero,
    String? mtnNumero,
    String? devise,
    String? fuseauHoraire,
  }) async {
    await _latence();
    _requireAuth();
    final p = _data.parametresByChurch.putIfAbsent(
        _churchId, () => _defaultParametres());
    final maj = EgliseParametres(
      adresse: adresse ?? p.adresse,
      ville: ville ?? p.ville,
      telephone: telephone ?? p.telephone,
      email: email ?? p.email,
      logoUrl: logoUrl ?? p.logoUrl,
      waveNumero: waveNumero ?? p.waveNumero,
      orangeNumero: orangeNumero ?? p.orangeNumero,
      mtnNumero: mtnNumero ?? p.mtnNumero,
      devise: devise ?? p.devise,
      fuseauHoraire: fuseauHoraire ?? p.fuseauHoraire,
      egliseNom: p.egliseNom,
      egliseCode: p.egliseCode,
    );
    _data.parametresByChurch[_churchId] = maj;
    return maj;
  }

  @override
  Future<List<RoleEglise>> getRoles() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.roles, (e) => e.userId));
  }

  @override
  Future<RoleEglise> setRole(String userId, String role) async {
    await _latence();
    _requireAuth();
    final i = _data.roles.indexWhere((r) => r.userId == userId);
    if (i < 0) throw const ApiException('Utilisateur introuvable (démo).');
    final r = _data.roles[i];
    final maj = RoleEglise(
      userId: r.userId,
      role: role,
      fullName: r.fullName,
      email: r.email,
    );
    _data.roles[i] = maj;
    return maj;
  }

  @override
  Future<List<AuditEntree>> getAudit() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.audit, (e) => e.id));
  }

  // -- Présentation et identité ----------------------------------------------------

  @override
  Future<ProfilEglise> getPresentation(String code) async {
    await _latence();
    _requireAuth();
    final eglise = _data.churchByCode(code.toUpperCase()) ?? _data.plateau;
    final antennes = _data.churches
        .where((e) => e.parentChurchId == eglise.id)
        .toList();
    return ProfilEglise(
      eglise: _withRole(eglise, eglise.id == _churchId ? _role! : 'admin_eglise'),
      pasteurPrincipal:
          eglise.id == DemoIds.plateau ? 'Pasteur Emmanuel Aka' : null,
      antennes: antennes,
    );
  }

  @override
  Future<Church> updateProfil({
    required String churchId,
    String? name,
    String? description,
    List<HoraireCulte>? horaires,
    String? couleurPrincipale,
    String? devise,
    String? fuseauHoraire,
    String? address,
    String? phone,
    String? email,
    String? city,
  }) async {
    await _latence();
    _requireAuth();
    final eglise = _data.churchById(churchId);
    if (eglise == null) throw const ApiException('Église introuvable (démo).');
    final maj = Church(
      id: eglise.id,
      code: eglise.code,
      name: name ?? eglise.name,
      parentChurchId: eglise.parentChurchId,
      city: city ?? eglise.city,
      status: eglise.status,
      role: eglise.role,
      logoUrl: eglise.logoUrl,
      couleurPrincipale: couleurPrincipale ?? eglise.couleurPrincipale,
      devise: devise ?? eglise.devise,
      fuseauHoraire: fuseauHoraire ?? eglise.fuseauHoraire,
      description: description ?? eglise.description,
      horairesCultes: horaires ?? eglise.horairesCultes,
    );
    final i = _data.churches.indexOf(eglise);
    _data.churches[i] = maj;
    return _withRole(maj, _role ?? 'admin_eglise');
  }

  @override
  Future<String> uploadLogo({
    required String churchId,
    required String base64,
    String? filename,
  }) async {
    await _latence();
    _requireAuth();
    // Pas de stockage en démo : le logo n'est jamais téléversé.
    throw const ApiException('Téléversement de logo désactivé en démo.');
  }

  @override
  Future<void> switchChurch(String churchId) async {
    await _latence();
    _requireAuth();
    final eglise = _data.churchById(churchId);
    if (eglise == null) throw const ApiException('Église introuvable (démo).');
    _churchId = churchId;
    // En démo, l'admin de démonstration gère toutes les églises du réseau.
    // Le compte plateforme garde son rôle super_admin en changeant d'église.
    if (_role != 'super_admin') _role = 'admin_eglise';
  }

  @override
  Future<AuthResult> refresh() async {
    await _latence();
    _requireAuth();
    // En démo, pas de vrai jeton : la session est simplement prolongée.
    final eglise = _data.churchById(_churchId) ?? _data.plateau;
    final result = _buildAuth(_user!, eglise, _role ?? 'membre');
    _applyAuth(result);
    return result;
  }

  @override
  Future<void> logout() async {
    await _latence();
    _user = null;
    _role = null;
    _churchId = DemoIds.plateau;
    _eglises = [];
  }

  @override
  Future<MesEglisesPage> listerMesEglises(
      {String? recherche, int page = 1, int limite = 50}) async {
    await _latence();
    _requireAuth();
    final q = recherche?.trim().toLowerCase() ?? '';
    final toutes = _eglises.where((m) {
      if (q.isEmpty) return true;
      final c = m.church;
      return c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q) ||
          (c.city ?? '').toLowerCase().contains(q);
    }).toList();
    final debut = (page - 1) * limite;
    final fin = (debut + limite).clamp(0, toutes.length);
    final tranche =
        debut >= toutes.length ? <Membership>[] : toutes.sublist(debut, fin);
    return MesEglisesPage(
      eglises: tranche,
      total: toutes.length,
      page: page,
      limite: limite,
      pages: (toutes.length / limite).ceil(),
    );
  }

  // -- Paiements --------------------------------------------------------------------

  static const List<FournisseurPaiement> _fournisseurs = [
    FournisseurPaiement(
      code: 'wave',
      nom: 'Wave',
      pays: ['CI', 'SN'],
      type: 'mobile_money',
      champsRequis: [
        ChampPaiement(nom: 'api_key', label: 'Clé API', secret: true),
        ChampPaiement(nom: 'marchand', label: 'Identifiant marchand', secret: false),
      ],
    ),
    FournisseurPaiement(
      code: 'orange_money',
      nom: 'Orange Money',
      pays: ['CI', 'SN'],
      type: 'mobile_money',
      champsRequis: [
        ChampPaiement(nom: 'api_key', label: 'Clé API', secret: true),
        ChampPaiement(nom: 'marchand', label: 'Code marchand', secret: false),
      ],
    ),
    FournisseurPaiement(
      code: 'mtn_momo',
      nom: 'MTN MoMo',
      pays: ['CI'],
      type: 'mobile_money',
      champsRequis: [
        ChampPaiement(nom: 'api_key', label: 'Clé API', secret: true),
        ChampPaiement(nom: 'abonnement', label: 'Clé d’abonnement', secret: true),
      ],
    ),
    FournisseurPaiement(
      code: 'mpesa',
      nom: 'M-Pesa',
      pays: ['KE'],
      type: 'mobile_money',
      champsRequis: [
        ChampPaiement(nom: 'api_key', label: 'Clé API', secret: true),
      ],
    ),
    FournisseurPaiement(
      code: 'paypal',
      nom: 'PayPal',
      pays: ['INTL'],
      type: 'carte',
      champsRequis: [
        ChampPaiement(nom: 'client_id', label: 'Client ID', secret: false),
        ChampPaiement(nom: 'secret', label: 'Secret', secret: true),
      ],
    ),
    FournisseurPaiement(
      code: 'stripe',
      nom: 'Stripe',
      pays: ['INTL'],
      type: 'carte',
      champsRequis: [
        ChampPaiement(nom: 'cle_publique', label: 'Clé publique', secret: false),
        ChampPaiement(nom: 'cle_secrete', label: 'Clé secrète', secret: true),
      ],
    ),
    FournisseurPaiement(
      code: 'virement',
      nom: 'Virement bancaire',
      pays: ['INTL'],
      type: 'virement',
      champsRequis: [
        ChampPaiement(nom: 'iban', label: 'IBAN', secret: false),
      ],
    ),
    FournisseurPaiement(
      code: 'especes',
      nom: 'Espèces',
      pays: ['*'],
      type: 'especes',
      champsRequis: [],
    ),
  ];

  @override
  Future<List<FournisseurPaiement>> getFournisseursPaiement({String? pays}) async {
    await _latence();
    _requireAuth();
    if (pays == null || pays.isEmpty) return _fournisseurs;
    return _fournisseurs.where((f) => f.disponiblePour(pays)).toList();
  }

  @override
  Future<List<EglisePaiement>> getMesPaiements(String churchId) async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.paiements, (e) => e.id));
  }

  @override
  Future<EglisePaiement> configurerPaiement({
    required String churchId,
    required String fournisseurCode,
    required String pays,
    String? libelle,
    bool? actif,
    required List<Map<String, String>> secrets,
  }) async {
    await _latence();
    _requireAuth();
    final fournisseur = _fournisseurs.firstWhere(
      (f) => f.code == fournisseurCode,
      orElse: () => throw const ApiException('Fournisseur inconnu (démo).'),
    );
    final existant = _data.paiements.indexWhere(
        (p) => p.fournisseurCode == fournisseurCode);
    final config = EglisePaiement(
      id: existant >= 0 ? _data.paiements[existant].id : _nextId('paiement'),
      fournisseurCode: fournisseur.code,
      fournisseurNom: fournisseur.nom,
      type: fournisseur.type,
      pays: pays,
      libelle: libelle,
      apercu: '•••• démo',
      actif: actif ?? true,
      champs: fournisseur.champsRequis
          .map((c) => ChampPaiementConfigure(
                nom: c.nom,
                label: c.label,
                secret: c.secret,
                configure: true,
              ))
          .toList(),
    );
    if (existant >= 0) {
      _data.paiements[existant] = config;
    } else {
      _data.paiements.add(config);
      _tag(config.id);
    }
    return config;
  }

  @override
  Future<void> supprimerPaiement({
    required String churchId,
    required String fournisseurCode,
  }) async {
    await _latence();
    _requireAuth();
    _data.paiements.removeWhere((p) => p.fournisseurCode == fournisseurCode);
  }

  @override
  Future<({bool ok, String message})> testerPaiement({
    required String churchId,
    required String fournisseurCode,
  }) async {
    await _latence();
    _requireAuth();
    // Aucun appel réel en démo : le test est simulé comme indisponible.
    return (
      ok: false,
      message: 'Test désactivé en démo — aucun appel réel au fournisseur.'
    );
  }

  @override
  Future<Map<String, dynamic>> executerPaiement({
    required String fournisseurCode,
    required String type,
    required int montant,
    String devise = 'XOF',
    String? memberId,
    required String successUrl,
    required String errorUrl,
    String? note,
  }) async {
    await _latence();
    _requireAuth();
    // Simulé : la contribution est créée « en attente », sans aucun appel
    // au fournisseur et sans page de paiement (launch_url null).
    final contribution = await createContribution(
      type: type,
      amountFcfa: montant,
      paymentMethod: fournisseurCode,
      memberId: memberId,
      note: note,
    );
    return {
      'contribution': {
        'id': contribution.id,
        'type': contribution.type,
        'amount_fcfa': contribution.amountFcfa,
        'payment_method': contribution.paymentMethod,
        'status': contribution.status,
      },
      'session_id': 'demo-${_nextId('session')}',
      'launch_url': null,
    };
  }

  // -- Rapports et annonces ----------------------------------------------------------

  @override
  Future<RapportConsolide> getRapport() async {
    await _latence();
    _requireAuth();
    if (_church.parentChurchId != null) {
      throw const ApiException(
          'Rapport consolidé réservé à l’église mère (démo).');
    }
    final sousEglises = _data.churches
        .where((e) => e.parentChurchId == _churchId)
        .map((e) {
          final c = _chiffres(e.id);
          return RapportSousEglise(
            egliseId: e.id,
            egliseNom: e.name,
            niveau: 1,
            membresActifs: c.membresActifs,
            nombreContributions: c.nombreContributions,
            totalFcfa: c.totalFcfa,
          );
        })
        .toList();
    final propre = _chiffres(_churchId);
    var totalMembres = propre.membresActifs;
    var totalContributions = propre.nombreContributions;
    var totalFcfa = propre.totalFcfa;
    for (final s in sousEglises) {
      totalMembres += s.membresActifs;
      totalContributions += s.nombreContributions;
      totalFcfa += s.totalFcfa;
    }
    return RapportConsolide(
      eglise: _church,
      propre: propre,
      sousEglises: sousEglises,
      totauxReseau: RapportChiffres(
        membresActifs: totalMembres,
        nombreContributions: totalContributions,
        totalFcfa: totalFcfa,
      ),
    );
  }

  @override
  Future<RapportDetailConsolide> getRapportDetail({
    required String periode,
    String? mois,
  }) async {
    await _latence();
    _requireAuth();
    if (_church.parentChurchId != null) {
      throw const ApiException(
          'Rapport consolidé réservé à l’église mère (démo).');
    }
    final maintenant = DateTime.now();
    final moisAncre = mois ??
        '${maintenant.year}-${maintenant.month.toString().padLeft(2, '0')}';
    final bornes = _bornesPeriode(periode, moisAncre);
    final debut = bornes.debut;
    final fin = bornes.fin;
    final branches = <RapportDetailBranche>[];
    final eglises = [_church, ..._data.churches.where((e) => e.parentChurchId == _churchId)];
    var entrees = 0;
    var depenses = 0;
    var membres = 0;
    final totaux = <String, ContributionTotals>{};
    for (var niveau = 0; niveau < eglises.length; niveau++) {
      final eglise = eglises[niveau];
      final contributions = _confirmedOf(eglise.id)
          .where((c) => _dansPeriode(c.createdAt, debut, fin))
          .toList();
      final depensesBudget =
          _depensesBudget(eglise.id, debut: debut, fin: fin);
      final nombreDepensesBudget =
          _nombreDepensesBudget(eglise.id, debut: debut, fin: fin);
      final totauxBranche = _totaux(contributions,
          depensesBudget: depensesBudget,
          nombreDepensesBudget: nombreDepensesBudget);
      final entreesBranche = contributions
          .where((c) => c.type != 'depense')
          .fold<int>(0, (s, c) => s + c.amountFcfa);
      final depensesBranche = contributions
              .where((c) => c.type == 'depense')
              .fold<int>(0, (s, c) => s + c.amountFcfa) +
          depensesBudget;
      entrees += entreesBranche;
      depenses += depensesBranche;
      membres += _chiffres(eglise.id).membresActifs;
      totauxBranche.forEach((key, value) {
        final precedent = totaux[key];
        totaux[key] = ContributionTotals(
          totalFcfa: (precedent?.totalFcfa ?? 0) + value.totalFcfa,
          nombre: (precedent?.nombre ?? 0) + value.nombre,
        );
      });
      branches.add(RapportDetailBranche(
        egliseId: eglise.id,
        egliseCode: eglise.code,
        egliseNom: eglise.name,
        egliseVille: eglise.city,
        niveau: niveau,
        membresActifs: _chiffres(eglise.id).membresActifs,
        totaux: totauxBranche,
        entreesFcfa: entreesBranche,
        depensesFcfa: depensesBranche,
        soldeFcfa: entreesBranche - depensesBranche,
        transactions: contributions,
      ));
    }
    return RapportDetailConsolide(
      eglise: _church,
      periode: RapportDetailPeriode(
        type: periode,
        debut: debut,
        fin: fin,
        label: bornes.label,
      ),
      branches: branches,
      totaux: totaux,
      entreesFcfa: entrees,
      depensesFcfa: depenses,
      soldeFcfa: entrees - depenses,
      membresActifs: membres,
    );
  }

  @override
  Future<List<Announcement>> getAnnonces() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_visible(_data.annonces, (e) => e.id));
  }

  @override
  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  }) async {
    await _latence();
    _requireAuth();
    final annonce = Announcement(
      id: _nextId('annonce'),
      title: title,
      body: body,
      broadcast: broadcast,
      createdAt: DateTime.now(),
      churchId: _churchId,
      egliseNom: _church.name,
    );
    _data.annonces.add(annonce);
    _tag(annonce.id);
    return annonce;
  }

  @override
  Future<void> deleteAnnonce(String id) async {
    await _latence();
    _requireAuth();
    _data.annonces.removeWhere((e) => e.id == id);
    _itemChurch.remove(id);
  }

  // -- Plateforme --------------------------------------------------------------------

  @override
  Future<ChiffresPlateforme> getPlateforme() async {
    await _latence();
    _requireAuth();
    var membres = 0;
    var contributions = 0;
    var total = 0;
    for (final eglise in _data.churches) {
      final c = _chiffres(eglise.id);
      membres += c.membresActifs;
      contributions += c.nombreContributions;
      total += c.totalFcfa;
    }
    final meres =
        _data.churches.where((e) => e.parentChurchId == null).length;
    return ChiffresPlateforme(
      eglisesMeres: meres,
      branches: _data.churches.length - meres,
      eglisesTotal: _data.churches.length,
      membresActifs: membres,
      nombreContributions: contributions,
      totalContributionsFcfa: total,
      depensesFcfa:
          _data.depenses.fold<int>(0, (s, d) => s + d.montantFcfa),
    );
  }
}
