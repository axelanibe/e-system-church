// Service API factice — DÉMO UNIQUEMENT.
//
// Implémente la même interface que le vrai [ApiService] (`lib/services/`)
// mais ne fait AUCUN appel réseau : tout est en mémoire, sur les données
// fictives de `mock_data.dart` (réseau « Grâce Divine »).
// Utilisé uniquement par `lib/main_demo.dart` via `DemoAppState`.
// L'application réelle (`lib/main.dart`) n'importe jamais ce fichier.

import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/biens.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/enfants.dart';
import '../models/fidele.dart';
import '../models/finances.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
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

  Map<String, ContributionTotals> _totaux(List<Contribution> list) {
    final map = <String, ContributionTotals>{};
    for (final c in list) {
      if (c.status != 'confirme') continue;
      final precedent = map[c.type];
      map[c.type] = ContributionTotals(
        totalFcfa: (precedent?.totalFcfa ?? 0) + c.amountFcfa,
        nombre: (precedent?.nombre ?? 0) + 1,
      );
    }
    return map;
  }

  // -- Authentification -----------------------------------------------------

  @override
  Future<AuthResult> login(
      {required String email, required String password}) async {
    await _latence();
    final mail = email.trim().toLowerCase();
    if (mail == DemoAccounts.adminEmail && password == _adminPassword) {
      const user = AppUser(
        id: 'demo-user-admin',
        fullName: 'Admin Grâce Divine',
        email: DemoAccounts.adminEmail,
        phone: '+225 07 47 00 01',
      );
      final church = _data.plateau;
      _eglises = [Membership(church: _withRole(church, 'admin_eglise'), role: 'admin_eglise')];
      final result = _buildAuth(user, church, 'admin_eglise');
      _applyAuth(result);
      return result;
    }
    if (mail == DemoAccounts.membreEmail && password == _membrePassword) {
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
        'E-mail ou mot de passe incorrect (démo). Utilisez « Entrer dans la démo ».');
  }

  @override
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
    final user = AppUser(
      id: _nextId('user'),
      fullName: adminName,
      email: adminEmail,
      phone: churchPhone,
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
    return const FideleInscriptionResult(
      lie: false,
      message:
          'Demande de liaison envoyée : un responsable doit la valider (démo).',
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
    return List.unmodifiable(_data.demandesLiaison
        .where((d) => d.status == 'en_attente'));
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
    return List.unmodifiable(_data.annonces);
  }

  @override
  Future<List<Culte>> getMesCultes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.cultes);
  }

  @override
  Future<List<Presence>> getMesPresences() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.presences
        .where((p) => p.memberId == 'demo-m-001'));
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
      arbre: _nodeOf(_data.plateau),
      demandesRattachement: List.unmodifiable(_data.rattachementsRecus
          .where((r) => r.status == 'en_attente')),
    );
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
    return eglise;
  }

  // -- Rattachements et transferts -------------------------------------------

  @override
  Future<RattachementsResult> getRattachements() async {
    await _latence();
    _requireAuth();
    return RattachementsResult(
      recues: List.unmodifiable(_data.rattachementsRecus),
      emises: List.unmodifiable(_data.rattachementsEmis),
    );
  }

  @override
  Future<Rattachement> requestRattachement({required String parentCode}) async {
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
      historique: list.where((t) => t.status != 'en_attente').toList(),
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
    String? department,
    String? cellGroup,
    String? status,
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
      department: department,
      cellGroup: cellGroup,
      status: status ?? 'actif',
      createdAt: DateTime.now(),
    );
    _data.membersOf(_churchId).add(membre);
    return membre;
  }

  // -- Membres (complément) --------------------------------------------------

  @override
  Future<List<Famille>> getFamilles() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.familles);
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
    return List.unmodifiable(
        _data.statuts.where((s) => s.memberId == memberId));
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
    // Le statut « membre » de l'historique correspond à « actif » ici.
    final nouveauStatut =
        statut == 'membre' ? 'actif' : statut;
    final maj = Member(
      id: membre.id,
      matricule: membre.matricule,
      fullName: membre.fullName,
      phone: membre.phone,
      email: membre.email,
      birthDate: membre.birthDate,
      department: membre.department,
      cellGroup: membre.cellGroup,
      status: nouveauStatut,
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
    return bapteme;
  }

  @override
  Future<List<LienParentEnfant>> getLiensParentEnfant(
      {String? enfantMemberId, String? parentMemberId}) async {
    await _latence();
    _requireAuth();
    var list = _data.liens;
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
    return item;
  }

  @override
  Future<List<Departement>> getDepartements() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.departements);
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
    return departement;
  }

  @override
  Future<List<Cellule>> getCellules() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.cellules);
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
    return cellule;
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
    return List.unmodifiable(_data.culteTypes);
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
    return type;
  }

  @override
  Future<List<Culte>> getCultes() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.cultes);
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
    return culte;
  }

  @override
  Future<List<OrdreCulteItem>> getOrdreCulte(String culteId) async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(
        _data.ordreCulte.where((o) => o.culteId == culteId));
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
    return item;
  }

  @override
  Future<List<EvenementSpecial>> getEvenementsSpeciaux({String? type}) async {
    await _latence();
    _requireAuth();
    var list = _data.evenements;
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
    return evenement;
  }

  // -- Présences ---------------------------------------------------------------

  @override
  Future<List<Presence>> getPresences(
      {String? culteId, String? eventId, String? memberId}) async {
    await _latence();
    _requireAuth();
    var list = _data.presences;
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
    return poste;
  }

  @override
  Future<List<Budget>> getBudgets({int? annee}) async {
    await _latence();
    _requireAuth();
    var list = _data.budgets;
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
    return budget;
  }

  @override
  Future<List<Depense>> getDepenses({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.depenses;
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
    return depense;
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
    final parMois = <Map<String, dynamic>>[
      {
        'mois': '2026-11',
        'entrees': _confirmedOf(_churchId)
            .where((c) => c.type != 'depense')
            .fold<int>(0, (s, c) => s + c.amountFcfa),
        'depenses': _data.depenses
            .fold<int>(0, (s, d) => s + d.montantFcfa),
      },
    ];
    final parPoste = _data.postes
        .map((p) => {
              'poste': p.nom,
              'montant': _data.depenses
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
      totaux: _totaux(_data.contributionsOf(_churchId)),
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

  // -- Communication ---------------------------------------------------------

  @override
  Future<List<DemandePriere>> getDemandesPriere({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.prieres;
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
    return demande;
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
    return List.unmodifiable(_data.messages);
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
    return message;
  }

  // -- Suivi pastoral ----------------------------------------------------------

  @override
  Future<List<ParcoursNouveau>> getParcoursNouveaux({String? etape}) async {
    await _latence();
    _requireAuth();
    var list = _data.parcours;
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
    return visite;
  }

  @override
  Future<List<Accompagnement>> getAccompagnements(
      {String? type, String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.accompagnements;
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
    return accompagnement;
  }

  // -- Serviteurs --------------------------------------------------------------

  @override
  Future<List<Serviteur>> getServiteurs({String? departementId}) async {
    await _latence();
    _requireAuth();
    var list = _data.serviteurs;
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
    return serviteur;
  }

  @override
  Future<List<PlanningServiteur>> getPlanningServiteurs() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.planning);
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
    return item;
  }

  // -- Enfants et jeunesse ------------------------------------------------------

  @override
  Future<List<ClasseEnfant>> getClassesEnfants() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.classesEnfants);
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
    return classe;
  }

  @override
  Future<List<AutorisationSortie>> getAutorisationsSorties(
      {String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.autorisations;
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
    return List.unmodifiable(_data.activitesJeunesse);
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
    return activite;
  }

  // -- Médias et enseignements ---------------------------------------------------

  @override
  Future<List<Predication>> getPredications() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.predications);
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
    return predication;
  }

  @override
  Future<List<PlanLecture>> getPlansLecture() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.plansLecture);
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
    return plan;
  }

  @override
  Future<List<Livre>> getLivres() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.livres);
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
    return livre;
  }

  @override
  Future<List<PretLivre>> getPretsLivres({String? statut}) async {
    await _latence();
    _requireAuth();
    var list = _data.pretsLivres;
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
    return List.unmodifiable(_data.salles);
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
    return salle;
  }

  @override
  Future<List<ReservationSalle>> getReservationsSalles({String? salleId}) async {
    await _latence();
    _requireAuth();
    var list = _data.reservationsSalles;
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
    return reservation;
  }

  @override
  Future<List<Materiel>> getMateriel({String? etat}) async {
    await _latence();
    _requireAuth();
    var list = _data.materiel;
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
    return item;
  }

  @override
  Future<List<MaintenanceMateriel>> getMaintenanceMateriel(
      {String? materielId}) async {
    await _latence();
    _requireAuth();
    var list = _data.maintenances;
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
    return maintenance;
  }

  // -- Statistiques et export ------------------------------------------------------

  @override
  Future<StatsGlobales> getStatsGlobales() async {
    await _latence();
    _requireAuth();
    final membres = _data.membersOf(_churchId);
    final recettes = _confirmedOf(_churchId)
        .where((c) => c.type != 'depense')
        .fold<int>(0, (s, c) => s + c.amountFcfa);
    final depenses = _data.depenses.fold<int>(0, (s, d) => s + d.montantFcfa);
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
      baptemes: _data.baptemes.length,
      cultesMois: _data.cultes.length,
      presencesMois: _data.presences.length,
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

  // -- Administration --------------------------------------------------------------

  @override
  Future<EgliseParametres> getParametres() async {
    await _latence();
    _requireAuth();
    return _data.parametres;
  }

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
    final p = _data.parametres;
    _data.parametres = EgliseParametres(
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
    return _data.parametres;
  }

  @override
  Future<List<RoleEglise>> getRoles() async {
    await _latence();
    _requireAuth();
    return List.unmodifiable(_data.roles);
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
    return List.unmodifiable(_data.audit);
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
      name: eglise.name,
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
    _role = 'admin_eglise';
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
    return List.unmodifiable(_data.paiements);
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
    final branches = <RapportDetailBranche>[];
    final eglises = [_church, ..._data.churches.where((e) => e.parentChurchId == _churchId)];
    var entrees = 0;
    var depenses = 0;
    var membres = 0;
    final totaux = <String, ContributionTotals>{};
    for (var niveau = 0; niveau < eglises.length; niveau++) {
      final eglise = eglises[niveau];
      final contributions = _confirmedOf(eglise.id);
      final totauxBranche = _totaux(contributions);
      final entreesBranche = contributions
          .where((c) => c.type != 'depense')
          .fold<int>(0, (s, c) => s + c.amountFcfa);
      final depensesBranche = contributions
          .where((c) => c.type == 'depense')
          .fold<int>(0, (s, c) => s + c.amountFcfa);
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
      periode: const RapportDetailPeriode(
        type: 'mois',
        debut: '2026-11-01',
        fin: '2026-12-01',
        label: 'Novembre 2026',
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
    return List.unmodifiable(_data.annonces);
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
    return annonce;
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
