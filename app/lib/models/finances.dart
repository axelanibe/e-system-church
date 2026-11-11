import '../utils/format.dart';

/// Poste budgétaire (`postes_budgetaires`).
class PosteBudgetaire {
  final String id;
  final String nom;
  final String categorie; // recette | depense
  final String? description;
  final DateTime? createdAt;

  const PosteBudgetaire({
    required this.id,
    required this.nom,
    required this.categorie,
    this.description,
    this.createdAt,
  });

  factory PosteBudgetaire.fromJson(Map<String, dynamic> json) =>
      PosteBudgetaire(
        id: json['id'] as String,
        nom: json['nom'] as String,
        categorie: json['categorie'] as String,
        description: json['description'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Budget annuel d'un poste (`budgets`).
class Budget {
  final String id;
  final String posteId;
  final int annee;
  final int montantPrevu;
  final DateTime? createdAt;

  const Budget({
    required this.id,
    required this.posteId,
    required this.annee,
    required this.montantPrevu,
    this.createdAt,
  });

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        posteId: json['poste_id'] as String,
        annee: (json['annee'] as num).toInt(),
        montantPrevu: (json['montant_prevu'] as num).toInt(),
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Dépense (`depenses`) : validation en deux temps
/// soumise → validée trésorier → validée pasteur → payée (ou refusée).
class Depense {
  final String id;
  final String? posteId;
  final int montantFcfa;
  final String motif;
  final String? justificatifRef;
  final String statut; // soumise | validee_tresorier | validee_pasteur | payee | refusee
  final String? dateDepense; // « AAAA-MM-JJ »
  final DateTime? createdAt;

  const Depense({
    required this.id,
    this.posteId,
    required this.montantFcfa,
    required this.motif,
    this.justificatifRef,
    required this.statut,
    this.dateDepense,
    this.createdAt,
  });

  factory Depense.fromJson(Map<String, dynamic> json) => Depense(
        id: json['id'] as String,
        posteId: json['poste_id'] as String?,
        montantFcfa: (json['montant_fcfa'] as num).toInt(),
        motif: json['motif'] as String,
        justificatifRef: json['justificatif_ref'] as String?,
        statut: json['statut'] as String? ?? 'soumise',
        dateDepense: json['date_depense'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'soumise':
        return 'Soumise';
      case 'validee_tresorier':
        return 'Validée par le trésorier';
      case 'validee_pasteur':
        return 'Validée par le pasteur';
      case 'payee':
        return 'Payée';
      case 'refusee':
        return 'Refusée';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Mouvement de caisse (`caisse_mouvements` : entrée ou sortie).
class CaisseMouvement {
  final String id;
  final String type; // entree | sortie
  final int montantFcfa;
  final String motif;
  final String? reference;
  final DateTime? createdAt;

  const CaisseMouvement({
    required this.id,
    required this.type,
    required this.montantFcfa,
    required this.motif,
    this.reference,
    this.createdAt,
  });

  factory CaisseMouvement.fromJson(Map<String, dynamic> json) =>
      CaisseMouvement(
        id: json['id'] as String,
        type: json['type'] as String,
        montantFcfa: (json['montant_fcfa'] as num).toInt(),
        motif: json['motif'] as String,
        reference: json['reference'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Solde de caisse (`GET /finances/caisse` :
/// `{ entrees, sorties, solde, mouvements }`, `mouvements` = nombre de
/// mouvements enregistrés).
class CaisseSolde {
  final int entrees;
  final int sorties;
  final int solde;
  final int mouvements;

  const CaisseSolde({
    required this.entrees,
    required this.sorties,
    required this.solde,
    required this.mouvements,
  });

  factory CaisseSolde.fromJson(Map<String, dynamic> json) => CaisseSolde(
        entrees: (json['entrees'] as num?)?.toInt() ?? 0,
        sorties: (json['sorties'] as num?)?.toInt() ?? 0,
        solde: (json['solde'] as num?)?.toInt() ?? 0,
        mouvements: (json['mouvements'] as num?)?.toInt() ?? 0,
      );
}

/// Rapport financier détaillé (`GET /finances/rapport` :
/// `{ par_mois, par_poste, par_branche }`).
class RapportFinancier {
  final List<Map<String, dynamic>> parMois;
  final List<Map<String, dynamic>> parPoste;
  final List<Map<String, dynamic>> parBranche;

  const RapportFinancier({
    required this.parMois,
    required this.parPoste,
    required this.parBranche,
  });

  factory RapportFinancier.fromJson(Map<String, dynamic> json) =>
      RapportFinancier(
        parMois: (json['par_mois'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        parPoste: (json['par_poste'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        parBranche: (json['par_branche'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}
