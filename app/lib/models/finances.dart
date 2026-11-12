import '../utils/format.dart';

/// Catégorie comptable des dépenses (`categories_depenses`) : dix
/// catégories globales, identiques pour toutes les églises.
class CategorieDepense {
  final String id;
  final String code; // 01 à 10
  final String nom;
  final String? description;

  const CategorieDepense({
    required this.id,
    required this.code,
    required this.nom,
    this.description,
  });

  factory CategorieDepense.fromJson(Map<String, dynamic> json) =>
      CategorieDepense(
        id: json['id'] as String,
        code: json['code'] as String,
        nom: json['nom'] as String,
        description: json['description'] as String?,
      );

  String get libelle => '$code · $nom';
}

/// Poste budgétaire (`postes_budgetaires`).
class PosteBudgetaire {
  final String id;
  final String nom;
  final String categorie; // recette | depense
  final String? description;
  final String? categorieId; // catégorie comptable (dépenses seulement)
  final bool estRecurrente; // dépense récurrente ou ponctuelle
  final DateTime? createdAt;

  const PosteBudgetaire({
    required this.id,
    required this.nom,
    required this.categorie,
    this.description,
    this.categorieId,
    this.estRecurrente = false,
    this.createdAt,
  });

  factory PosteBudgetaire.fromJson(Map<String, dynamic> json) =>
      PosteBudgetaire(
        id: json['id'] as String,
        nom: json['nom'] as String,
        categorie: json['categorie'] as String,
        description: json['description'] as String?,
        categorieId: json['categorie_id'] as String?,
        estRecurrente: json['est_recurrente'] as bool? ?? false,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Budget mensuel d'un poste (`budgets_mensuels`).
class BudgetMensuel {
  final String id;
  final String posteId;
  final int annee;
  final int mois;
  final int montantPrevu;
  final DateTime? createdAt;

  const BudgetMensuel({
    required this.id,
    required this.posteId,
    required this.annee,
    required this.mois,
    required this.montantPrevu,
    this.createdAt,
  });

  factory BudgetMensuel.fromJson(Map<String, dynamic> json) => BudgetMensuel(
        id: json['id'] as String,
        posteId: json['poste_id'] as String,
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num).toInt(),
        montantPrevu: (json['montant_prevu'] as num).toInt(),
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
  final String? reference; // DEP-AAAA-NNNN, auto-générée par le serveur
  final String? departementId;
  final String? modePaiement; // especes | wave | orange_money | mtn_money | virement | cheque
  final String? fournisseurBeneficiaire;
  final String? responsableDepense;
  final String? responsableAutorisation;
  final String? devise; // FCFA par défaut
  final DateTime? createdAt;

  const Depense({
    required this.id,
    this.posteId,
    required this.montantFcfa,
    required this.motif,
    this.justificatifRef,
    required this.statut,
    this.dateDepense,
    this.reference,
    this.departementId,
    this.modePaiement,
    this.fournisseurBeneficiaire,
    this.responsableDepense,
    this.responsableAutorisation,
    this.devise,
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
        reference: json['reference'] as String?,
        departementId: json['departement_id'] as String?,
        modePaiement: json['mode_paiement'] as String?,
        fournisseurBeneficiaire:
            json['fournisseur_beneficiaire'] as String?,
        responsableDepense: json['responsable_depense'] as String?,
        responsableAutorisation:
            json['responsable_autorisation'] as String?,
        devise: json['devise'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForModePaiement(String? mode) {
    switch (mode) {
      case 'especes':
        return 'Espèces';
      case 'wave':
        return 'Wave';
      case 'orange_money':
        return 'Orange Money';
      case 'mtn_money':
        return 'MTN Mobile Money';
      case 'virement':
        return 'Virement';
      case 'cheque':
        return 'Chèque';
      default:
        return 'Non précisé';
    }
  }

  String get modePaiementLabel => labelForModePaiement(modePaiement);

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

/// Ligne de suivi mensuel : prévu contre réel, par catégorie ou par poste.
/// Dépassement quand le réel dépasse un budget mensuel défini.
class SuiviMensuelLigne {
  final String? posteId;
  final String? poste;
  final String? categorieCode;
  final String? categorieNom;
  final bool? recurrente;
  final int prevuFcfa;
  final int reelFcfa;
  final bool budgetDefini;

  const SuiviMensuelLigne({
    this.posteId,
    this.poste,
    this.categorieCode,
    this.categorieNom,
    this.recurrente,
    required this.prevuFcfa,
    required this.reelFcfa,
    required this.budgetDefini,
  });

  factory SuiviMensuelLigne.fromJson(Map<String, dynamic> json) =>
      SuiviMensuelLigne(
        posteId: json['poste_id'] as String?,
        poste: json['poste'] as String?,
        categorieCode: json['categorie_code'] as String?,
        categorieNom: json['categorie_nom'] as String?,
        recurrente: json['recurrente'] as bool?,
        prevuFcfa: (json['prevu_fcfa'] as num?)?.toInt() ?? 0,
        reelFcfa: (json['reel_fcfa'] as num?)?.toInt() ?? 0,
        budgetDefini: json['budget_defini'] as bool? ?? false,
      );

  bool get depassement => budgetDefini && prevuFcfa > 0 && reelFcfa > prevuFcfa;

  String get libelle {
    if (poste != null) return poste!;
    if (categorieCode != null) return '$categorieCode · ${categorieNom ?? ''}';
    return categorieNom ?? '—';
  }
}

/// Suivi mensuel (`GET /plan-comptable/suivi-mensuel`).
class SuiviMensuel {
  final int annee;
  final int mois;
  final List<SuiviMensuelLigne> parCategories;
  final List<SuiviMensuelLigne> parPostes;
  final int totalPrevuFcfa;
  final int totalReelFcfa;

  const SuiviMensuel({
    required this.annee,
    required this.mois,
    required this.parCategories,
    required this.parPostes,
    required this.totalPrevuFcfa,
    required this.totalReelFcfa,
  });

  factory SuiviMensuel.fromJson(Map<String, dynamic> json) => SuiviMensuel(
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num).toInt(),
        parCategories: (json['par_categories'] as List<dynamic>? ?? [])
            .map((e) =>
                SuiviMensuelLigne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        parPostes: (json['par_postes'] as List<dynamic>? ?? [])
            .map((e) =>
                SuiviMensuelLigne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        totalPrevuFcfa: (json['total_prevu_fcfa'] as num?)?.toInt() ?? 0,
        totalReelFcfa: (json['total_reel_fcfa'] as num?)?.toInt() ?? 0,
      );
}

/// Rapport des dépenses (`GET /plan-comptable/rapport`) : mêmes chiffres
/// que le PDF serveur et que le classeur Excel côté application.
class RapportPlanComptable {
  final int annee;
  final int? mois;
  final List<SuiviMensuelLigne> parCategories;
  final List<SuiviMensuelLigne> parPostes;
  final List<Map<String, dynamic>> depenses;
  final int totalPrevuFcfa;
  final int totalReelFcfa;

  const RapportPlanComptable({
    required this.annee,
    this.mois,
    required this.parCategories,
    required this.parPostes,
    required this.depenses,
    required this.totalPrevuFcfa,
    required this.totalReelFcfa,
  });

  factory RapportPlanComptable.fromJson(Map<String, dynamic> json) =>
      RapportPlanComptable(
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num?)?.toInt(),
        parCategories: (json['par_categories'] as List<dynamic>? ?? [])
            .map((e) =>
                SuiviMensuelLigne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        parPostes: (json['par_postes'] as List<dynamic>? ?? [])
            .map((e) =>
                SuiviMensuelLigne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        depenses: (json['depenses'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        totalPrevuFcfa: (json['total_prevu_fcfa'] as num?)?.toInt() ?? 0,
        totalReelFcfa: (json['total_reel_fcfa'] as num?)?.toInt() ?? 0,
      );
}
