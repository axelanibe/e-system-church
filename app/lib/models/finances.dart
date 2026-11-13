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
/// Libellé d'un canal de paiement ou de caisse (codes serveur → français).
String labelCanal(String? canal) {
  switch (canal) {
    case 'wave':
      return 'Wave';
    case 'orange_money':
      return 'Orange Money';
    case 'mtn_momo':
      return 'MTN MoMo';
    case 'especes':
      return 'Espèces';
    case 'virement':
      return 'Virement';
    case 'cheque':
      return 'Chèque';
    case 'non_ventile':
      return 'Non ventilé';
    default:
      return canal ?? '—';
  }
}

class CaisseMouvement {
  final String id;
  final String type; // entree | sortie
  final int montantFcfa;
  final String motif;
  final String? reference;
  final DateTime? createdAt;

  /// Origine de l'écriture (T7) : manuelle (saisie à la main),
  /// contribution (confirmée) ou depense (payée).
  final String? source;

  /// Canal de paiement (T7) : wave, orange_money, mtn_momo, especes,
  /// virement, cheque. Null pour les écritures non ventilées.
  final String? canal;

  const CaisseMouvement({
    required this.id,
    required this.type,
    required this.montantFcfa,
    required this.motif,
    this.reference,
    this.createdAt,
    this.source,
    this.canal,
  });

