/// Suppression d'une église entière (`POST /admin/supprimer-eglise`) :
/// l'église TEST par elle-même, ou une annexe par sa mère ou par le
/// super administrateur. Aperçu d'abord, confirmation ensuite.
class EgliseASupprimer {
  final String id;
  final String nom;
  final String code;

  const EgliseASupprimer({
    required this.id,
    required this.nom,
    required this.code,
  });

  factory EgliseASupprimer.fromJson(Map<String, dynamic> json) =>
      EgliseASupprimer(
        id: json['id'] as String,
        nom: json['nom'] as String,
        code: json['code'] as String,
      );
}

/// Aperçu de la suppression : ce qui serait supprimé, sans rien supprimer.
class SuppressionEgliseApercu {
  final EgliseASupprimer eglise;
  final List<EgliseASupprimer> annexes;

  /// Comptes par table (seules les tables non vides sont présentes).
  final Map<String, int> comptes;

  /// Comptes utilisateurs TEST qui n'ont plus aucune église après la
  /// suppression et seraient supprimés avec elle.
  final int utilisateursSupprimes;

  const SuppressionEgliseApercu({
    required this.eglise,
    required this.annexes,
    required this.comptes,
    required this.utilisateursSupprimes,
  });

  /// Églises, éléments et comptes supprimés au total.
  int get total =>
      1 +
      annexes.length +
      comptes.values.fold<int>(0, (a, b) => a + b) +
      utilisateursSupprimes;

  static const _libelles = {
    'members': 'Membres',
    'contributions': 'Contributions',
    'campagnes': 'Campagnes',
    'attestations': 'Attestations',
    'transferts_membre': 'Transferts',
    'church_users': 'Comptes liés à l\u2019église',
    'depenses': 'Dépenses',
    'cultes': 'Cultes',
    'presences': 'Présences',
    'announcements': 'Annonces',
    'demandes_priere': 'Demandes de prière',
    'familles': 'Familles',
    'departements': 'Départements',
    'cellules': 'Cellules',
    'serviteurs': 'Serviteurs',
    'budgets': 'Budgets',
    'budgets_mensuels': 'Budgets mensuels',
    'caisse_mouvements': 'Mouvements de caisse',
    'clotures_caisse': 'Clôtures de caisse',
    'comptes_bancaires': 'Comptes bancaires',
    'rattachements': 'Rattachements',
    'codes_tutelle': 'Codes de tutelle',
    'rapports_annexe': 'Rapports d\u2019annexe',
    'abonnements': 'Abonnements',
    'evenements_paiement': 'Événements de paiement',
    'eglise_paiements': 'Comptes de paiement',
    'eglise_paiement_secrets': 'Clés de paiement',
  };

  /// Lignes « Libellé : nombre » pour l'aperçu, triées par nombre décroissant.
  List<String> get lignesComptes {
    final entrees = comptes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entrees)
        '${_libelles[e.key] ?? e.key} : ${e.value}',
    ];
  }

  factory SuppressionEgliseApercu.fromJson(Map<String, dynamic> json) =>
      SuppressionEgliseApercu(
        eglise: EgliseASupprimer.fromJson(
            json['eglise'] as Map<String, dynamic>),
        annexes: (json['annexes'] as List<dynamic>)
            .map((e) => EgliseASupprimer.fromJson(e as Map<String, dynamic>))
            .toList(),
        comptes: (json['comptes'] as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        utilisateursSupprimes: (json['utilisateurs_supprimes'] as num?)?.toInt() ?? 0,
      );
}

/// Résultat de la suppression confirmée.
class SuppressionEgliseResultat {
  final EgliseASupprimer eglise;
  final List<EgliseASupprimer> annexes;
  final Map<String, int> comptes;
  final int utilisateursSupprimes;

  const SuppressionEgliseResultat({
    required this.eglise,
    required this.annexes,
    required this.comptes,
    required this.utilisateursSupprimes,
  });

  int get total =>
      1 +
      annexes.length +
      comptes.values.fold<int>(0, (a, b) => a + b) +
      utilisateursSupprimes;

  factory SuppressionEgliseResultat.fromJson(Map<String, dynamic> json) =>
      SuppressionEgliseResultat(
        eglise: EgliseASupprimer.fromJson(
            json['eglise'] as Map<String, dynamic>),
        annexes: (json['annexes'] as List<dynamic>)
            .map((e) => EgliseASupprimer.fromJson(e as Map<String, dynamic>))
            .toList(),
        comptes: (json['comptes'] as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        utilisateursSupprimes: (json['utilisateurs_supprimes'] as num?)?.toInt() ?? 0,
      );
}
