import '../utils/format.dart';

/// Réunion du conseil (`reunions_conseil`, T10).
class ReunionConseil {
  final String id;
  final String titre;
  final String dateReunion;
  final String? lieu;
  final String? ordreDuJour;
  final String statut; // prevue | tenue | annulee
  final DateTime? createdAt;

  const ReunionConseil({
    required this.id,
    required this.titre,
    required this.dateReunion,
    this.lieu,
    this.ordreDuJour,
    required this.statut,
    this.createdAt,
  });

  String get statutLabel => switch (statut) {
        'tenue' => 'Tenue',
        'annulee' => 'Annulée',
        _ => 'Prévue',
      };

  factory ReunionConseil.fromJson(Map<String, dynamic> json) =>
      ReunionConseil(
        id: json['id'] as String,
        titre: json['titre'] as String,
        dateReunion: json['date_reunion'] as String,
        lieu: json['lieu'] as String?,
        ordreDuJour: json['ordre_du_jour'] as String?,
        statut: json['statut'] as String? ?? 'prevue',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Décision du conseil (`decisions`, T10).
class Decision {
  final String id;
  final String? reunionId;
  final String titre;
  final String? description;
  final String? dateDecision; // « AAAA-MM-JJ »
  final String statut; // adoptee | rejetee | reportee
  final DateTime? createdAt;

  const Decision({
    required this.id,
    this.reunionId,
    required this.titre,
    this.description,
    this.dateDecision,
    required this.statut,
    this.createdAt,
  });

  String get statutLabel => switch (statut) {
        'rejetee' => 'Rejetée',
        'reportee' => 'Reportée',
        _ => 'Adoptée',
      };

  factory Decision.fromJson(Map<String, dynamic> json) => Decision(
        id: json['id'] as String,
        reunionId: json['reunion_id'] as String?,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        dateDecision: json['date_decision'] as String?,
        statut: json['statut'] as String? ?? 'adoptee',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Mandat d'un responsable (`mandats`, T10). Une nomination est un
/// mandat : sa décision de nomination est gardée quand elle existe.
class Mandat {
  final String id;
  final String memberId;
  final String fonction;
  final String dateDebut; // « AAAA-MM-JJ »
  final String? dateFin;
  final String statut; // en_cours | termine
  final String? decisionId;
  final DateTime? createdAt;

  const Mandat({
    required this.id,
    required this.memberId,
    required this.fonction,
    required this.dateDebut,
    this.dateFin,
    required this.statut,
    this.decisionId,
    this.createdAt,
  });

  bool get enCours => statut == 'en_cours';

  String get statutLabel => enCours ? 'En cours' : 'Terminé';

  factory Mandat.fromJson(Map<String, dynamic> json) => Mandat(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        fonction: json['fonction'] as String,
        dateDebut: json['date_debut'] as String,
        dateFin: json['date_fin'] as String?,
        statut: json['statut'] as String? ?? 'en_cours',
        decisionId: json['decision_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Procès-verbal (`proces_verbaux`, T10).
class ProcesVerbal {
  final String id;
  final String? reunionId;
  final String? numero;
  final String contenu;
  final String? datePv; // « AAAA-MM-JJ »
  final String? signataire;
  final String statut; // brouillon | signe | archive
  final DateTime? createdAt;

  const ProcesVerbal({
    required this.id,
    this.reunionId,
    this.numero,
    required this.contenu,
    this.datePv,
    this.signataire,
    required this.statut,
    this.createdAt,
  });

  String get statutLabel => switch (statut) {
        'signe' => 'Signé',
        'archive' => 'Archivé',
        _ => 'Brouillon',
      };

  factory ProcesVerbal.fromJson(Map<String, dynamic> json) => ProcesVerbal(
        id: json['id'] as String,
        reunionId: json['reunion_id'] as String?,
        numero: json['numero'] as String?,
        contenu: json['contenu'] as String,
        datePv: json['date_pv'] as String?,
        signataire: json['signataire'] as String?,
        statut: json['statut'] as String? ?? 'brouillon',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Document classé (`documents`, T10) : statuts, règlements, modèles et
/// courriers entrants / sortants.
class GouvernanceDocument {
  final String id;
  final String titre;
  final String categorie; // statuts | reglement | decision | courrier | modele | autre
  final String? sens; // entrant | sortant | interne
  final String? reference;
  final String? fichierUrl;
  final String? description;
  final String? dateDocument; // « AAAA-MM-JJ »
  final DateTime? createdAt;

  const GouvernanceDocument({
    required this.id,
    required this.titre,
    required this.categorie,
    this.sens,
    this.reference,
    this.fichierUrl,
    this.description,
    this.dateDocument,
    this.createdAt,
  });

  static String labelForCategorie(String categorie) => switch (categorie) {
        'statuts' => 'Statuts',
        'reglement' => 'Règlement',
        'decision' => 'Décision',
        'courrier' => 'Courrier',
        'modele' => 'Modèle',
        _ => 'Autre',
      };

  String get categorieLabel => labelForCategorie(categorie);

  static String labelForSens(String? sens) => switch (sens) {
        'entrant' => 'Entrant',
        'sortant' => 'Sortant',
        'interne' => 'Interne',
        _ => '—',
      };

  String get sensLabel => labelForSens(sens);

  factory GouvernanceDocument.fromJson(Map<String, dynamic> json) =>
      GouvernanceDocument(
        id: json['id'] as String,
        titre: json['titre'] as String,
        categorie: json['categorie'] as String? ?? 'autre',
        sens: json['sens'] as String?,
        reference: json['reference'] as String?,
        fichierUrl: json['fichier_url'] as String?,
        description: json['description'] as String?,
        dateDocument: json['date_document'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Bénéficiaire de l'action sociale (`beneficiaires`, T10).
class Beneficiaire {
  final String id;
  final String nom;
  final String? telephone;
  final String? adresse;
  final String? besoin;
  final String statut; // actif | clos
  final String? memberId;
  final DateTime? createdAt;

  const Beneficiaire({
    required this.id,
    required this.nom,
    this.telephone,
    this.adresse,
    this.besoin,
    required this.statut,
    this.memberId,
    this.createdAt,
  });

  String get statutLabel => statut == 'clos' ? 'Clos' : 'Actif';

  factory Beneficiaire.fromJson(Map<String, dynamic> json) => Beneficiaire(
        id: json['id'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String?,
        adresse: json['adresse'] as String?,
        besoin: json['besoin'] as String?,
        statut: json['statut'] as String? ?? 'actif',
        memberId: json['member_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Aide suivie (`aides`, T10).
class Aide {
  final String id;
  final String beneficiaireId;
  final String typeAide; // vivres | financier | medical | autre
  final int? montantFcfa;
  final String? dateAide; // « AAAA-MM-JJ »
  final String? description;
  final String statut; // prevue | versee | annulee
  final DateTime? createdAt;

  const Aide({
    required this.id,
    required this.beneficiaireId,
    required this.typeAide,
    this.montantFcfa,
    this.dateAide,
    this.description,
    required this.statut,
    this.createdAt,
  });

  static String labelForType(String type) => switch (type) {
        'vivres' => 'Vivres',
        'financier' => 'Financière',
        'medical' => 'Médicale',
        _ => 'Autre',
      };

  String get typeLabel => labelForType(typeAide);

  String get statutLabel => switch (statut) {
        'versee' => 'Versée',
        'annulee' => 'Annulée',
        _ => 'Prévue',
      };

  factory Aide.fromJson(Map<String, dynamic> json) => Aide(
        id: json['id'] as String,
        beneficiaireId: json['beneficiaire_id'] as String,
        typeAide: json['type_aide'] as String,
        montantFcfa: (json['montant_fcfa'] as num?)?.toInt(),
        dateAide: json['date_aide'] as String?,
        description: json['description'] as String?,
        statut: json['statut'] as String? ?? 'prevue',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Bien du patrimoine (`biens_patrimoine`, T10).
class BienPatrimoine {
  final String id;
  final String nom;
  final String categorie; // batiment | terrain | vehicule | equipement | autre
  final int? valeurFcfa;
  final String? assurance;
  final String? photoUrl;
  final String? codeInventaire;
  final DateTime? createdAt;

  const BienPatrimoine({
    required this.id,
    required this.nom,
    required this.categorie,
    this.valeurFcfa,
    this.assurance,
    this.photoUrl,
    this.codeInventaire,
    this.createdAt,
  });

  static String labelForCategorie(String categorie) => switch (categorie) {
        'batiment' => 'Bâtiment',
        'terrain' => 'Terrain',
        'vehicule' => 'Véhicule',
        'equipement' => 'Équipement',
        _ => 'Autre',
      };

  String get categorieLabel => labelForCategorie(categorie);

  factory BienPatrimoine.fromJson(Map<String, dynamic> json) =>
      BienPatrimoine(
        id: json['id'] as String,
        nom: json['nom'] as String,
        categorie: json['categorie'] as String,
        valeurFcfa: (json['valeur_fcfa'] as num?)?.toInt(),
        assurance: json['assurance'] as String?,
        photoUrl: json['photo_url'] as String?,
        codeInventaire: json['code_inventaire'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Maintenance d'un bien du patrimoine (`maintenance_patrimoine`, T10).
class MaintenancePatrimoine {
  final String id;
  final String bienId;
  final String? dateMaintenance; // « AAAA-MM-JJ »
  final String description;
  final int? coutFcfa;
  final String? realisePar;
  final String? depenseId;
  final DateTime? createdAt;

  const MaintenancePatrimoine({
    required this.id,
    required this.bienId,
    this.dateMaintenance,
    required this.description,
    this.coutFcfa,
    this.realisePar,
    this.depenseId,
    this.createdAt,
  });

  factory MaintenancePatrimoine.fromJson(Map<String, dynamic> json) =>
      MaintenancePatrimoine(
        id: json['id'] as String,
        bienId: json['bien_id'] as String,
        dateMaintenance: json['date_maintenance'] as String?,
        description: json['description'] as String,
        coutFcfa: (json['cout_fcfa'] as num?)?.toInt(),
        realisePar: json['realise_par'] as String?,
        depenseId: json['depense_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}