  factory CaisseMouvement.fromJson(Map<String, dynamic> json) =>
      CaisseMouvement(
        id: json['id'] as String,
        type: json['type'] as String,
        montantFcfa: (json['montant_fcfa'] as num).toInt(),
        motif: json['motif'] as String,
        reference: json['reference'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
        source: json['source'] as String?,
        canal: json['canal'] as String?,
      );

  /// « Manuelle » pour une saisie, « Automatique » pour une écriture
  /// créée par le serveur (contribution confirmée, dépense payée).
  String get sourceLabel =>
      source == 'manuelle' ? 'Manuelle' : 'Automatique';

  String get canalLabel => labelCanal(canal);
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

/// ---------------------------------------------------------------------------
/// Tranche T7 — Finances complètes (cotisations, comptes bancaires,
/// rapprochement, clôture, reçus, budgets par département).
/// ---------------------------------------------------------------------------

/// Configuration des cotisations (`cotisations_config`, T7) : montant
/// fixé par l'église, pour tous les membres actifs.
class CotisationConfig {
  final int montantFcfa;
  final String periodicite; // mensuelle | annuelle
  final bool actif;

  const CotisationConfig({
    required this.montantFcfa,
    required this.periodicite,
    required this.actif,
  });

  factory CotisationConfig.fromJson(Map<String, dynamic> json) =>
      CotisationConfig(
        montantFcfa: (json['montant_fcfa'] as num).toInt(),
        periodicite: json['periodicite'] as String? ?? 'mensuelle',
        actif: json['actif'] as bool? ?? true,
      );

  String get periodiciteLabel =>
      periodicite == 'annuelle' ? 'Annuelle' : 'Mensuelle';
}

/// Une ligne du suivi des cotisations (T7, `GET /cotisations/suivi`) :
/// ce qu'un membre doit, a payé et doit encore, sur la période.
class LigneCotisation {
  final String memberId;
  final String membreNom;
  final String? membreMatricule;
  final int montantDuFcfa;
  final int montantPayeFcfa;
  final int resteFcfa;
  final int surplusFcfa;
  final String statut; // payee | partielle | impayee

  const LigneCotisation({
    required this.memberId,
    required this.membreNom,
    this.membreMatricule,
    required this.montantDuFcfa,
    required this.montantPayeFcfa,
    required this.resteFcfa,
    required this.surplusFcfa,
    required this.statut,
  });

  factory LigneCotisation.fromJson(Map<String, dynamic> json) =>
      LigneCotisation(
        memberId: json['member_id'] as String,
        membreNom: json['membre_nom'] as String,
        membreMatricule: json['membre_matricule'] as String?,
        montantDuFcfa: (json['montant_du_fcfa'] as num).toInt(),
        montantPayeFcfa: (json['montant_paye_fcfa'] as num).toInt(),
        resteFcfa: (json['reste_fcfa'] as num).toInt(),
        surplusFcfa: (json['surplus_fcfa'] as num?)?.toInt() ?? 0,
        statut: json['statut'] as String,
      );

  String get statutLabel {
    switch (statut) {
      case 'payee':
        return 'Payée';
      case 'partielle':
        return 'Partielle';
      default:
        return 'Impayée';
    }
  }
}

/// Totaux du suivi des cotisations (T7).
class TotauxCotisations {
  final int totalDuFcfa;
  final int totalPayeFcfa;
  final int totalResteFcfa;
  final int membresPayes;
  final int membresTotal;

  const TotauxCotisations({
    required this.totalDuFcfa,
    required this.totalPayeFcfa,
    required this.totalResteFcfa,
    required this.membresPayes,
    required this.membresTotal,
  });

  factory TotauxCotisations.fromJson(Map<String, dynamic> json) =>
      TotauxCotisations(
        totalDuFcfa: (json['total_du_fcfa'] as num?)?.toInt() ?? 0,
        totalPayeFcfa: (json['total_paye_fcfa'] as num?)?.toInt() ?? 0,
        totalResteFcfa: (json['total_reste_fcfa'] as num?)?.toInt() ?? 0,
        membresPayes: (json['membres_payes'] as num?)?.toInt() ?? 0,
        membresTotal: (json['membres_total'] as num?)?.toInt() ?? 0,
      );
}

/// Suivi des cotisations (T7, `GET /cotisations/suivi`).
class SuiviCotisations {
  final CotisationConfig? config;
  final bool configAbsente;
  final String periode;
  final List<LigneCotisation> membres;
  final TotauxCotisations totaux;

  const SuiviCotisations({
    this.config,
    required this.configAbsente,
    required this.periode,
    required this.membres,
    required this.totaux,
  });

  factory SuiviCotisations.fromJson(Map<String, dynamic> json) =>
      SuiviCotisations(
        config: json['config'] == null
            ? null
            : CotisationConfig.fromJson(
                Map<String, dynamic>.from(json['config'] as Map)),
        configAbsente: json['config_absente'] as bool? ?? false,
        periode: json['periode'] as String,
        membres: (json['membres'] as List<dynamic>? ?? [])
            .map((e) =>
                LigneCotisation.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        totaux: TotauxCotisations.fromJson(
            Map<String, dynamic>.from(json['totaux'] as Map)),
      );
}

/// Compte bancaire de l'église (T7, `comptes_bancaires`).
class CompteBancaire {
  final String id;
  final String banque;
  final String? titulaire;
  final String? numeroCompte;
  final String type; // banque | mobile_money
  final String devise;
  final bool actif;
  final DateTime? createdAt;

  const CompteBancaire({
    required this.id,
    required this.banque,
    this.titulaire,
    this.numeroCompte,
    required this.type,
    required this.devise,
    required this.actif,
    this.createdAt,
  });

  factory CompteBancaire.fromJson(Map<String, dynamic> json) =>
      CompteBancaire(
        id: json['id'] as String,
        banque: json['banque'] as String,
        titulaire: json['titulaire'] as String?,
        numeroCompte: json['numero_compte'] as String?,
        type: json['type'] as String? ?? 'banque',
        devise: json['devise'] as String? ?? 'FCFA',
        actif: json['actif'] as bool? ?? true,
        createdAt: parseDate(json['created_at'] as String?),
      );

  String get typeLabel =>
      type == 'mobile_money' ? 'Mobile Money' : 'Banque';
}

/// Une ligne du rapprochement par canal (T7,
/// `GET /finances/rapprochement`) : ce qui aurait dû entrer ou sortir
/// contre ce qui est comptabilisé en caisse, pour un canal et un mois.
class LigneRapprochement {
  final String canal;
  final int entreesConfirmeesFcfa;
  final int sortiesPayeesFcfa;
  final int attenduFcfa;
  final int caisseEntreesFcfa;
  final int caisseSortiesFcfa;
  final int caisseNetFcfa;
  final int ecartFcfa;
  final bool alerte;

  const LigneRapprochement({
    required this.canal,
    required this.entreesConfirmeesFcfa,
    required this.sortiesPayeesFcfa,
    required this.attenduFcfa,
    required this.caisseEntreesFcfa,
    required this.caisseSortiesFcfa,
    required this.caisseNetFcfa,
    required this.ecartFcfa,
    required this.alerte,
  });

  factory LigneRapprochement.fromJson(Map<String, dynamic> json) =>
      LigneRapprochement(
        canal: json['canal'] as String,
        entreesConfirmeesFcfa:
            (json['entrees_confirmees_fcfa'] as num?)?.toInt() ?? 0,
        sortiesPayeesFcfa:
            (json['sorties_payees_fcfa'] as num?)?.toInt() ?? 0,
        attenduFcfa: (json['attendu_fcfa'] as num?)?.toInt() ?? 0,
        caisseEntreesFcfa:
            (json['caisse_entrees_fcfa'] as num?)?.toInt() ?? 0,
        caisseSortiesFcfa:
            (json['caisse_sorties_fcfa'] as num?)?.toInt() ?? 0,
        caisseNetFcfa: (json['caisse_net_fcfa'] as num?)?.toInt() ?? 0,
        ecartFcfa: (json['ecart_fcfa'] as num?)?.toInt() ?? 0,
        alerte: json['alerte'] as bool? ?? false,
      );

  String get canalLabel => labelCanal(canal);
}

/// Totaux du rapprochement (T7).
class TotauxRapprochement {
  final int entreesConfirmeesFcfa;
  final int sortiesPayeesFcfa;
  final int attenduFcfa;
  final int caisseNetFcfa;
  final int ecartFcfa;

  const TotauxRapprochement({
    required this.entreesConfirmeesFcfa,
    required this.sortiesPayeesFcfa,
    required this.attenduFcfa,
    required this.caisseNetFcfa,
    required this.ecartFcfa,
  });

  factory TotauxRapprochement.fromJson(Map<String, dynamic> json) =>
      TotauxRapprochement(
        entreesConfirmeesFcfa:
            (json['entrees_confirmees_fcfa'] as num?)?.toInt() ?? 0,
        sortiesPayeesFcfa:
            (json['sorties_payees_fcfa'] as num?)?.toInt() ?? 0,
        attenduFcfa: (json['attendu_fcfa'] as num?)?.toInt() ?? 0,
        caisseNetFcfa: (json['caisse_net_fcfa'] as num?)?.toInt() ?? 0,
        ecartFcfa: (json['ecart_fcfa'] as num?)?.toInt() ?? 0,
      );
}

/// Rapprochement par canal (T7, `GET /finances/rapprochement`).
class Rapprochement {
  final int annee;
  final int mois;
  final String periode;
  final List<LigneRapprochement> canaux;
  final LigneRapprochement nonVentile;
  final TotauxRapprochement totaux;

  const Rapprochement({
    required this.annee,
    required this.mois,
    required this.periode,
    required this.canaux,
    required this.nonVentile,
    required this.totaux,
  });

  factory Rapprochement.fromJson(Map<String, dynamic> json) =>
      Rapprochement(
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num).toInt(),
        periode: json['periode'] as String,
        canaux: (json['canaux'] as List<dynamic>? ?? [])
            .map((e) => LigneRapprochement.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        nonVentile: LigneRapprochement.fromJson(
            Map<String, dynamic>.from(json['non_ventile'] as Map)),
        totaux: TotauxRapprochement.fromJson(
            Map<String, dynamic>.from(json['totaux'] as Map)),
      );
}

/// Clôture de caisse verrouillée (T7, `clotures_caisse`) : un mois
/// clôturé ne se rouvre ni ne se supprime.
class ClotureCaisse {
  final String id;
  final String periode; // AAAA-MM
  final int soldeCalculeFcfa;
  final int soldeCompteFcfa;
  final int ecartFcfa;
  final String? commentaire;
  final DateTime? createdAt;

  const ClotureCaisse({
    required this.id,
    required this.periode,
    required this.soldeCalculeFcfa,
    required this.soldeCompteFcfa,
    required this.ecartFcfa,
    this.commentaire,
    this.createdAt,
  });

  factory ClotureCaisse.fromJson(Map<String, dynamic> json) =>
      ClotureCaisse(
        id: json['id'] as String,
        periode: json['periode'] as String,
        soldeCalculeFcfa: (json['solde_calcule_fcfa'] as num).toInt(),
        soldeCompteFcfa: (json['solde_compte_fcfa'] as num).toInt(),
        ecartFcfa: (json['ecart_fcfa'] as num).toInt(),
        commentaire: json['commentaire'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Budget mensuel d'un département (T7, `budgets_departements`).
class BudgetDepartement {
  final String id;
  final String departementId;
  final String? departementNom;
  final int annee;
  final int mois;
  final int montantPrevu;

  const BudgetDepartement({
    required this.id,
    required this.departementId,
    this.departementNom,
    required this.annee,
    required this.mois,
    required this.montantPrevu,
  });

  factory BudgetDepartement.fromJson(Map<String, dynamic> json) =>
      BudgetDepartement(
        id: json['id'] as String,
        departementId: json['departement_id'] as String,
        departementNom: json['departement_nom'] as String?,
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num).toInt(),
        montantPrevu: (json['montant_prevu'] as num).toInt(),
      );
}

/// Une ligne du suivi par département (T7,
/// `GET /plan-comptable/suivi-departements`) : prévu contre réel,
/// avec alerte quand le réel dépasse un budget défini.
class LigneSuiviDepartement {
  final String departementId;
  final String departement;
  final int prevuFcfa;
  final int reelFcfa;
  final int ecartFcfa;
  final bool depasse;
  final bool budgetDefini;

  const LigneSuiviDepartement({
    required this.departementId,
    required this.departement,
    required this.prevuFcfa,
    required this.reelFcfa,
    required this.ecartFcfa,
    required this.depasse,
    required this.budgetDefini,
  });

  factory LigneSuiviDepartement.fromJson(Map<String, dynamic> json) =>
      LigneSuiviDepartement(
        departementId: json['departement_id'] as String,
        departement: json['departement'] as String,
        prevuFcfa: (json['prevu_fcfa'] as num?)?.toInt() ?? 0,
        reelFcfa: (json['reel_fcfa'] as num?)?.toInt() ?? 0,
        ecartFcfa: (json['ecart_fcfa'] as num?)?.toInt() ?? 0,
        depasse: json['depasse'] as bool? ?? false,
        budgetDefini: json['budget_defini'] as bool? ?? false,
      );
}

/// Dépenses sans département, dans le suivi par département (T7).
class TotalSansDepartement {
  final int prevuFcfa;
  final int reelFcfa;
  final int ecartFcfa;

  const TotalSansDepartement({
    required this.prevuFcfa,
    required this.reelFcfa,
    required this.ecartFcfa,
  });

  factory TotalSansDepartement.fromJson(Map<String, dynamic> json) =>
      TotalSansDepartement(
        prevuFcfa: (json['prevu_fcfa'] as num?)?.toInt() ?? 0,
        reelFcfa: (json['reel_fcfa'] as num?)?.toInt() ?? 0,
        ecartFcfa: (json['ecart_fcfa'] as num?)?.toInt() ?? 0,
      );
}

/// Suivi par département (T7, `GET /plan-comptable/suivi-departements`).
class SuiviDepartements {
  final int annee;
  final int mois;
  final List<LigneSuiviDepartement> parDepartements;
  final TotalSansDepartement sansDepartement;
  final int totalPrevuFcfa;
  final int totalReelFcfa;

  const SuiviDepartements({
    required this.annee,
    required this.mois,
    required this.parDepartements,
    required this.sansDepartement,
    required this.totalPrevuFcfa,
    required this.totalReelFcfa,
  });

  factory SuiviDepartements.fromJson(Map<String, dynamic> json) =>
      SuiviDepartements(
        annee: (json['annee'] as num).toInt(),
        mois: (json['mois'] as num).toInt(),
        parDepartements: (json['par_departements'] as List<dynamic>? ?? [])
            .map((e) => LigneSuiviDepartement.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        sansDepartement: TotalSansDepartement.fromJson(
            Map<String, dynamic>.from(json['sans_departement'] as Map)),
        totalPrevuFcfa: (json['total_prevu_fcfa'] as num?)?.toInt() ?? 0,
        totalReelFcfa: (json['total_reel_fcfa'] as num?)?.toInt() ?? 0,
      );
}
