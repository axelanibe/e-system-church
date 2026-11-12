/// Mon abonnement (tranche P3, migration 021) : abonnement annuel de
/// l'église mère, 200 000 FCFA par an, couvrant l'église mère et
/// toutes ses annexes. Une annexe n'a pas son propre abonnement :
/// elle est couverte par celui de son église mère.
class Abonnement {
  /// Vrai si mon église est une annexe (elle a une église mère).
  final bool estAnnexe;

  /// Nom de l'église mère (annexe seulement).
  final String? egliseMereNom;

  /// Statut : essai, actif, grace, expire.
  final String statut;

  /// Plan : annuel.
  final String plan;

  /// Montant annuel en FCFA (200 000 par défaut).
  final int montantFcfa;

  /// Date d'expiration, null tant qu'elle n'est pas renseignée
  /// (affichée « À compléter », jamais inventée).
  final DateTime? dateExpiration;

  /// Durée de l'essai gratuit, en jours (30).
  final int essaiJours;

  /// Vrai quand l'abonnement est expiré et la grâce de 30 jours
  /// passée : l'application passe en lecture seule.
  final bool lectureSeule;

  const Abonnement({
    required this.estAnnexe,
    this.egliseMereNom,
    required this.statut,
    required this.plan,
    required this.montantFcfa,
    this.dateExpiration,
    required this.essaiJours,
    required this.lectureSeule,
  });

  /// Libellé du statut, tel qu'affiché dans la projection.
  String get statutLibelle {
    switch (statut) {
      case 'essai':
        return 'Essai gratuit';
      case 'grace':
        return 'Période de grâce';
      case 'expire':
        return 'Expiré';
      case 'actif':
      default:
        return 'Actif';
    }
  }

  factory Abonnement.fromJson(Map<String, dynamic> json) {
    final abo = json['abonnement'] as Map<String, dynamic>?;
    return Abonnement(
      estAnnexe: json['est_annexe'] as bool? ?? false,
      egliseMereNom: json['eglise_mere_nom'] as String?,
      statut: abo?['statut'] as String? ?? 'actif',
      plan: abo?['plan'] as String? ?? 'annuel',
      montantFcfa: (abo?['montant_fcfa'] as num?)?.toInt() ?? 200000,
      dateExpiration: abo?['date_expiration'] == null
          ? null
          : DateTime.tryParse(abo!['date_expiration'] as String),
      essaiJours: (abo?['essai_jours'] as num?)?.toInt() ?? 30,
      lectureSeule: abo?['lecture_seule'] as bool? ?? false,
    );
  }
}

/// Résultat de la validation d'un code promo (tranche P3).
/// La réduction dépend du code ; aucun taux n'est inventé côté client.
class ValidationCodePromo {
  final bool valide;
  final String code;
  final String typeReduction; // pourcentage ou montant
  final int valeur;
  final int totalAvant;
  final int totalApres;

  const ValidationCodePromo({
    required this.valide,
    required this.code,
    required this.typeReduction,
    required this.valeur,
    required this.totalAvant,
    required this.totalApres,
  });

  factory ValidationCodePromo.fromJson(Map<String, dynamic> json) =>
      ValidationCodePromo(
        valide: json['valide'] as bool? ?? false,
        code: json['code'] as String? ?? '',
        typeReduction: json['type_reduction'] as String? ?? '',
        valeur: (json['valeur'] as num?)?.toInt() ?? 0,
        totalAvant: (json['total_avant'] as num?)?.toInt() ?? 0,
        totalApres: (json['total_apres'] as num?)?.toInt() ?? 0,
      );
}

/// Tarifs validés par Axel le 12 novembre 2026, remises déjà incluses.
/// 1 an 200 000 FCFA, 3 ans 540 000 au lieu de 600 000, 10 ans
/// 1 600 000 au lieu de 2 000 000.
const Map<int, int> tarifsAbonnement = {1: 200000, 3: 540000, 10: 1600000};

/// Ancien prix barré, avant remise de durée (null pour 1 an).
int? ancienTarifAbonnement(int dureeAnnees) {
  switch (dureeAnnees) {
    case 3:
      return 600000;
    case 10:
      return 2000000;
    default:
      return null;
  }
}
