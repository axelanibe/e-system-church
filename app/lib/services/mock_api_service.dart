import 'dart:convert';

import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/member.dart';
import '../models/plateforme.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';
import '../models/transfert.dart';
import 'api_service.dart';
import 'mock_data.dart';

/// Implémentation en mémoire de [ApiService] (mode démo) : mêmes règles que
/// l'API réelle (isolation par église, rôles, anti-cycle), données fictives
/// « Grâce Divine ». Les données vivent le temps de la session : basculer
/// de mode les réinitialise.
class MockApiService implements ApiService {
  // -- État en mémoire (copies profondes des données de démo) ---------------
  late final List<Map<String, dynamic>> _churches;
  late final Map<String, List<Map<String, dynamic>>> _members;
  late final Map<String, List<Map<String, dynamic>>> _contributions;
  late final List<Map<String, dynamic>> _annonces;
  late final List<Map<String, dynamic>> _rattachements;
  late final List<Map<String, dynamic>> _transferts;

  String? _token;
  AppUser? _user;
  String? _churchId;
  String? _role;
  int _seq = 100;

  MockApiService() {
    _churches = (jsonDecode(jsonEncode(demoChurches)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    _members = (jsonDecode(jsonEncode(demoMembers)) as Map<String, dynamic>)
        .map((k, v) => MapEntry(
            k, (v as List<dynamic>).cast<Map<String, dynamic>>()));
    _contributions =
        (jsonDecode(jsonEncode(demoContributions)) as Map<String, dynamic>)
            .map((k, v) => MapEntry(
                k, (v as List<dynamic>).cast<Map<String, dynamic>>()));
    _annonces = (jsonDecode(jsonEncode(demoAnnonces)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    _rattachements =
        (jsonDecode(jsonEncode(demoRattachements)) as List<dynamic>)
            .cast<Map<String, dynamic>>();
    _transferts =
        (jsonDecode(jsonEncode(demoTransferts)) as List<dynamic>)
            .cast<Map<String, dynamic>>();
  }

  // -- Aides -----------------------------------------------------------------
  Future<void> _delay() => Future.delayed(const Duration(milliseconds: 300));

  String _nextId(String prefix) => 'demo-$prefix-${_seq++}';

  void _requireAuth() {
    if (_token == null || _churchId == null) {
      throw const ApiException('Non connecté.');
    }
  }

  void _requireRole(List<String> roles) {
    _requireAuth();
    if (!roles.contains(_role)) {
      throw ApiException(
          'Action non autorisée pour le rôle « ${_roleLabel(_role)} ».', 403);
    }
  }

  static String _roleLabel(String? role) {
    switch (role) {
      case 'admin_eglise':
        return 'Admin d’église';
      case 'tresorier':
        return 'Trésorier';
      case 'responsable_culte':
        return 'Responsable de culte';
      case 'membre':
        return 'Membre';
      default:
        return role ?? '—';
    }
  }

  Map<String, dynamic>? _churchById(String id) {
    for (final c in _churches) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  Map<String, dynamic>? _churchByCode(String code) {
    for (final c in _churches) {
      if (c['code'] == code) return c;
    }
    return null;
  }

  Church _toChurch(Map<String, dynamic> map, {String? role}) =>
      Church.fromJson({...map, if (role != null) 'role': role});

  List<String> _childrenIds(String id) => _churches
      .where((c) => c['parent_church_id'] == id)
      .map((c) => c['id'] as String)
      .toList();

  /// Tous les descendants de [id] (lui compris).
  Set<String> _subtreeIds(String id) {
    final result = <String>{id};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final child in _childrenIds(current)) {
        if (result.add(child)) queue.add(child);
      }
    }
    return result;
  }

  /// Tous les descendants de [id] avec leur niveau (0 = [id] lui-même,
  /// 1 = sous-église directe, 2 = antenne d'une sous-église, …),
  /// triés par niveau puis par nom.
  List<({String id, int niveau})> _subtreeWithNiveau(String id) {
    final result = <({String id, int niveau})>[];
    final queue = <({String id, int niveau})>[(id: id, niveau: 0)];
    final seen = <String>{};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!seen.add(current.id)) continue;
      result.add(current);
      for (final child in _childrenIds(current.id)) {
        queue.add((id: child, niveau: current.niveau + 1));
      }
    }
    result.sort((a, b) {
      if (a.niveau != b.niveau) return a.niveau.compareTo(b.niveau);
      final na = _churchById(a.id)!['name'] as String;
      final nb = _churchById(b.id)!['name'] as String;
      return na.compareTo(nb);
    });
    return result;
  }

  /// Ancêtres de [id] (mères, grand-mères…), sans [id] lui-même.
  List<String> _ancestorIds(String id) {
    final result = <String>[];
    var current = _churchById(id);
    while (current != null && current['parent_church_id'] != null) {
      final parentId = current['parent_church_id'] as String;
      result.add(parentId);
      current = _churchById(parentId);
    }
    return result;
  }

  ChurchNode _buildNode(String id) {
    final map = _churchById(id)!;
    final members =
        _members[id]?.where((m) => m['status'] == 'actif').length ?? 0;
    return ChurchNode(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      parentChurchId: map['parent_church_id'] as String?,
      city: map['city'] as String?,
      status: map['status'] as String,
      membresActifs: members,
      children: _childrenIds(id).map(_buildNode).toList(),
    );
  }

  RapportChiffres _chiffres(String churchId) {
    final membresActifs =
        _members[churchId]?.where((m) => m['status'] == 'actif').length ?? 0;
    final confirmes = (_contributions[churchId] ?? []).where((c) =>
        (c['type'] == 'dime' ||
            c['type'] == 'offrande' ||
            c['type'] == 'don') &&
        c['status'] == 'confirme');
    return RapportChiffres(
      membresActifs: membresActifs,
      nombreContributions: confirmes.length,
      totalFcfa: confirmes.fold<int>(
          0, (sum, c) => sum + (c['amount_fcfa'] as int)),
    );
  }

  AuthResult _authResult(AppUser user, String churchId, String role) {
    final church = _toChurch(_churchById(churchId)!, role: role);
    return AuthResult(
      token: _token!,
      user: user,
      church: church,
      eglises: [Membership(church: church, role: role)],
    );
  }

  // -- Authentification ------------------------------------------------------
  static const _demoUsers = [
    {
      'email': 'admin@gracedivine.ci',
      'password': 'demo1234',
      'full_name': 'Axel N’Guessan',
      'church_id': 'demo-plateau',
      'role': 'admin_eglise',
    },
    {
      'email': 'admin@yopougon.ci',
      'password': 'demo1234',
      'full_name': 'Yao Kouassi',
      'church_id': 'demo-yopougon',
      'role': 'admin_eglise',
    },
    {
      'email': 'tresorier@gracedivine.ci',
      'password': 'demo1234',
      'full_name': 'Awa Koné',
      'church_id': 'demo-plateau',
      'role': 'tresorier',
    },
    {
      'email': 'membre@gracedivine.ci',
      'password': 'demo1234',
      'full_name': 'Koffi Yao',
      'church_id': 'demo-plateau',
      'role': 'membre',
    },
    {
      'email': 'admin@esystem.ci',
      'password': 'demo1234',
      'full_name': 'Admin Plateforme',
      'church_id': 'demo-plateforme',
      'role': 'super_admin',
    },
  ];

  @override
  Future<AuthResult> login(
      {required String email, required String password}) async {
    await _delay();
    final found = _demoUsers.where(
        (u) => u['email'] == email && u['password'] == password);
    if (found.isEmpty) {
      throw const ApiException('E-mail ou mot de passe incorrect.');
    }
    final u = found.first;
    _token = 'demo-token-${u['church_id']}';
    _churchId = u['church_id'] as String;
    _role = u['role'] as String;
    _user = AppUser(
      id: 'demo-user-${u['church_id']}',
      fullName: u['full_name'] as String,
      email: u['email'] as String,
    );
    return _authResult(_user!, _churchId!, _role!);
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
    await _delay();
    if (_demoUsers.any((u) => u['email'] == adminEmail)) {
      throw const ApiException('Cet e-mail est déjà utilisé.', 409);
    }
    Map<String, dynamic>? parent;
    if (parentCode != null && parentCode.isNotEmpty) {
      parent = _churchByCode(parentCode);
      if (parent == null) {
        throw const ApiException(
            'Code d’invitation de l’église mère invalide.');
      }
    }
    final code = 'ESC-D${(_seq++).toString().padLeft(5, '0')}';
    final churchId = _nextId('church');
    _churches.add({
      'id': churchId,
      'code': code,
      'name': churchName,
      'parent_church_id': null,
      'city': city,
      'status': 'active',
    });
    _members[churchId] = [];
    _contributions[churchId] = [];
    Map<String, dynamic>? rattachement;
    if (parent != null) {
      rattachement = {
        'id': _nextId('ratt'),
        'church_id': churchId,
        'parent_church_id': parent['id'],
        'status': 'en_attente',
        'created_at': DateTime.now().toIso8601String(),
        'eglise_code': code,
        'eglise_nom': churchName,
        'eglise_ville': city,
      };
      _rattachements.add(rattachement);
    }
    _token = 'demo-token-$churchId';
    _churchId = churchId;
    _role = 'admin_eglise';
    _user = AppUser(
        id: 'demo-user-$churchId', fullName: adminName, email: adminEmail);
    return AuthResult(
      token: _token!,
      user: _user!,
      church: _toChurch(_churchById(churchId)!, role: 'admin_eglise'),
      eglises: [
        Membership(
            church: _toChurch(_churchById(churchId)!,
                role: 'admin_eglise'),
            role: 'admin_eglise')
      ],
      rattachement: rattachement == null
          ? null
          : {'id': rattachement['id'], 'status': rattachement['status']},
    );
  }

  @override
  Future<MeResult> me() async {
    await _delay();
    _requireAuth();
    return MeResult(
      user: _user!,
      church: _toChurch(_churchById(_churchId!)!),
      role: _role!,
      eglises: [
        Membership(
            church: _toChurch(_churchById(_churchId!)!, role: _role!),
            role: _role!)
      ],
    );
  }

  // -- Églises et arborescence ----------------------------------------------
  @override
  Future<TreeResult> getTree() async {
    await _delay();
    _requireAuth();
    final demandes = _rattachements
        .where((r) =>
            r['parent_church_id'] == _churchId && r['status'] == 'en_attente')
        .map((r) => Rattachement.fromJson(r))
        .toList();
    return TreeResult(arbre: _buildNode(_churchId!), demandesRattachement: demandes);
  }

  @override
  Future<Church> createSubChurch({
    required String name,
    required String city,
    String? phone,
    String? email,
  }) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final code = 'ESC-D${(_seq++).toString().padLeft(5, '0')}';
    final id = _nextId('church');
    final map = {
      'id': id,
      'code': code,
      'name': name,
      'parent_church_id': _churchId,
      'city': city,
      'status': 'active',
    };
    _churches.add(map);
    _members[id] = [];
    _contributions[id] = [];
    return _toChurch(map);
  }

