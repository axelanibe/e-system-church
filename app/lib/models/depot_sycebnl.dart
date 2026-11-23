import '../utils/format.dart';

/// Registres SYCEBNL et suivi du dépôt (tranche dépôt SYCEBNL,
/// migration 043).
///
/// L'immobilisation porte sa valeur nette calculée (valeur
/// d'acquisition moins amortissement cumulé). Les dettes et les
/// créances portent un statut en cours ou soldée. Le suivi du dépôt
/// est un par église et par exercice.

class Immobilisation {
  final String id;
  final String libelle;
  final String dateAcquisition;
  final int valeurAcquisition;
  final int amortissementCumule;

  const Immobilisation({
    required this.id,
    required this.libelle,
    required this.dateAcquisition,
    required this.valeurAcquisition,
    required this.amortissementCumule,
  });

  int get valeurNette => valeurAcquisition - amortissementCumule;

  factory Immobilisation.depuisJson(Map<String, dynamic> json) {
    return Immobilisation(
      id: json['id'] as String,
      libelle: json['libelle'] as String,
      dateAcquisition: json['date_acquisition'] as String,
      valeurAcquisition: (json['valeur_acquisition'] as num).toInt(),
      amortissementCumule: (json['amortissement_cumule'] as num).toInt(),
    );
  }

  String get dateAffichee =>
      afficherDate(parseDate(dateAcquisition) ?? DateTime.now());
}

class Dette {
  final String id;
  final String libelle;
  final int montant;
  final String? echeance;
  final String statut;

  const Dette({
    required this.id,
    required this.libelle,
    required this.montant,
    required this.echeance,
    required this.statut,
  });

  bool get estSoldee => statut == 'soldee';

  String get statutLibelle => estSoldee ? 'Soldée' : 'En cours';

  factory Dette.depuisJson(Map<String, dynamic> json) {
    return Dette(
      id: json['id'] as String,
      libelle: json['libelle'] as String,
      montant: (json['montant'] as num).toInt(),
      echeance: json['echeance'] as String?,
      statut: json['statut'] as String,
    );
  }

  String get echeanceAffichee =>
      echeance == null
          ? 'Sans échéance'
          : afficherDate(parseDate(echeance!) ?? DateTime.now());
}

class Creance {
  final String id;
  final String libelle;
  final int montant;
  final String? echeance;
  final String statut;

  const Creance({
    required this.id,
    required this.libelle,
    required this.montant,
    required this.echeance,
    required this.statut,
  });

  bool get estSoldee => statut == 'soldee';

  String get statutLibelle => estSoldee ? 'Soldée' : 'En cours';

  factory Creance.depuisJson(Map<String, dynamic> json) {
    return Creance(
      id: json['id'] as String,
      libelle: json['libelle'] as String,
      montant: (json['montant'] as num).toInt(),
      echeance: json['echeance'] as String?,
      statut: json['statut'] as String,
    );
  }

  String get echeanceAffichee =>
      echeance == null
          ? 'Sans échéance'
          : afficherDate(parseDate(echeance!) ?? DateTime.now());
}

class NoteAnnexe {
  final String id;
  final String titre;
  final String contenu;
  final int exercice;

  const NoteAnnexe({
    required this.id,
    required this.titre,
    required this.contenu,
    required this.exercice,
  });

  factory NoteAnnexe.depuisJson(Map<String, dynamic> json) {
    return NoteAnnexe(
      id: json['id'] as String,
      titre: json['titre'] as String,
      contenu: json['contenu'] as String,
      exercice: (json['exercice'] as num).toInt(),
    );
  }
}

/// Suivi du dépôt d'un exercice : statut, date de dépôt, référence
/// libre (par exemple numéro de reçu e-impots). Nul tant que l'admin
/// n'a rien enregistré pour l'exercice.
class SuiviDepotSycebnl {
  final int exercice;
  final String statut;
  final String? dateDepot;
  final String? reference;

  const SuiviDepotSycebnl({
    required this.exercice,
    required this.statut,
    required this.dateDepot,
    required this.reference,
  });

  bool get estDepose => statut == 'depose';

  String get statutLibelle =>
      switch (statut) {
        'pret' => 'Prêt',
        'depose' => 'Déposé',
        _ => 'À préparer',
      };

  factory SuiviDepotSycebnl.depuisJson(Map<String, dynamic> json) {
    return SuiviDepotSycebnl(
      exercice: (json['exercice'] as num).toInt(),
      statut: json['statut'] as String,
      dateDepot: json['date_depot'] as String?,
      reference: json['reference'] as String?,
    );
  }
}

/// Réponse de GET /sycebnl/depot : ressources annuelles, seuil,
/// dépôt requis ou non, échéance du 30 mai de l'année suivante,
/// suivi de l'exercice (nul si rien n'est enregistré).
class DepotSycebnl {
  final int annee;
  final int ressources;
  final int seuil;
  final bool requis;
  final String echeance;
  final SuiviDepotSycebnl? suivi;

  const DepotSycebnl({
    required this.annee,
    required this.ressources,
    required this.seuil,
    required this.requis,
    required this.echeance,
    required this.suivi,
  });

  DateTime get echeanceDate =>
      parseDate(echeance) ?? DateTime(annee + 1, 5, 30);

  String get echeanceAffichee => afficherDate(echeanceDate);

  factory DepotSycebnl.depuisJson(Map<String, dynamic> json) {
    return DepotSycebnl(
      annee: (json['annee'] as num).toInt(),
      ressources: (json['ressources'] as num).toInt(),
      seuil: (json['seuil'] as num).toInt(),
      requis: json['requis'] as bool,
      echeance: json['echeance'] as String,
      suivi:
          json['suivi'] == null
              ? null
              : SuiviDepotSycebnl.depuisJson(
                json['suivi'] as Map<String, dynamic>,
              ),
    );
  }
}
