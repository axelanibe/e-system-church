import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/attestation.dart';
import '../models/annexe.dart';
import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/biens.dart';
import '../models/campagne.dart';
import '../models/church.dart';
import '../models/code_tutelle.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/checkin_enfant.dart';
import '../models/enfants.dart';
import '../models/fidele.dart';
import '../models/finances.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../models/module_eglise.dart';
import '../models/paiements.dart';
import '../models/parametres.dart';
import '../models/pastoral.dart';
import '../models/presences.dart';
import '../models/prieres.dart';
import '../models/profil.dart';
import '../models/plateforme.dart';
import '../models/transfert.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';
import '../models/serviteurs.dart';
import '../models/stats.dart';
import 'api_service.dart';

/// Client HTTP de l'API e-System Church (`server/` : Fastify + JWT bearer).
/// Seule implémentation de [ApiService] : aucune donnée de démonstration,
/// tout vient de l'API réelle (listes vides quand l'église n'a rien saisi).
class HttpApiService implements ApiService {
  final String baseUrl;
  String? _token;

  HttpApiService({required this.baseUrl, String? token}) : _token = token;

  void setToken(String? token) => _token = token;

  /// En-têtes : `Content-Type: application/json` seulement quand un corps
  /// est envoyé. Un POST sans corps (ex. accepter ou refuser un
  /// rattachement) avec ce content-type arrive corps vide au serveur, et
  /// Fastify le rejette (« Body cannot be empty when content-type is set
  /// to 'application/json' »).
  Map<String, String> _headers({required bool withBody}) => <String, String>{
        if (withBody) 'Content-Type': 'application/json',
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
    final headers = _headers(withBody: body != null);
    http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        case 'POST':
          res = await http
              .post(uri,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          res = await http
              .patch(uri,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        case 'DELETE':
          res = await http
              .delete(uri, headers: headers)
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

  /// Liste générique : `GET` + `data['items']`.
  List<T> _items<T>(
      Map<String, dynamic> data, T Function(Map<String, dynamic>) fromJson) =>
      (data['items'] as List<dynamic>? ?? [])
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();

  /// Paramètres de requête : on ne garde que les valeurs non nulles.
  Map<String, String> _q(Map<String, dynamic> params) => {
        for (final e in params.entries)
          if (e.value != null) e.key: e.value.toString(),
      };

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
    String? logoBase64,
    String? logoFilename,
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
    if (logoBase64 != null) {
      // Logo choisi à l'inscription : téléversé après la création,
      // comme dans Mon église (même route, même limite de 2 Mo).
      await uploadLogo(
        churchId: result.church.id,
        base64: logoBase64,
        filename: logoFilename,
      );
    }
    return result;
  }

  @override
  Future<MeResult> me() async =>
      MeResult.fromJson(await _call('GET', '/moi/eglise'));

  // -- Mot de passe et accès fidèle (modules 15-16) -------------------------
  @override
  Future<bool> forgotPassword({required String email}) async {
    final data = await _call('POST', '/auth/mot-de-passe-oublie', body: {
      'email': email,
    });
    return data['email_envoye'] as bool? ?? false;
  }

  @override
  Future<void> resetPassword(
      {required String token, required String password}) async {
    await _call('POST', '/auth/reinitialiser-mot-de-passe', body: {
      'token': token,
      'mot_de_passe': password,
    });
  }

  @override
  Future<void> initPassword(
      {required String token, required String password}) async {
    await _call('POST', '/auth/initialiser-mot-de-passe', body: {
      'token': token,
      'mot_de_passe': password,
    });
  }

  @override
  Future<void> changePassword(
      {required String ancien, required String nouveau}) async {
    await _call('POST', '/auth/changer-mot-de-passe', body: {
      'ancien': ancien,
      'nouveau': nouveau,
    });
  }

  @override
  Future<String> inviter({
    required String email,
    required String role,
    String? memberId,
    String? fullName,
  }) async {
    final data = await _call('POST', '/auth/inviter', body: {
      'email': email,
      'role': role,
      if (memberId != null) 'member_id': memberId,
      if (fullName != null) 'full_name': fullName,
    });
    return data['lien_invitation'] as String;
  }

  @override
  Future<String> adminResetLink({required String email}) async {
    final data = await _call(
        'POST', '/auth/admin/lien-reinitialisation',
        body: {'email': email});
    return data['lien'] as String;
  }

  @override
  Future<FideleInscriptionResult> registerFidele({
    required String email,
    required String password,
    required String matricule,
    String? codeFidele,
  }) async {
    final data = await _call('POST', '/auth/inscription-fidele', body: {
      'email': email,
      'mot_de_passe': password,
      'matricule': matricule,
      if (codeFidele != null && codeFidele.isNotEmpty)
        'code_fidele': codeFidele,
      'channel': 'mobile',
    });
    final result = FideleInscriptionResult.fromJson(data);
    if (result.auth != null) _token = result.auth!.token;
    return result;
  }

  @override
  Future<FideleInscriptionResult> registerMembreParCode({
    required String nomPrenom,
    required String email,
    required String telephone,
    required String password,
    required String codeEglise,
    String? department,
    String? fonction,
  }) async {
    final data = await _call('POST', '/auth/inscription-par-code', body: {
      'nom_prenom': nomPrenom,
      'email': email,
      'telephone': telephone,
      'mot_de_passe': password,
      'code_eglise': codeEglise,
      if (department != null) 'department': department,
      if (fonction != null) 'fonction': fonction,
      'channel': 'mobile',
    });
    final result = FideleInscriptionResult.fromJson(data);
    if (result.auth != null) _token = result.auth!.token;
    return result;
  }

  @override
  Future<FideleProfil> getMoi() async =>
      FideleProfil.fromJson(await _call('GET', '/moi'));

  @override
  Future<List<DemandeLiaison>> getDemandesLiaison() async {
    final data = await _call('GET', '/membres/demandes-liaison');
    return (data['demandes'] as List<dynamic>? ?? [])
        .map((e) => DemandeLiaison.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> decideDemandeLiaison(String id, {required bool accept}) async {
    await _call(
        'POST', '/membres/demandes-liaison/$id/${accept ? 'valider' : 'refuser'}');
  }

  @override
  Future<List<Announcement>> getMesAnnonces() async {
    final data = await _call('GET', '/moi/annonces');
    return (data['annonces'] as List<dynamic>? ?? [])
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Culte>> getMesCultes() async {
    final data = await _call('GET', '/moi/cultes');
    return (data['cultes'] as List<dynamic>? ?? [])
        .map((e) => Culte.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Presence>> getMesPresences() async {
    final data = await _call('GET', '/moi/presences');
    return (data['presences'] as List<dynamic>? ?? [])
        .map((e) => Presence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Contribution>> getMesContributions() async {
    final data = await _call('GET', '/moi/contributions');
    return (data['contributions'] as List<dynamic>? ?? [])
        .map((e) => Contribution.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Attestation>> getMesAttestations() async {
    final data = await _call('GET', '/moi/attestations');
    return (data['attestations'] as List<dynamic>? ?? [])
        .map((e) => Attestation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<MaCarte> getMaCarte() async =>
      MaCarte.fromJson(await _call('GET', '/moi/carte'));

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
  Future<Rattachement> requestRattachement({
    required String parentCode,
    String? codeTutelle,
  }) async {
    final data = await _call(
      'POST',
      '/rattachements',
      body: codeTutelle != null
          ? {'code_tutelle': codeTutelle}
          : {'parent_code': parentCode},
    );
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

  // -- Annexes et codes de tutelle (migration 009) -------------------------
  @override
  Future<List<Annexe>> getAnnexes({String? q}) async {
    final data = await _call(
      'GET',
      '/annexes',
      query: q == null || q.isEmpty ? null : {'q': q},
    );
    return (data['annexes'] as List<dynamic>)
        .map((e) => Annexe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AnnexeDetail> getAnnexeDetail(String id) async =>
      AnnexeDetail.fromJson(await _call('GET', '/annexes/$id'));

  @override
  Future<List<CodeTutelle>> getCodesTutelle() async {
    final data = await _call('GET', '/codes-tutelle');
    return (data['codes'] as List<dynamic>)
        .map((e) => CodeTutelle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<CodeTutelle> createCodeTutelle() async =>
      CodeTutelle.fromJson(await _call('POST', '/codes-tutelle'));

  @override
  Future<void> annulerCodeTutelle(String id) async {
    await _call('POST', '/codes-tutelle/$id/annuler');
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
    String? fonction,
    String? poste,
    String? cellGroup,
    String? status,
  }) async {
    final data = await _call('POST', '/membres', body: {
      'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (birthDate != null) 'birth_date': birthDate,
      if (department != null) 'department': department,
      if (fonction != null) 'fonction': fonction,
      if (poste != null) 'poste': poste,
      if (cellGroup != null) 'cell_group': cellGroup,
      if (status != null) 'status': status,
    });
    return Member.fromJson(data);
  }

  @override
  Future<Member> updateMember(String id,
      {required String fullName,
      String? phone,
      String? email,
      String? birthDate,
      String? department,
      String? fonction,
      String? poste,
      String? cellGroup,
      String? status}) async {
    final data = await _call('PATCH', '/membres/$id', body: {
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'birth_date': birthDate,
      'department': department,
      'fonction': fonction,
      'poste': poste,
      'cell_group': cellGroup,
      'status': status,
    });
    return Member.fromJson(data);
  }

  @override
  Future<void> deleteMember(String id) async {
    await _call('DELETE', '/membres/$id');
  }

  // -- Membres (complément, module 1) ----------------------------------------
  @override
  Future<List<Famille>> getFamilles() async =>
      _items(await _call('GET', '/familles'), Famille.fromJson);

  @override
  Future<Famille> createFamille({
    required String nom,
    String? chefFamilleId,
    String? adresse,
    String? telephone,
  }) async =>
      Famille.fromJson(await _call('POST', '/familles', body: {
        'nom': nom,
        if (chefFamilleId != null) 'chef_famille_id': chefFamilleId,
        if (adresse != null) 'adresse': adresse,
        if (telephone != null) 'telephone': telephone,
      }));

  @override
  Future<void> deleteFamille(String id) async {
    await _call('DELETE', '/familles/$id');
  }

  @override
  Future<List<MembreStatut>> getMembreStatuts(String memberId) async =>
      _items(
          await _call('GET', '/membre-statuts',
              query: {'member_id': memberId}),
          MembreStatut.fromJson);

  @override
  Future<MembreStatut> changerStatutMembre(String memberId,
      {required String statut, String? motif}) async {
    // POST /membres/:id/statut ne renvoie que { membre_id, statut,
    // statut_simple } : on relit l'historique (trié par date desc).
    await _call('POST', '/membres/$memberId/statut', body: {
      'statut': statut,
      if (motif != null) 'motif': motif,
    });
    final statuts = await getMembreStatuts(memberId);
    if (statuts.isEmpty) {
      throw const ApiException('Statut introuvable après le changement.');
    }
    return statuts.first;
  }

  @override
  Future<List<Bapteme>> getBaptemes({String? memberId}) async => _items(
      await _call('GET', '/baptemes', query: _q({'member_id': memberId})),
      Bapteme.fromJson);

  @override
  Future<Bapteme> createBapteme({
    required String memberId,
    required String dateBapteme,
    String? lieu,
    String? pasteur,
    String? certificatNumero,
  }) async =>
      Bapteme.fromJson(await _call('POST', '/baptemes', body: {
        'member_id': memberId,
        'date_bapteme': dateBapteme,
        if (lieu != null) 'lieu': lieu,
        if (pasteur != null) 'pasteur': pasteur,
        if (certificatNumero != null) 'certificat_numero': certificatNumero,
      }));

  @override
  Future<List<LienParentEnfant>> getLiensParentEnfant(
      {String? enfantMemberId, String? parentMemberId}) async =>
      _items(
          await _call('GET', '/liens-parent-enfant',
              query: _q({
                'enfant_member_id': enfantMemberId,
                'parent_member_id': parentMemberId,
              })),
          LienParentEnfant.fromJson);

  @override
  Future<LienParentEnfant> createLienParentEnfant({
    required String parentMemberId,
    required String enfantMemberId,
    required String lien,
  }) async =>
      LienParentEnfant.fromJson(
          await _call('POST', '/liens-parent-enfant', body: {
        'parent_member_id': parentMemberId,
        'enfant_member_id': enfantMemberId,
        'lien': lien,
      }));

  @override
  Future<List<Departement>> getDepartements() async =>
      _items(await _call('GET', '/departements'), Departement.fromJson);

  @override
  Future<Departement> createDepartement({
    required String nom,
    String? description,
    String? responsableMemberId,
  }) async =>
      Departement.fromJson(await _call('POST', '/departements', body: {
        'nom': nom,
        if (description != null) 'description': description,
        if (responsableMemberId != null)
          'responsable_member_id': responsableMemberId,
      }));

  @override
  Future<void> deleteDepartement(String id) async {
    await _call('DELETE', '/departements/$id');
  }

  @override
  Future<Departement> updateDepartement(String id,
          {required String nom}) async =>
      Departement.fromJson(
          await _call('PATCH', '/departements/$id', body: {'nom': nom}));

  @override
  Future<List<Fonction>> getFonctions() async =>
      _items(await _call('GET', '/fonctions'), Fonction.fromJson);

  @override
  Future<Fonction> createFonction({required String nom}) async =>
      Fonction.fromJson(
          await _call('POST', '/fonctions', body: {'nom': nom}));

  @override
  Future<Fonction> updateFonction(String id, {required String nom}) async =>
      Fonction.fromJson(
          await _call('PATCH', '/fonctions/$id', body: {'nom': nom}));

  @override
  Future<void> deleteFonction(String id) async {
    await _call('DELETE', '/fonctions/$id');
  }

  @override
  Future<List<Poste>> getPostes() async =>
      _items(await _call('GET', '/postes'), Poste.fromJson);

  @override
  Future<Poste> createPoste({required String nom}) async =>
      Poste.fromJson(await _call('POST', '/postes', body: {'nom': nom}));

  @override
  Future<Poste> updatePoste(String id, {required String nom}) async =>
      Poste.fromJson(
          await _call('PATCH', '/postes/$id', body: {'nom': nom}));

  @override
  Future<void> deletePoste(String id) async {
    await _call('DELETE', '/postes/$id');
  }

  @override
  Future<List<Cellule>> getCellules() async =>
      _items(await _call('GET', '/cellules'), Cellule.fromJson);

  @override
  Future<Cellule> createCellule({
    required String nom,
    String? quartier,
    String? responsableMemberId,
    String? jourReunion,
    String? heureReunion,
  }) async =>
      Cellule.fromJson(await _call('POST', '/cellules', body: {
        'nom': nom,
        if (quartier != null) 'quartier': quartier,
        if (responsableMemberId != null)
          'responsable_member_id': responsableMemberId,
        if (jourReunion != null) 'jour_reunion': jourReunion,
        if (heureReunion != null) 'heure_reunion': heureReunion,
      }));

  @override
  Future<void> deleteCellule(String id) async {
    await _call('DELETE', '/cellules/$id');
  }

  @override
  Future<Map<String, dynamic>> getMembreComplet(String memberId) async =>
      await _call('GET', '/membres/$memberId/complet');

  // -- Cultes et programmes (module 2) ---------------------------------------
  @override
  Future<List<CulteType>> getCulteTypes() async =>
      _items(await _call('GET', '/culte-types'), CulteType.fromJson);

  @override
  Future<CulteType> createCulteType({
    required String nom,
    int? jourSemaine,
    String? heureDebut,
    int? dureeMinutes,
    String? lieu,
  }) async =>
      CulteType.fromJson(await _call('POST', '/culte-types', body: {
        'nom': nom,
        if (jourSemaine != null) 'jour_semaine': jourSemaine,
        if (heureDebut != null) 'heure_debut': heureDebut,
        if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
        if (lieu != null) 'lieu': lieu,
      }));

  @override
  Future<List<Culte>> getCultes() async =>
      _items(await _call('GET', '/cultes'), Culte.fromJson);

  @override
  Future<Culte> createCulte({
    String? culteTypeId,
    required String titre,
    required String dateHeure,
    String? lieu,
    String? orateur,
    String? theme,
  }) async =>
      Culte.fromJson(await _call('POST', '/cultes', body: {
        if (culteTypeId != null) 'culte_type_id': culteTypeId,
        'titre': titre,
        'date_heure': dateHeure,
        if (lieu != null) 'lieu': lieu,
        if (orateur != null) 'orateur': orateur,
        if (theme != null) 'theme': theme,
      }));

  @override
  Future<void> deleteCulte(String id) async {
    await _call('DELETE', '/cultes/$id');
  }

  @override
  Future<List<OrdreCulteItem>> getOrdreCulte(String culteId) async => _items(
      await _call('GET', '/ordre-culte', query: {'culte_id': culteId}),
      OrdreCulteItem.fromJson);

  @override
  Future<OrdreCulteItem> createOrdreCulteItem({
    required String culteId,
    required String titre,
    int ordre = 0,
    String? description,
    String? intervenant,
    int? dureeMinutes,
  }) async =>
      OrdreCulteItem.fromJson(await _call('POST', '/ordre-culte', body: {
        'culte_id': culteId,
        'titre': titre,
        'ordre': ordre,
        if (description != null) 'description': description,
        if (intervenant != null) 'intervenant': intervenant,
        if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
      }));

  @override
  Future<List<EvenementSpecial>> getEvenementsSpeciaux({String? type}) async =>
      _items(
          await _call('GET', '/evenements-speciaux',
              query: _q({'type': type})),
          EvenementSpecial.fromJson);

  @override
  Future<EvenementSpecial> createEvenementSpecial({
    required String type,
    required String titre,
    required String dateDebut,
    String? dateFin,
    String? description,
    String? lieu,
    String? responsable,
  }) async =>
      EvenementSpecial.fromJson(
          await _call('POST', '/evenements-speciaux', body: {
        'type': type,
        'titre': titre,
        'date_debut': dateDebut,
        if (dateFin != null) 'date_fin': dateFin,
        if (description != null) 'description': description,
        if (lieu != null) 'lieu': lieu,
        if (responsable != null) 'responsable': responsable,
      }));

  // -- Présences (module 3) --------------------------------------------------
  @override
  Future<List<Presence>> getPresences(
      {String? culteId, String? eventId, String? memberId}) async =>
      _items(
          await _call('GET', '/presences',
              query: _q({
                'culte_id': culteId,
                'event_id': eventId,
                'member_id': memberId,
              })),
          Presence.fromJson);

  @override
  Future<Presence> pointerPresence({
    String? matricule,
    String? memberId,
    String? culteId,
    String? eventId,
    String statut = 'present',
    String mode = 'scan_qr',
  }) async =>
      Presence.fromJson(await _call('POST', '/presences/pointer', body: {
        if (matricule != null) 'matricule': matricule,
        if (memberId != null) 'member_id': memberId,
        if (culteId != null) 'culte_id': culteId,
        if (eventId != null) 'event_id': eventId,
        'statut': statut,
        'mode': mode,
      }));

  @override
  Future<PresenceStats> getPresenceStats({String? from, String? to}) async =>
      PresenceStats.fromJson(await _call('GET', '/presences/stats',
          query: _q({'from': from, 'to': to})));

  // -- Finances (module 4) ---------------------------------------------------
  @override
  Future<List<PosteBudgetaire>> getPostesBudgetaires(
          {String? categorie}) async =>
      _items(
          await _call('GET', '/postes-budgetaires',
              query: _q({'categorie': categorie})),
          PosteBudgetaire.fromJson);

  @override
  Future<PosteBudgetaire> createPosteBudgetaire({
    required String nom,
    required String categorie,
    String? description,
  }) async =>
      PosteBudgetaire.fromJson(
          await _call('POST', '/postes-budgetaires', body: {
        'nom': nom,
        'categorie': categorie,
        if (description != null) 'description': description,
      }));

  @override
  Future<void> deletePosteBudgetaire(String id) async {
    await _call('DELETE', '/postes-budgetaires/$id');
  }

  @override
  Future<List<Budget>> getBudgets({int? annee}) async => _items(
      await _call('GET', '/budgets', query: _q({'annee': annee})),
      Budget.fromJson);

  @override
  Future<Budget> createBudget({
    required String posteId,
    required int annee,
    required int montantPrevu,
  }) async =>
      Budget.fromJson(await _call('POST', '/budgets', body: {
        'poste_id': posteId,
        'annee': annee,
        'montant_prevu': montantPrevu,
      }));

  @override
  Future<void> deleteBudget(String id) async {
    await _call('DELETE', '/budgets/$id');
  }

  @override
  Future<List<Depense>> getDepenses({String? statut}) async => _items(
      await _call('GET', '/depenses', query: _q({'statut': statut})),
      Depense.fromJson);

  @override
  Future<Depense> createDepense({
    String? posteId,
    required int montantFcfa,
    required String motif,
    String? justificatifRef,
    String? dateDepense,
  }) async =>
      Depense.fromJson(await _call('POST', '/depenses', body: {
        if (posteId != null) 'poste_id': posteId,
        'montant_fcfa': montantFcfa,
        'motif': motif,
        if (justificatifRef != null) 'justificatif_ref': justificatifRef,
        if (dateDepense != null) 'date_depense': dateDepense,
      }));

  @override
  Future<void> deleteDepense(String id) async {
    await _call('DELETE', '/depenses/$id');
  }

  @override
  Future<Depense> setDepenseStatut(String id, String statut) async {
    // PATCH /depenses/:id/statut ne renvoie qu'un résumé : on relit la
    // dépense complète.
    await _call('PATCH', '/depenses/$id/statut', body: {'statut': statut});
    return Depense.fromJson(await _call('GET', '/depenses/$id'));
  }

  @override
  Future<List<CaisseMouvement>> getCaisseMouvements({String? type}) async =>
      _items(
          await _call('GET', '/caisse-mouvements',
              query: _q({'type': type})),
          CaisseMouvement.fromJson);

  @override
  Future<CaisseMouvement> createCaisseMouvement({
    required String type,
    required int montantFcfa,
    required String motif,
    String? reference,
  }) async =>
      CaisseMouvement.fromJson(
          await _call('POST', '/caisse-mouvements', body: {
        'type': type,
        'montant_fcfa': montantFcfa,
        'motif': motif,
        if (reference != null) 'reference': reference,
      }));

  @override
  Future<CaisseSolde> getCaisseSolde() async =>
      CaisseSolde.fromJson(await _call('GET', '/finances/caisse'));

  @override
  Future<RapportFinancier> getRapportFinancier({int? annee}) async =>
      RapportFinancier.fromJson(await _call('GET', '/finances/rapport',
          query: _q({'annee': annee})));

  // -- Contributions (existant) ----------------------------------------------
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
    String? campagneId,
    String? note,
  }) async {
    final data = await _call('POST', '/contributions', body: {
      'type': type,
      'amount_fcfa': amountFcfa,
      'payment_method': paymentMethod,
      if (paymentRef != null) 'payment_ref': paymentRef,
      if (memberId != null) 'member_id': memberId,
      if (campagneId != null) 'campagne_id': campagneId,
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

  // -- Campagnes de collecte (US2) ------------------------------------------
  @override
  Future<List<Campagne>> getCampagnes() async {
    final data = await _call('GET', '/campagnes');
    return (data['campagnes'] as List<dynamic>? ?? [])
        .map((e) => Campagne.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -- Attestations annuelles de dons (US3) ----------------------------------
  @override
  Future<List<Attestation>> getAttestations({int? annee}) async {
    final data = await _call('GET', '/attestations',
        query: _q({'annee': annee}));
    return (data['attestations'] as List<dynamic>? ?? [])
        .map((e) => Attestation.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final data = await _call('POST', '/campagnes', body: {
      'nom': nom,
      'objectif_fcfa': objectifFcfa,
      'date_debut': dateDebut,
      'date_fin': dateFin,
      'statut': statut,
      'visible_membres': visibleMembres,
    });
    return Campagne.fromJson(data);
  }

  @override
  Future<Campagne> setCampagneStatut(String id, String statut) async {
    final data = await _call('PATCH', '/campagnes/$id', body: {'statut': statut});
    return Campagne.fromJson(data);
  }

  @override
  Future<void> cloturerCampagne(String id) async {
    await _call('PATCH', '/campagnes/$id/cloturer');
  }

  @override
  Future<Contribution> affecterContributionCampagne(
      String id, String? campagneId) async {
    await _call('PATCH', '/contributions/$id/campagne',
        body: {'campagne_id': campagneId});
    // La réponse est partielle : on relit le reçu complet.
    return getReceipt(id);
  }

  @override
  Future<List<Attestation>> genererAttestations({required int annee}) async {
    final data =
        await _call('POST', '/attestations/generer', body: {'annee': annee});
    return (data['creees'] as List<dynamic>? ?? [])
        .map((e) => Attestation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Attestation> corrigerAttestation(String id,
      {required String motif}) async {
    final data = await _call('POST', '/attestations/$id/corriger',
        body: {'motif': motif});
    return Attestation.fromJson(data);
  }

  @override
  Future<Uint8List> telechargerAttestationPdf(String id) async {
    final uri = Uri.parse('$baseUrl/attestations/$id/pdf');
    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers(withBody: false))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException('Le serveur ne répond pas.');
    } on SocketException {
      throw const ApiException('Impossible de joindre le serveur.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }
    String message = 'Erreur ${res.statusCode}.';
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      message = (data['message'] as String?) ?? message;
    } catch (_) {}
    throw ApiException(message, res.statusCode);
  }

  // -- Communication : prières et messages (module 5) ------------------------
  @override
  Future<List<DemandePriere>> getDemandesPriere({String? statut}) async =>
      _items(
          await _call('GET', '/demandes-priere',
              query: _q({'statut': statut})),
          DemandePriere.fromJson);

  @override
  Future<DemandePriere> createDemandePriere({
    required String sujet,
    String? memberId,
    String? demandeurNom,
    String? details,
    bool confidentiel = false,
  }) async =>
      DemandePriere.fromJson(await _call('POST', '/demandes-priere', body: {
        'sujet': sujet,
        if (memberId != null) 'member_id': memberId,
        if (demandeurNom != null) 'demandeur_nom': demandeurNom,
        if (details != null) 'details': details,
        'confidentiel': confidentiel,
      }));

  @override
  Future<void> deleteDemandePriere(String id) async {
    await _call('DELETE', '/demandes-priere/$id');
  }

  @override
  Future<DemandePriere> setDemandePriereStatut(String id, String statut) async =>
      DemandePriere.fromJson(await _call(
          'PATCH', '/demandes-priere/$id',
          body: {'statut': statut}));

  @override
  Future<List<MessageInterne>> getMessagesInternes() async =>
      _items(await _call('GET', '/messages-internes'), MessageInterne.fromJson);

  @override
  Future<MessageInterne> createMessageInterne({
    required String sujet,
    required String corps,
    String? destinataireId,
  }) async {
    // Le serveur exige expediteur_id = utilisateur connecté.
    final moi = await me();
    return MessageInterne.fromJson(
        await _call('POST', '/messages-internes', body: {
      'expediteur_id': moi.user.id,
      if (destinataireId != null) 'destinataire_id': destinataireId,
      'sujet': sujet,
      'corps': corps,
    }));
  }

  // -- Suivi pastoral (module 6) ---------------------------------------------
  @override
  Future<List<ParcoursNouveau>> getParcoursNouveaux({String? etape}) async =>
      _items(
          await _call('GET', '/parcours-nouveaux',
              query: _q({'etape': etape})),
          ParcoursNouveau.fromJson);

  @override
  Future<ParcoursNouveau> createParcoursNouveau({
    required String memberId,
    String etape = 'accueil',
    String? note,
  }) async =>
      ParcoursNouveau.fromJson(
          await _call('POST', '/parcours-nouveaux', body: {
        'member_id': memberId,
        'etape': etape,
        if (note != null) 'note': note,
      }));

  @override
  Future<ParcoursNouveau> setParcoursEtape(String id, String etape) async =>
      ParcoursNouveau.fromJson(await _call(
          'PATCH', '/parcours-nouveaux/$id',
          body: {'etape': etape}));

  @override
  Future<List<VisitePastorale>> getVisitesPastorales({String? statut}) async =>
      _items(
          await _call('GET', '/visites-pastorales',
              query: _q({'statut': statut})),
          VisitePastorale.fromJson);

  @override
  Future<VisitePastorale> createVisitePastorale({
    required String memberId,
    required String dateVisite,
    String? motif,
    String? compteRendu,
  }) async =>
      VisitePastorale.fromJson(
          await _call('POST', '/visites-pastorales', body: {
        'member_id': memberId,
        'date_visite': dateVisite,
        if (motif != null) 'motif': motif,
        if (compteRendu != null) 'compte_rendu': compteRendu,
      }));

  @override
  Future<List<Accompagnement>> getAccompagnements(
      {String? type, String? statut}) async =>
      _items(
          await _call('GET', '/accompagnements',
              query: _q({'type': type, 'statut': statut})),
          Accompagnement.fromJson);

  @override
  Future<Accompagnement> createAccompagnement({
    required String memberId,
    required String type,
    String? description,
  }) async =>
      Accompagnement.fromJson(await _call('POST', '/accompagnements', body: {
        'member_id': memberId,
        'type': type,
        if (description != null) 'description': description,
      }));

  // -- Serviteurs (module 7) -------------------------------------------------
  @override
  Future<List<Serviteur>> getServiteurs({String? departementId}) async =>
      _items(
          await _call('GET', '/serviteurs',
              query: _q({'departement_id': departementId})),
          Serviteur.fromJson);

  @override
  Future<Serviteur> createServiteur({
    required String memberId,
    required String departementId,
    String role = 'serviteur',
    String? disponibilite,
  }) async =>
      Serviteur.fromJson(await _call('POST', '/serviteurs', body: {
        'member_id': memberId,
        'departement_id': departementId,
        'role': role,
        if (disponibilite != null) 'disponibilite': disponibilite,
      }));

  @override
  Future<void> deleteServiteur(String id) async {
    await _call('DELETE', '/serviteurs/$id');
  }

  @override
  Future<List<PlanningServiteur>> getPlanningServiteurs() async => _items(
      await _call('GET', '/planning-serviteurs'), PlanningServiteur.fromJson);

  @override
  Future<PlanningServiteur> createPlanningServiteur({
    required String serviteurId,
    required String dateService,
    String? culteId,
    String? roleService,
  }) async =>
      PlanningServiteur.fromJson(
          await _call('POST', '/planning-serviteurs', body: {
        'serviteur_id': serviteurId,
        'date_service': dateService,
        if (culteId != null) 'culte_id': culteId,
        if (roleService != null) 'role_service': roleService,
      }));

  // -- Enfants et jeunesse (module 8) -----------------------------------------
  @override
  Future<List<ClasseEnfant>> getClassesEnfants() async =>
      _items(await _call('GET', '/classes-enfants'), ClasseEnfant.fromJson);

  @override
  Future<ClasseEnfant> createClasseEnfant({
    required String nom,
    int? ageMin,
    int? ageMax,
    String? salle,
  }) async =>
      ClasseEnfant.fromJson(await _call('POST', '/classes-enfants', body: {
        'nom': nom,
        if (ageMin != null) 'age_min': ageMin,
        if (ageMax != null) 'age_max': ageMax,
        if (salle != null) 'salle': salle,
      }));

  @override
  Future<void> deleteClasseEnfant(String id) async {
    await _call('DELETE', '/classes-enfants/$id');
  }

  @override
  Future<List<AutorisationSortie>> getAutorisationsSorties(
          {String? statut}) async =>
      _items(
          await _call('GET', '/autorisations-sorties',
              query: _q({'statut': statut})),
          AutorisationSortie.fromJson);

  @override
  Future<AutorisationSortie> createAutorisationSortie({
    required String enfantMemberId,
    required String activite,
    required String dateSortie,
    String? parentMemberId,
  }) async =>
      AutorisationSortie.fromJson(
          await _call('POST', '/autorisations-sorties', body: {
        'enfant_member_id': enfantMemberId,
        'activite': activite,
        'date_sortie': dateSortie,
        if (parentMemberId != null) 'parent_member_id': parentMemberId,
      }));

  @override
  Future<AutorisationSortie> setAutorisationStatut(
          String id, String statut) async =>
      AutorisationSortie.fromJson(await _call(
          'PATCH', '/autorisations-sorties/$id',
          body: {'statut': statut}));

  @override
  Future<List<ActiviteJeunesse>> getActivitesJeunesse() async => _items(
      await _call('GET', '/activites-jeunesse'), ActiviteJeunesse.fromJson);

  @override
  Future<ActiviteJeunesse> createActiviteJeunesse({
    required String titre,
    required String dateActivite,
    String? description,
    String? lieu,
    String? responsableMemberId,
  }) async =>
      ActiviteJeunesse.fromJson(
          await _call('POST', '/activites-jeunesse', body: {
        'titre': titre,
        'date_activite': dateActivite,
        if (description != null) 'description': description,
        if (lieu != null) 'lieu': lieu,
        if (responsableMemberId != null)
          'responsable_member_id': responsableMemberId,
      }));

  @override
  Future<CheckinEnfant> checkinEnfant({
    required String enfantMemberId,
    required String parentMemberId,
    required String codeParent,
    required String codeEnfant,
    String? salle,
    String? allergie,
  }) async =>
      CheckinEnfant.fromJson(
          await _call('POST', '/checkins-enfants/checkin', body: {
        'enfant_member_id': enfantMemberId,
        'parent_member_id': parentMemberId,
        'code_parent': codeParent,
        'code_enfant': codeEnfant,
        if (salle != null) 'salle': salle,
        if (allergie != null) 'allergie': allergie,
      }));

  @override
  Future<CheckinEnfant> sortieEnfant({
    required String checkinId,
    required String codeEnfant,
    required String codeParent,
  }) async =>
      CheckinEnfant.fromJson(
          await _call('POST', '/checkins-enfants/$checkinId/sortie', body: {
        'code_enfant': codeEnfant,
        'code_parent': codeParent,
      }));

  @override
  Future<CheckinEnfant> alerteCheckinEnfant({
    required String checkinId,
    required String message,
  }) async =>
      CheckinEnfant.fromJson(await _call(
          'POST', '/checkins-enfants/$checkinId/alerte',
          body: {'message': message}));

  @override
  Future<List<CheckinEnfant>> getCheckinsEnfantsJour({String? salle}) async =>
      _items(
          await _call('GET', '/checkins-enfants/jour',
              query: _q({'salle': salle})),
          CheckinEnfant.fromJson);

  // -- Médias et enseignements (module 9) ------------------------------------
  @override
  Future<List<Predication>> getPredications() async =>
      _items(await _call('GET', '/predications'), Predication.fromJson);

  @override
  Future<Predication> createPredication({
    required String titre,
    required String datePredication,
    String? orateur,
    String? serie,
    String? urlAudio,
    String? urlVideo,
  }) async =>
      Predication.fromJson(await _call('POST', '/predications', body: {
        'titre': titre,
        'date_predication': datePredication,
        if (orateur != null) 'orateur': orateur,
        if (serie != null) 'serie': serie,
        if (urlAudio != null) 'url_audio': urlAudio,
        if (urlVideo != null) 'url_video': urlVideo,
      }));

  @override
  Future<List<PlanLecture>> getPlansLecture() async =>
      _items(await _call('GET', '/plans-lecture'), PlanLecture.fromJson);

  @override
  Future<PlanLecture> createPlanLecture({
    required String nom,
    String? description,
    int? dureeJours,
  }) async =>
      PlanLecture.fromJson(await _call('POST', '/plans-lecture', body: {
        'nom': nom,
        if (description != null) 'description': description,
        if (dureeJours != null) 'duree_jours': dureeJours,
      }));

  @override
  Future<List<Livre>> getLivres() async =>
      _items(await _call('GET', '/livres'), Livre.fromJson);

  @override
  Future<Livre> createLivre({
    required String titre,
    String? auteur,
    String? categorie,
    int exemplaires = 1,
  }) async =>
      Livre.fromJson(await _call('POST', '/livres', body: {
        'titre': titre,
        if (auteur != null) 'auteur': auteur,
        if (categorie != null) 'categorie': categorie,
        'exemplaires': exemplaires,
      }));

  @override
  Future<void> deleteLivre(String id) async {
    await _call('DELETE', '/livres/$id');
  }

  @override
  Future<List<PretLivre>> getPretsLivres({String? statut}) async => _items(
      await _call('GET', '/prets-livres', query: _q({'statut': statut})),
      PretLivre.fromJson);

  @override
  Future<PretLivre> createPretLivre({
    required String livreId,
    required String memberId,
    String? dateRetourPrevue,
  }) async =>
      PretLivre.fromJson(await _call('POST', '/prets-livres', body: {
        'livre_id': livreId,
        'member_id': memberId,
        if (dateRetourPrevue != null)
          'date_retour_prevue': dateRetourPrevue,
      }));

  @override
  Future<PretLivre> rendreLivre(String id) async => PretLivre.fromJson(
      await _call('POST', '/prets-livres/$id/rendre'));

  // -- Biens et inventaire (module 10) ---------------------------------------
  @override
  Future<List<Salle>> getSalles() async =>
      _items(await _call('GET', '/salles'), Salle.fromJson);

  @override
  Future<Salle> createSalle({
    required String nom,
    int? capacite,
    String? description,
  }) async =>
      Salle.fromJson(await _call('POST', '/salles', body: {
        'nom': nom,
        if (capacite != null) 'capacite': capacite,
        if (description != null) 'description': description,
      }));

  @override
  Future<void> deleteSalle(String id) async {
    await _call('DELETE', '/salles/$id');
  }

  @override
  Future<List<ReservationSalle>> getReservationsSalles(
          {String? salleId}) async =>
      _items(
          await _call('GET', '/reservations-salles',
              query: _q({'salle_id': salleId})),
          ReservationSalle.fromJson);

  @override
  Future<ReservationSalle> createReservationSalle({
    required String salleId,
    required String titre,
    required String debut,
    required String fin,
    String? reservePar,
  }) async =>
      ReservationSalle.fromJson(
          await _call('POST', '/reservations-salles', body: {
        'salle_id': salleId,
        'titre': titre,
        'debut': debut,
        'fin': fin,
        if (reservePar != null) 'reserve_par': reservePar,
      }));

  @override
  Future<List<Materiel>> getMateriel({String? etat}) async => _items(
      await _call('GET', '/materiel', query: _q({'etat': etat})),
      Materiel.fromJson);

  @override
  Future<Materiel> createMateriel({
    required String nom,
    String? categorie,
    int quantite = 1,
    String etat = 'bon',
    String? responsableMemberId,
  }) async =>
      Materiel.fromJson(await _call('POST', '/materiel', body: {
        'nom': nom,
        if (categorie != null) 'categorie': categorie,
        'quantite': quantite,
        'etat': etat,
        if (responsableMemberId != null)
          'responsable_member_id': responsableMemberId,
      }));

  @override
  Future<List<MaintenanceMateriel>> getMaintenanceMateriel(
          {String? materielId}) async =>
      _items(
          await _call('GET', '/maintenance-materiel',
              query: _q({'materiel_id': materielId})),
          MaintenanceMateriel.fromJson);

  @override
  Future<MaintenanceMateriel> createMaintenanceMateriel({
    required String materielId,
    required String description,
    String? dateMaintenance,
    int? coutFcfa,
    String? realisePar,
  }) async =>
      MaintenanceMateriel.fromJson(
          await _call('POST', '/maintenance-materiel', body: {
        'materiel_id': materielId,
        'description': description,
        if (dateMaintenance != null) 'date_maintenance': dateMaintenance,
        if (coutFcfa != null) 'cout_fcfa': coutFcfa,
        if (realisePar != null) 'realise_par': realisePar,
      }));

  // -- Statistiques et export (module 11) ------------------------------------
  @override
  Future<StatsGlobales> getStatsGlobales() async =>
      StatsGlobales.fromJson(await _call('GET', '/stats/globales'));

  @override
  Future<String> exportCsv(String type) async {
    // Le CSV est du texte brut : on n'utilise pas _call (qui attend du JSON).
    final uri = Uri.parse('$baseUrl/stats/export')
        .replace(queryParameters: {'type': type});
    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers(withBody: false))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException(
          'Le serveur ne répond pas. Vérifiez l’URL de l’API dans Réglages.');
    } on SocketException {
      throw const ApiException(
          'Impossible de joindre le serveur. Vérifiez l’URL de l’API dans Réglages.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
    String message = 'Erreur ${res.statusCode}.';
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      message = (data['message'] as String?) ?? message;
    } catch (_) {
      // Corps non JSON : on garde le message générique.
    }
    throw ApiException(message, res.statusCode);
  }

  // -- Administration : paramètres, rôles, audit (module 12) -----------------
  @override
  Future<EgliseParametres> getParametres() async =>
      EgliseParametres.fromJson(await _call('GET', '/parametres'));

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
  }) async =>
      EgliseParametres.fromJson(await _call('PATCH', '/parametres', body: {
        if (adresse != null) 'adresse': adresse,
        if (ville != null) 'ville': ville,
        if (telephone != null) 'telephone': telephone,
        if (email != null) 'email': email,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (waveNumero != null) 'wave_numero': waveNumero,
        if (orangeNumero != null) 'orange_numero': orangeNumero,
        if (mtnNumero != null) 'mtn_numero': mtnNumero,
        if (devise != null) 'devise': devise,
        if (fuseauHoraire != null) 'fuseau_horaire': fuseauHoraire,
      }));

  @override
  Future<List<RoleEglise>> getRoles() async {
    final data = await _call('GET', '/parametres/roles');
    return (data['roles'] as List<dynamic>)
        .map((e) => RoleEglise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RoleEglise> setRole(String userId, String role) async {
    // PATCH ne renvoie que { user_id, role } : on relit la liste des rôles.
    await _call('PATCH', '/parametres/roles/$userId', body: {'role': role});
    final roles = await getRoles();
    final trouve = roles.where((r) => r.userId == userId).firstOrNull;
    return trouve ?? RoleEglise(userId: userId, role: role);
  }

  @override
  Future<List<AuditEntree>> getAudit() async {
    final data = await _call('GET', '/parametres/audit');
    return (data['items'] as List<dynamic>)
        .map((e) => AuditEntree.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -- Présentation et identité de l'église (module 13) ----------------------
  @override
  Future<ProfilEglise> getPresentation(String code) async =>
      ProfilEglise.fromJson(
          await _call('GET', '/eglises/$code/presentation'));

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
  }) async =>
      Church.fromJson(await _call('PATCH', '/eglises/$churchId/profil', body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (horaires != null)
          'horaires_cultes': horaires.map((h) => h.toJson()).toList(),
        if (couleurPrincipale != null)
          'couleur_principale': couleurPrincipale,
        if (devise != null) 'devise': devise,
        if (fuseauHoraire != null) 'fuseau_horaire': fuseauHoraire,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (city != null) 'city': city,
      }));

  @override
  Future<String> uploadLogo({
    required String churchId,
    required String base64,
    String? filename,
  }) async {
    final data = await _call('POST', '/eglises/$churchId/logo', body: {
      'image_base64': base64,
      if (filename != null) 'filename': filename,
    });
    return data['logo_url'] as String;
  }

  @override
  Future<void> switchChurch(String churchId) async {
    final data = await _call('POST', '/auth/eglise-active', body: {
      'church_id': churchId,
    });
    _token = data['token'] as String?;
  }

  @override
  Future<MesEglisesPage> listerMesEglises(
          {String? recherche, int page = 1, int limite = 50}) async =>
      MesEglisesPage.fromJson(await _call('GET', '/moi/eglises', query: {
        if (recherche != null && recherche.trim().isNotEmpty)
          'recherche': recherche.trim(),
        'page': '$page',
        'limite': '$limite',
      }));

  // -- Paiements par pays et clés API (module 14) ---------------------------
  @override
  Future<List<FournisseurPaiement>> getFournisseursPaiement(
          {String? pays}) async =>
      _items(
          await _call('GET', '/paiements/fournisseurs',
              query: _q({'pays': pays})),
          FournisseurPaiement.fromJson);

  @override
  Future<List<EglisePaiement>> getMesPaiements(String churchId) async =>
      _items(await _call('GET', '/eglises/$churchId/paiements'),
          EglisePaiement.fromJson);

  @override
  Future<EglisePaiement> configurerPaiement({
    required String churchId,
    required String fournisseurCode,
    required String pays,
    String? libelle,
    bool? actif,
    required List<Map<String, String>> secrets,
  }) async =>
      EglisePaiement.fromJson(await _call('POST', '/eglises/$churchId/paiements', body: {
        'fournisseur_code': fournisseurCode,
        'pays': pays,
        if (libelle != null) 'libelle': libelle,
        if (actif != null) 'actif': actif,
        'secrets': secrets
            .map((s) => {'nom_champ': s['nom_champ'], 'valeur': s['valeur']})
            .toList(),
      }));

  @override
  Future<void> supprimerPaiement({
    required String churchId,
    required String fournisseurCode,
  }) async {
    await _call('DELETE', '/eglises/$churchId/paiements/$fournisseurCode');
  }

  @override
  Future<({bool ok, String message})> testerPaiement({
    required String churchId,
    required String fournisseurCode,
  }) async {
    final data = await _call(
        'POST', '/eglises/$churchId/paiements/$fournisseurCode/tester');
    return (
      ok: data['ok'] as bool? ?? false,
      message: data['message'] as String? ?? 'Test terminé.',
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
  }) async =>
      await _call('POST', '/paiements/executer', body: {
        'fournisseur_code': fournisseurCode,
        'type': type,
        'montant': montant,
        'devise': devise,
        if (memberId != null) 'member_id': memberId,
        'success_url': successUrl,
        'error_url': errorUrl,
        if (note != null) 'note': note,
      });

  // -- Rapports et annonces --------------------------------------------------
  @override
  Future<RapportConsolide> getRapport() async =>
      RapportConsolide.fromJson(await _call('GET', '/rapports/consolide'));

  @override
  Future<RapportDetailConsolide> getRapportDetail({
    required String periode,
    String? mois,
  }) async =>
      RapportDetailConsolide.fromJson(await _call(
        'GET',
        '/rapports/consolide/detail',
        query: {
          'periode': periode,
          if (mois != null) 'mois': mois,
        },
      ));

  @override
  Future<ChiffresPlateforme> getPlateforme() async {
    final data = await _call('GET', '/plateforme/chiffres');
    return ChiffresPlateforme.fromJson(
        data['chiffres'] as Map<String, dynamic>);
  }

  @override
  Future<List<ModuleEglise>> getModules() async {
    final data = await _call('GET', '/modules');
    return (data['modules'] as List<dynamic>)
        .map((e) => ModuleEglise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ModuleEglise> setModule({
    required String code,
    required bool actif,
  }) async {
    final data = await _call('PATCH', '/modules/$code', body: {'actif': actif});
    return ModuleEglise.fromJson(data);
  }

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

  @override
  Future<void> deleteAnnonce(String id) async {
    await _call('DELETE', '/annonces/$id');
  }
}
