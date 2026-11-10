import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/member.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';
import '../models/transfert.dart';
import 'api_service.dart';

/// Client HTTP de l'API e-System Church (`server/` : Fastify + JWT bearer).
class HttpApiService implements ApiService {
  final String baseUrl;
  String? _token;

  HttpApiService({required this.baseUrl, String? token}) : _token = token;

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Appel HTTP générique : renvoie le JSON décodé, ou lève [ApiException].
  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: query?.isEmpty ?? true ? null : query);
    http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http
              .get(uri, headers: _headers)
              .timeout(const Duration(seconds: 20));
        case 'POST':
          res = await http
              .post(uri,
                  headers: _headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          res = await http
              .patch(uri,
                  headers: _headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        default:
          throw const ApiException('Méthode HTTP inconnue.');
      }
    } on TimeoutException {
      throw const ApiException(
          'Le serveur ne répond pas. Vérifiez l’URL de l’API dans Réglages.');
    } on SocketException {
      throw const ApiException(
          'Impossible de joindre le serveur. Vérifiez l’URL de l’API dans Réglages.');
    }
    final Map<String, dynamic> data = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw ApiException(
      (data['message'] as String?) ?? 'Erreur ${res.statusCode}.',
      res.statusCode,
    );
  }

  @override
  Future<AuthResult> login(
      {required String email, required String password}) async {
    final data = await _call('POST', '/auth/login', body: {
      'email': email,
      'password': password,
      'channel': 'mobile',
    });
    final result = AuthResult.fromJson(data);
    _token = result.token;
    return result;
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
    final data = await _call('POST', '/auth/register', body: {
      'eglise': {
        'name': churchName,
        'city': city,
        if (churchPhone != null) 'phone': churchPhone,
        if (churchEmail != null) 'email': churchEmail,
        if (parentCode != null) 'parent_code': parentCode,
      },
      'admin': {
        'full_name': adminName,
        'email': adminEmail,
        'password': password,
      },
      'channel': 'mobile',
    });
    final result = AuthResult.fromJson(data);
    _token = result.token;
    return result;
  }

  @override
  Future<MeResult> me() async =>
      MeResult.fromJson(await _call('GET', '/moi/eglise'));

  @override
  Future<TreeResult> getTree() async {
    final data = await _call('GET', '/eglises/arbre');
    return TreeResult(
      arbre: ChurchNode.fromJson(data['arbre'] as Map<String, dynamic>),
      demandesRattachement: (data['demandes_rattachement'] as List<dynamic>)
          .map((e) => Rattachement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Church> createSubChurch({
    required String name,
    required String city,
    String? phone,
    String? email,
  }) async {
    final data = await _call('POST', '/eglises', body: {
      'name': name,
      'city': city,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    });
    return Church.fromJson(data);
  }

  @override
  Future<RattachementsResult> getRattachements() async {
    final data = await _call('GET', '/rattachements');
    return RattachementsResult(
      recues: (data['recues'] as List<dynamic>)
          .map((e) => Rattachement.fromJson(e as Map<String, dynamic>))
          .toList(),
      emises: (data['emises'] as List<dynamic>)
          .map((e) => Rattachement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Rattachement> requestRattachement({required String parentCode}) async {
    final data = await _call('POST', '/rattachements',
        body: {'parent_code': parentCode});
    // La réponse ne contient pas les champs d'église : on la complète.
    return Rattachement(
      id: data['id'] as String,
      status: data['status'] as String,
      egliseId: data['church_id'] as String,
      egliseCode: '',
      egliseNom: 'Mon église',
      createdAt: DateTime.tryParse(data['created_at'] as String? ?? ''),
    );
  }

  @override
  Future<void> decideRattachement(String id, {required bool accept}) async {
    await _call(
        'POST', '/rattachements/$id/${accept ? 'accepter' : 'refuser'}');
  }

  @override
  Future<TransfertsResult> getTransferts() async {
    final data = await _call('GET', '/transferts');
    List<TransfertMembre> list(String key) =>
        (data[key] as List<dynamic>)
            .map((e) => TransfertMembre.fromJson(e as Map<String, dynamic>))
            .toList();
    return TransfertsResult(
      aTraiter: list('a_traiter'),
      emises: list('emises'),
      recues: list('recues'),
      historique: list('historique'),
    );
  }

  @override
  Future<TransfertMembre> requestTransfert({
    required String matricule,
    required String destinationCode,
    String? motif,
  }) async {
    final data = await _call('POST', '/transferts', body: {
      'matricule': matricule,
      'eglise_arrivee_code': destinationCode,
      if (motif != null && motif.isNotEmpty) 'motif': motif,
    });
    // La réponse ne contient pas les noms des églises : on relit la demande.
    final id = data['id'] as String;
    final result = await getTransferts();
    final found = [...result.emises, ...result.aTraiter]
        .where((t) => t.id == id)
        .firstOrNull;
    if (found != null) return found;
    throw const ApiException('Transfert créé, mais relecture impossible.');
  }

  @override
  Future<void> decideTransfert(String id, {required bool accept}) async {
    await _call(
        'POST', '/transferts/$id/${accept ? 'accepter' : 'refuser'}');
  }

  @override
  Future<void> annulerTransfert(String id) async {
    await _call('POST', '/transferts/$id/annuler');
  }

  @override
  Future<MemberPage> getMembers(
      {String? q, String? department, String? status}) async {
    final data = await _call('GET', '/membres', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (department != null) 'department': department,
      if (status != null) 'status': status,
    });
    return MemberPage(
      total: (data['total'] as num).toInt(),
      membres: (data['membres'] as List<dynamic>)
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Member> getMember(String id) async =>
      Member.fromJson(await _call('GET', '/membres/$id'));

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
    final data = await _call('POST', '/membres', body: {
      'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (birthDate != null) 'birth_date': birthDate,
      if (department != null) 'department': department,
      if (cellGroup != null) 'cell_group': cellGroup,
      if (status != null) 'status': status,
    });
    return Member.fromJson(data);
  }

  @override
  Future<ContributionPage> getContributions(
      {String? type, String? status}) async {
    final data = await _call('GET', '/contributions', query: {
      if (type != null) 'type': type,
      if (status != null) 'status': status,
    });
    final totaux = <String, ContributionTotals>{};
    (data['totaux'] as Map<String, dynamic>).forEach((key, value) {
      totaux[key] =
          ContributionTotals.fromJson(value as Map<String, dynamic>);
    });
    return ContributionPage(
      contributions: (data['contributions'] as List<dynamic>)
          .map((e) => Contribution.fromJson(e as Map<String, dynamic>))
          .toList(),
      totaux: totaux,
    );
  }

  @override
  Future<Contribution> getReceipt(String id) async {
    final data = await _call('GET', '/contributions/$id');
    return Contribution.fromJson(data['recu'] as Map<String, dynamic>);
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
    final data = await _call('POST', '/contributions', body: {
      'type': type,
      'amount_fcfa': amountFcfa,
      'payment_method': paymentMethod,
      if (paymentRef != null) 'payment_ref': paymentRef,
      if (memberId != null) 'member_id': memberId,
      if (note != null) 'note': note,
    });
    return Contribution.fromJson(data);
  }

  @override
  Future<Contribution> setContributionStatus(String id, String status) async {
    final data = await _call('PATCH', '/contributions/$id/statut',
        body: {'status': status});
    // La réponse est partielle : on relit le reçu complet.
    if (data.containsKey('recu')) {
      return Contribution.fromJson(data['recu'] as Map<String, dynamic>);
    }
    return getReceipt(id);
  }

  @override
  Future<RapportConsolide> getRapport() async =>
      RapportConsolide.fromJson(await _call('GET', '/rapports/consolide'));

  @override
  Future<List<Announcement>> getAnnonces() async {
    final data = await _call('GET', '/annonces');
    return (data['annonces'] as List<dynamic>)
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  }) async {
    final data = await _call('POST', '/annonces', body: {
      'title': title,
      'body': body,
      'broadcast': broadcast,
    });
    return Announcement.fromJson(data);
  }
}
