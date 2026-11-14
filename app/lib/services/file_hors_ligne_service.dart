import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

/// File d'attente hors ligne, côté application (T11).
///
/// Quand le réseau est absent, les pointages et les saisies sont
/// enregistrés localement (une clé cliente unique par action) puis
/// soumis au serveur à la reconnexion. Le serveur déduplique par
/// `cle_client` : une action déjà enregistrée n'est jamais appliquée
/// deux fois, même si elle est rejouée plusieurs fois.
class ActionEnFile {
  final String cleClient;
  final String typeAction;
  final Map<String, dynamic> charge;
  final DateTime createdAt;
  final String? erreur;

  const ActionEnFile({
    required this.cleClient,
    required this.typeAction,
    required this.charge,
    required this.createdAt,
    this.erreur,
  });

  Map<String, dynamic> toJson() => {
        'cle_client': cleClient,
        'type_action': typeAction,
        'charge': charge,
        'created_at': createdAt.toIso8601String(),
        if (erreur != null) 'erreur': erreur,
      };

  factory ActionEnFile.fromJson(Map<String, dynamic> json) => ActionEnFile(
        cleClient: json['cle_client'] as String,
        typeAction: json['type_action'] as String,
        charge: (json['charge'] as Map<String, dynamic>?) ?? {},
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        erreur: json['erreur'] as String?,
      );
}

/// Résultat du rejeu de la file locale.
class RejeuLocal {
  final int envoyees;
  final int echecs;

  const RejeuLocal({required this.envoyees, required this.echecs});
}

class FileHorsLigneService {
  static const _storage = FlutterSecureStorage();

  String _cle(String userId) => 'file_hors_ligne_$userId';

  Future<List<ActionEnFile>> lire(String userId) async {
    final brut = await _storage.read(key: _cle(userId));
    if (brut == null || brut.isEmpty) return [];
    final decode = jsonDecode(brut);
    if (decode is! List) return [];
    return decode
        .whereType<Map<String, dynamic>>()
        .map(ActionEnFile.fromJson)
        .toList();
  }

  Future<void> _sauver(String userId, List<ActionEnFile> actions) =>
      _storage.write(
        key: _cle(userId),
        value: jsonEncode(actions.map((a) => a.toJson()).toList()),
      );

  /// Ajoute une action à la file. La clé cliente est unique : elle
  /// sert d'identifiant d'idempotence côté serveur.
  Future<ActionEnFile> ajouter(
    String userId, {
    required String typeAction,
    required Map<String, dynamic> charge,
  }) async {
    final action = ActionEnFile(
      cleClient:
          '${DateTime.now().millisecondsSinceEpoch}-${charge.hashCode.abs()}',
      typeAction: typeAction,
      charge: charge,
      createdAt: DateTime.now(),
    );
    final actions = await lire(userId);
    actions.add(action);
    await _sauver(userId, actions);
    return action;
  }

  Future<void> retirer(String userId, String cleClient) async {
    final actions = await lire(userId);
    actions.removeWhere((a) => a.cleClient == cleClient);
    await _sauver(userId, actions);
  }

  Future<void> marquerErreur(
      String userId, String cleClient, String erreur) async {
    final actions = await lire(userId);
    final index = actions.indexWhere((a) => a.cleClient == cleClient);
    if (index < 0) return;
    final action = actions[index];
    actions[index] = ActionEnFile(
      cleClient: action.cleClient,
      typeAction: action.typeAction,
      charge: action.charge,
      createdAt: action.createdAt,
      erreur: erreur,
    );
    await _sauver(userId, actions);
  }

  /// Rejoue la file dans l'ordre : chaque action est soumise au
  /// serveur, puis retirée de la file locale. Une action rejetée par
  /// le serveur (données invalides) reste dans la file avec son
  /// erreur, elle n'est pas perdue.
  Future<RejeuLocal> rejouer(String userId, ApiService api) async {
    final actions = await lire(userId);
    var envoyees = 0;
    var echecs = 0;
    for (final action in actions) {
      try {
        await api.soumettreActionHorsLigne(
          typeAction: action.typeAction,
          charge: action.charge,
          cleClient: action.cleClient,
        );
        await retirer(userId, action.cleClient);
        envoyees++;
      } on ApiException catch (e) {
        // Hors ligne : on arrête, le reste sera rejoué plus tard.
        if (e.code == 'hors_ligne') break;
        await marquerErreur(userId, action.cleClient, e.message);
        echecs++;
      }
    }
    return RejeuLocal(envoyees: envoyees, echecs: echecs);
  }
}