  // -- Rattachements ---------------------------------------------------------
  @override
  Future<RattachementsResult> getRattachements() async {
    await _delay();
    _requireRole(['admin_eglise']);
    return RattachementsResult(
      recues: _rattachements
          .where((r) => r['parent_church_id'] == _churchId)
          .map((r) => Rattachement.fromJson(r))
          .toList(),
      emises: _rattachements
          .where((r) => r['church_id'] == _churchId)
          .map((r) => Rattachement.fromJson(r))
          .toList(),
    );
  }

  @override
  Future<Rattachement> requestRattachement({required String parentCode}) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final parent = _churchByCode(parentCode);
    if (parent == null) {
      throw const ApiException('Église mère introuvable ou inactive.');
    }
    if (parent['id'] == _churchId) {
      throw const ApiException('Une église ne peut pas se rattacher à elle-même.');
    }
    if (_subtreeIds(_churchId!).contains(parent['id'])) {
      throw const ApiException(
          'Rattachement impossible : cette église est déjà dans votre descendance.');
    }
    final exists = _rattachements.any((r) =>
        r['church_id'] == _churchId &&
        r['parent_church_id'] == parent['id'] &&
        r['status'] == 'en_attente');
    if (exists) {
      throw const ApiException(
          'Une demande est déjà en attente vers cette église mère.', 409);
    }
    final record = {
      'id': _nextId('ratt'),
      'church_id': _churchId,
      'parent_church_id': parent['id'],
      'status': 'en_attente',
      'created_at': DateTime.now().toIso8601String(),
      'eglise_code': _churchById(_churchId!)!['code'],
      'eglise_nom': _churchById(_churchId!)!['name'],
      'eglise_ville': _churchById(_churchId!)!['city'],
    };
    _rattachements.add(record);
    return Rattachement.fromJson(record);
  }

  @override
  Future<void> decideRattachement(String id, {required bool accept}) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final record =
        _rattachements.where((r) => r['id'] == id).firstOrNull;
    if (record == null) {
      throw const ApiException('Demande introuvable.', 404);
    }
    if (record['parent_church_id'] != _churchId) {
      throw const ApiException(
          'Seule l’église mère sollicitée peut décider.', 403);
    }
    if (record['status'] != 'en_attente') {
      throw const ApiException('Cette demande a déjà été traitée.', 409);
    }
    if (accept) {
      final church = _churchById(record['church_id'] as String);
      if (church != null) {
        church['parent_church_id'] = record['parent_church_id'];
      }
      record['status'] = 'acceptee';
    } else {
      record['status'] = 'refusee';
    }
  }

  // -- Transferts de membre entre branches ----------------------------------
  // Mêmes règles que l'API réelle : demande par matricule, validation par
  // les deux pasteurs (départ puis arrivée), historique gardé. À la double
  // acceptation, le membre change d'église et reçoit un nouveau matricule.
  @override
  Future<TransfertsResult> getTransferts() async {
    await _delay();
    _requireRole(['admin_eglise', 'responsable_culte']);
    final rows =
        _transferts.where((t) =>
            t['eglise_depart_id'] == _churchId ||
            t['eglise_arrivee_id'] == _churchId).toList();
    rows.sort((a, b) => (b['created_at'] as String)
        .compareTo(a['created_at'] as String));
    final list = rows.map((t) => TransfertMembre.fromJson(t)).toList();
    return TransfertsResult(
      aTraiter: list.where((t) => t.aTraiterPour(_churchId!)).toList(),
      emises: list.where((t) => t.egliseDepartId == _churchId).toList(),
      recues: list.where((t) => t.egliseArriveeId == _churchId).toList(),
      historique:
          list.where((t) => t.status != 'en_attente').toList(),
    );
  }

  @override
  Future<TransfertMembre> requestTransfert({
    required String matricule,
    required String destinationCode,
    String? motif,
  }) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final member = (_members[_churchId] ?? [])
        .where((m) => m['matricule'] == matricule)
        .firstOrNull;
    if (member == null) {
      throw const ApiException(
          'Aucun membre de votre église ne porte ce matricule.', 404);
    }
    if (member['status'] == 'inactif') {
      throw const ApiException(
          'Un membre inactif ne peut pas être transféré.');
    }
    final dest = _churchByCode(destinationCode);
    if (dest == null || dest['status'] != 'active') {
      throw const ApiException(
          'Église d’arrivée introuvable ou inactive.');
    }
    if (dest['id'] == _churchId) {
      throw const ApiException('Le membre est déjà dans cette église.');
    }
    final exists = _transferts.any((t) =>
        t['membre_id'] == member['id'] && t['status'] == 'en_attente');
    if (exists) {
      throw const ApiException(
          'Une demande de transfert est déjà en attente pour ce membre.',
          409);
    }
    final source = _churchById(_churchId!)!;
    final now = DateTime.now().toIso8601String();
    final record = <String, dynamic>{
      'id': _nextId('transfert'),
      'membre_id': member['id'],
      'membre_nom': member['full_name'],
      'ancien_matricule': member['matricule'],
      'nouveau_matricule': null,
      'eglise_depart_id': _churchId,
      'eglise_arrivee_id': dest['id'],
      'motif': motif,
      'status': 'en_attente',
      'decision_depart': 'en_attente',
      'decision_arrivee': 'en_attente',
      'decide_depart_at': null,
      'decide_arrivee_at': null,
      'created_at': now,
      'updated_at': now,
      'depart_code': source['code'],
      'depart_nom': source['name'],
      'depart_ville': source['city'],
      'arrivee_code': dest['code'],
      'arrivee_nom': dest['name'],
      'arrivee_ville': dest['city'],
    };
    _transferts.add(record);
    return TransfertMembre.fromJson(record);
  }

  @override
  Future<void> decideTransfert(String id, {required bool accept}) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final record = _transferts.where((t) => t['id'] == id).firstOrNull;
    if (record == null) {
      throw const ApiException('Transfert introuvable.', 404);
    }
    final cote = record['eglise_depart_id'] == _churchId
        ? 'depart'
        : record['eglise_arrivee_id'] == _churchId
            ? 'arrivee'
            : null;
    if (cote == null) {
      throw const ApiException(
          'Seules les deux églises concernées peuvent décider.', 403);
    }
    if (record['status'] != 'en_attente') {
      throw const ApiException('Ce transfert a déjà été traité.', 409);
    }
    if (cote == 'depart' && record['decision_depart'] != 'en_attente') {
      throw const ApiException('Votre église a déjà décidé.', 409);
    }
    if (cote == 'arrivee') {
      if (record['decision_depart'] != 'accepte') {
        throw const ApiException(
            'En attente de la décision de l’église de départ.', 409);
      }
      if (record['decision_arrivee'] != 'en_attente') {
        throw const ApiException('Votre église a déjà décidé.', 409);
      }
    }
    final now = DateTime.now().toIso8601String();
    if (cote == 'depart') {
      record['decision_depart'] = accept ? 'accepte' : 'refuse';
      record['decide_depart_at'] = now;
    } else {
      record['decision_arrivee'] = accept ? 'accepte' : 'refuse';
      record['decide_arrivee_at'] = now;
    }
    record['updated_at'] = now;
    if (!accept) {
      record['status'] = 'refuse';
      return;
    }
    if (cote != 'arrivee') return;
    // Double acceptation : le membre déménage avec un nouveau matricule.
    final destMembers = _members[record['eglise_arrivee_id'] as String] ??= [];
    var n = destMembers.length + 1;
    var matricule = 'M-${n.toString().padLeft(4, '0')}';
    while (destMembers.any((m) => m['matricule'] == matricule)) {
      n++;
      matricule = 'M-${n.toString().padLeft(4, '0')}';
    }
    final sourceMembers = _members[record['eglise_depart_id'] as String] ?? [];
    final memberIndex =
        sourceMembers.indexWhere((m) => m['id'] == record['membre_id']);
    if (memberIndex < 0) {
      throw const ApiException(
          'Le membre n’est plus dans l’église de départ.');
    }
    final moved = sourceMembers.removeAt(memberIndex);
    moved['matricule'] = matricule;
    destMembers.add(moved);
    record['nouveau_matricule'] = matricule;
    record['status'] = 'accepte';
  }

  @override
  Future<void> annulerTransfert(String id) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final record = _transferts.where((t) => t['id'] == id).firstOrNull;
    if (record == null) {
      throw const ApiException('Transfert introuvable.', 404);
    }
    if (record['eglise_depart_id'] != _churchId) {
      throw const ApiException(
          'Seule l’église de départ peut annuler la demande.', 403);
    }
    if (record['status'] != 'en_attente') {
      throw const ApiException(
          'Seule une demande en attente peut être annulée.', 409);
    }
    record['status'] = 'annule';
    record['updated_at'] = DateTime.now().toIso8601String();
  }

  // -- Membres ---------------------------------------------------------------
  @override
  Future<MemberPage> getMembers(
      {String? q, String? department, String? status}) async {
    await _delay();
    _requireAuth();
    var list = List<Map<String, dynamic>>.from(_members[_churchId] ?? []);
    if (q != null && q.isNotEmpty) {
      final needle = q.toLowerCase();
      list = list.where((m) {
        final name = (m['full_name'] as String).toLowerCase();
        final mat = (m['matricule'] as String).toLowerCase();
        return name.contains(needle) || mat.contains(needle);
      }).toList();
    }
    if (department != null) {
      list = list.where((m) => m['department'] == department).toList();
    }
    if (status != null) {
      list = list.where((m) => m['status'] == status).toList();
    }
    list.sort((a, b) =>
        (a['full_name'] as String).compareTo(b['full_name'] as String));
    return MemberPage(
      total: list.length,
      membres: list.map((m) => Member.fromJson(m)).toList(),
    );
  }

  @override
  Future<Member> getMember(String id) async {
    await _delay();
    _requireAuth();
    final found =
        (_members[_churchId] ?? []).where((m) => m['id'] == id).firstOrNull;
    if (found == null) {
      throw const ApiException('Membre introuvable.', 404);
    }
    return Member.fromJson(found);
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
    await _delay();
    _requireRole(['admin_eglise', 'responsable_culte']);
    final list = _members[_churchId!] ??= [];
    var n = list.length + 1;
    var matricule = 'M-${n.toString().padLeft(4, '0')}';
    while (list.any((m) => m['matricule'] == matricule)) {
      n++;
      matricule = 'M-${n.toString().padLeft(4, '0')}';
    }
    final map = {
      'id': _nextId('member'),
      'matricule': matricule,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'birth_date': birthDate,
      'department': department,
      'cell_group': cellGroup,
      'status': status ?? 'actif',
      'created_at': DateTime.now().toIso8601String(),
    };
    list.add(map);
    return Member.fromJson(map);
  }

  // -- Finances --------------------------------------------------------------
  @override
  Future<ContributionPage> getContributions(
      {String? type, String? status}) async {
    await _delay();
    _requireRole(['admin_eglise', 'tresorier', 'responsable_culte']);
    var list =
        List<Map<String, dynamic>>.from(_contributions[_churchId] ?? []);
    if (type != null) list = list.where((c) => c['type'] == type).toList();
    if (status != null) {
      list = list.where((c) => c['status'] == status).toList();
    }
    list.sort((a, b) => (b['created_at'] as String)
        .compareTo(a['created_at'] as String));
    final totaux = <String, ContributionTotals>{};
    for (final c in _contributions[_churchId] ?? []) {
      if (c['status'] != 'confirme') continue;
      final t = c['type'] as String;
      final prev = totaux[t];
      totaux[t] = ContributionTotals(
        totalFcfa: (prev?.totalFcfa ?? 0) + (c['amount_fcfa'] as int),
        nombre: (prev?.nombre ?? 0) + 1,
      );
    }
    return ContributionPage(
      contributions:
          list.map((c) => Contribution.fromJson(c)).toList(),
      totaux: totaux,
    );
  }

  @override
  Future<Contribution> getReceipt(String id) async {
    await _delay();
    _requireRole(['admin_eglise', 'tresorier', 'responsable_culte']);
    final found = (_contributions[_churchId] ?? [])
        .where((c) => c['id'] == id)
        .firstOrNull;
    if (found == null) {
      throw const ApiException('Contribution introuvable.', 404);
    }
    final church = _churchById(_churchId!)!;
    return Contribution.fromJson({
      ...found,
      'eglise_nom': church['name'],
      'eglise_code': church['code'],
    });
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
    await _delay();
    _requireRole(['admin_eglise', 'tresorier']);
    String? membreNom;
    String? membreMatricule;
    if (memberId != null) {
      final member = (_members[_churchId] ?? [])
          .where((m) => m['id'] == memberId)
          .firstOrNull;
      if (member == null) {
        throw const ApiException(
            'Ce membre n’appartient pas à votre église.');
      }
      membreNom = member['full_name'] as String;
      membreMatricule = member['matricule'] as String;
    }
    final map = {
      'id': _nextId('contrib'),
      'type': type,
      'amount_fcfa': amountFcfa,
      'payment_method': paymentMethod,
      'payment_ref': paymentRef,
      'status': 'en_attente',
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'member_id': memberId,
      'membre_nom': membreNom,
      'membre_matricule': membreMatricule,
    };
    (_contributions[_churchId!] ??= []).add(map);
    return Contribution.fromJson(map);
  }

  @override
  Future<Contribution> setContributionStatus(String id, String status) async {
    await _delay();
    _requireRole(['admin_eglise', 'tresorier']);
    final found = (_contributions[_churchId] ?? [])
        .where((c) => c['id'] == id)
        .firstOrNull;
    if (found == null) {
      throw const ApiException('Contribution introuvable.', 404);
    }
    if (found['status'] != 'en_attente') {
      throw const ApiException(
          'Contribution introuvable, ou déjà confirmée / annulée.', 409);
    }
    found['status'] = status;
    return getReceipt(id);
  }

  // -- Rapports et annonces --------------------------------------------------
  @override
  Future<RapportConsolide> getRapport() async {
    await _delay();
    _requireRole(['admin_eglise']);
    final church = _toChurch(_churchById(_churchId!)!);
    // Tous les descendants, récursif (petites-filles comprises), comme
    // la vue v_rapports_consolides côté API réelle.
    final sousEglises = _subtreeWithNiveau(_churchId!)
        .where((e) => e.id != _churchId)
        .map((e) {
      final child = _churchById(e.id)!;
      final chiffres = _chiffres(e.id);
      return RapportSousEglise(
        egliseId: e.id,
        egliseNom: child['name'] as String,
        niveau: e.niveau,
        membresActifs: chiffres.membresActifs,
        nombreContributions: chiffres.nombreContributions,
        totalFcfa: chiffres.totalFcfa,
      );
    }).toList();
    final propre = _chiffres(_churchId!);
    return RapportConsolide(
      eglise: church,
      propre: propre,
      sousEglises: sousEglises,
      totauxReseau: RapportChiffres(
        membresActifs: propre.membresActifs +
            sousEglises.fold<int>(0, (s, e) => s + e.membresActifs),
        nombreContributions: propre.nombreContributions +
            sousEglises.fold<int>(0, (s, e) => s + e.nombreContributions),
        totalFcfa: propre.totalFcfa +
            sousEglises.fold<int>(0, (s, e) => s + e.totalFcfa),
      ),
    );
  }

  /// Bornes [début, fin[ d'une période, ancrée sur le mois AAAA-MM.
  /// Même règle que l'API réelle (`bornesPeriode` côté serveur).
  static ({DateTime debut, DateTime fin, String label})
      _bornesDetail(String periode, String moisAncre) {
    const nomsMois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    final annee = int.parse(moisAncre.substring(0, 4));
    final mois = int.parse(moisAncre.substring(5, 7));
    if (periode == 'annee') {
      return (
        debut: DateTime.utc(annee, 1, 1),
        fin: DateTime.utc(annee + 1, 1, 1),
        label: 'Année $annee',
      );
    }
    if (periode == 'trimestre') {
      final trimestre = (mois - 1) ~/ 3 + 1;
      final debutMois = (trimestre - 1) * 3 + 1;
      return (
        debut: DateTime.utc(annee, debutMois, 1),
        fin: DateTime.utc(annee, debutMois + 3, 1),
        label: '${trimestre == 1 ? '1er' : '${trimestre}e'} trimestre $annee',
      );
    }
    return (
      debut: DateTime.utc(annee, mois, 1),
      fin: DateTime.utc(annee, mois + 1, 1),
      label:
          '${nomsMois[mois - 1][0].toUpperCase()}${nomsMois[mois - 1].substring(1)} $annee',
    );
  }

  @override
  Future<RapportDetailConsolide> getRapportDetail({
    required String periode,
    String? mois,
  }) async {
    await _delay();
    _requireRole(['admin_eglise']);
    if (periode != 'mois' && periode != 'trimestre' && periode != 'annee') {
      throw const ApiException('Période invalide (mois, trimestre ou année).');
    }
    final ancre = mois ??
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    final bornes = _bornesDetail(periode, ancre);
    // Périmètre strict : mon église + tous ses descendants, récursif
    // (petites-filles comprises, avec leur niveau), comme l'API réelle.
    final ids = _subtreeWithNiveau(_churchId!);
    final totaux = <String, ContributionTotals>{};
    for (final t in ['dime', 'offrande', 'don', 'depense']) {
      totaux[t] = const ContributionTotals(totalFcfa: 0, nombre: 0);
    }
    var entrees = 0;
    var depenses = 0;
    var membresActifs = 0;
    final branches = <RapportDetailBranche>[];
    for (final entry in ids) {
      final id = entry.id;
      final church = _churchById(id)!;
      final confirmes = (_contributions[id] ?? []).where((c) {
        if (c['status'] != 'confirme') return false;
        final date = DateTime.tryParse(c['created_at'] as String);
        if (date == null) return false;
        return !date.isBefore(bornes.debut) && date.isBefore(bornes.fin);
      }).toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      final totauxBranche = <String, ContributionTotals>{};
      for (final t in ['dime', 'offrande', 'don', 'depense']) {
        totauxBranche[t] = const ContributionTotals(totalFcfa: 0, nombre: 0);
      }
      for (final c in confirmes) {
        final t = c['type'] as String;
        final prev = totauxBranche[t]!;
        totauxBranche[t] = ContributionTotals(
          totalFcfa: prev.totalFcfa + (c['amount_fcfa'] as int),
          nombre: prev.nombre + 1,
        );
        final prevReseau = totaux[t]!;
        totaux[t] = ContributionTotals(
          totalFcfa: prevReseau.totalFcfa + (c['amount_fcfa'] as int),
          nombre: prevReseau.nombre + 1,
        );
      }
      final entreesBranche = (totauxBranche['dime']?.totalFcfa ?? 0) +
          (totauxBranche['offrande']?.totalFcfa ?? 0) +
          (totauxBranche['don']?.totalFcfa ?? 0);
      final depensesBranche = totauxBranche['depense']?.totalFcfa ?? 0;
      entrees += entreesBranche;
      depenses += depensesBranche;
      final actifs =
          _members[id]?.where((m) => m['status'] == 'actif').length ?? 0;
      membresActifs += actifs;
      branches.add(RapportDetailBranche(
        egliseId: id,
        egliseCode: church['code'] as String,
        egliseNom: church['name'] as String,
        egliseVille: church['city'] as String?,
        niveau: entry.niveau,
        membresActifs: actifs,
        totaux: totauxBranche,
        entreesFcfa: entreesBranche,
        depensesFcfa: depensesBranche,
        soldeFcfa: entreesBranche - depensesBranche,
        transactions:
            confirmes.map((c) => Contribution.fromJson(c)).toList(),
      ));
    }
    return RapportDetailConsolide(
      eglise: _toChurch(_churchById(_churchId!)!),
      periode: RapportDetailPeriode(
        type: periode,
        debut: bornes.debut.toIso8601String().substring(0, 10),
        fin: bornes.fin.toIso8601String().substring(0, 10),
        label: bornes.label,
      ),
      // Comme l'API réelle : mon église d'abord, puis les branches par
      // niveau, puis par nom.
      branches: branches
        ..sort((a, b) {
          if (a.egliseId == _churchId) return -1;
          if (b.egliseId == _churchId) return 1;
          if (a.niveau != b.niveau) return a.niveau.compareTo(b.niveau);
          return a.egliseNom.compareTo(b.egliseNom);
        }),
      totaux: totaux,
      entreesFcfa: entrees,
      depensesFcfa: depenses,
      soldeFcfa: entrees - depenses,
      membresActifs: membresActifs,
    );
  }

  @override
  Future<ChiffresPlateforme> getPlateforme() async {
    await _delay();
    _requireRole(['super_admin']);
    // Chiffres globaux seulement, sur toutes les vraies églises du réseau.
    // La pseudo-église de session `demo-plateforme` n'est pas une vraie
    // église : elle est exclue des comptes.
    final eglises = _churches.where((c) => c['id'] != 'demo-plateforme');
    final meres =
        eglises.where((c) => c['parent_church_id'] == null).length;
    final branches =
        eglises.where((c) => c['parent_church_id'] != null).length;
    var membresActifs = 0;
    var nombreContributions = 0;
    var totalContributions = 0;
    var depenses = 0;
    for (final c in eglises) {
      final id = c['id'] as String;
      membresActifs +=
          _members[id]?.where((m) => m['status'] == 'actif').length ?? 0;
      for (final contribution in _contributions[id] ?? []) {
        if (contribution['status'] != 'confirme') continue;
        final montant = contribution['amount_fcfa'] as int;
        if (contribution['type'] == 'depense') {
          depenses += montant;
        } else {
          nombreContributions++;
          totalContributions += montant;
        }
      }
    }
    return ChiffresPlateforme(
      eglisesMeres: meres,
      branches: branches,
      eglisesTotal: eglises.length,
      membresActifs: membresActifs,
      nombreContributions: nombreContributions,
      totalContributionsFcfa: totalContributions,
      depensesFcfa: depenses,
    );
  }

  @override
  Future<List<Announcement>> getAnnonces() async {
    await _delay();
    _requireAuth();
    final ancestors = _ancestorIds(_churchId!);
    final list = _annonces.where((a) {
      if (a['church_id'] == _churchId) return true;
      return ancestors.contains(a['church_id']) && a['broadcast'] == true;
    }).toList();
    list.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));
    return list.map((a) => Announcement.fromJson(a)).toList();
  }

  @override
  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  }) async {
    await _delay();
    _requireRole(['admin_eglise']);
    final map = {
      'id': _nextId('annonce'),
      'title': title,
      'body': body,
      'broadcast': broadcast,
      'created_at': DateTime.now().toIso8601String(),
      'church_id': _churchId,
      'eglise_nom': _churchById(_churchId!)!['name'],
    };
    _annonces.add(map);
    return Announcement.fromJson(map);
  }
}
