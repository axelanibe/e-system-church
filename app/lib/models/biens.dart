import '../utils/format.dart';

/// Salle de l'église (`salles`).
class Salle {
  final String id;
  final String nom;
  final int? capacite;
  final String? description;
  final DateTime? createdAt;

  const Salle({
    required this.id,
    required this.nom,
    this.capacite,
    this.description,
    this.createdAt,
  });

  factory Salle.fromJson(Map<String, dynamic> json) => Salle(
        id: json['id'] as String,
        nom: json['nom'] as String,
        capacite: (json['capacite'] as num?)?.toInt(),
        description: json['description'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Réservation d'une salle (`reservations_salles`).
class ReservationSalle {
  final String id;
  final String salleId;
  final String titre;
  final String debut;
  final String fin;
  final String? reservePar;
  final String statut; // confirmee | annulee
  final DateTime? createdAt;

  const ReservationSalle({
    required this.id,
    required this.salleId,
    required this.titre,
    required this.debut,
    required this.fin,
    this.reservePar,
    required this.statut,
    this.createdAt,
  });

  /// Libellé lisible du statut, jamais la valeur brute.
  String get statutLabel =>
      switch (statut) { 'annulee' => 'Annulée', _ => 'Confirmée' };

  factory ReservationSalle.fromJson(Map<String, dynamic> json) =>
      ReservationSalle(
        id: json['id'] as String,
        salleId: json['salle_id'] as String,
        titre: json['titre'] as String,
        debut: json['debut'] as String,
        fin: json['fin'] as String,
        reservePar: json['reserve_par'] as String?,
        statut: json['statut'] as String? ?? 'confirmee',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Matériel inventorié (`materiel`).
class Materiel {
  final String id;
  final String nom;
  final String? categorie;
  final int quantite;
  final String etat; // bon | a_reparer | hors_service
  final String? responsableMemberId;
  final DateTime? createdAt;

  const Materiel({
    required this.id,
    required this.nom,
    this.categorie,
    required this.quantite,
    required this.etat,
    this.responsableMemberId,
    this.createdAt,
  });

  factory Materiel.fromJson(Map<String, dynamic> json) => Materiel(
        id: json['id'] as String,
        nom: json['nom'] as String,
        categorie: json['categorie'] as String?,
        quantite: (json['quantite'] as num?)?.toInt() ?? 1,
        etat: json['etat'] as String? ?? 'bon',
        responsableMemberId: json['responsable_member_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForEtat(String etat) {
    switch (etat) {
      case 'bon':
        return 'Bon état';
      case 'a_reparer':
        return 'À réparer';
      case 'hors_service':
        return 'Hors service';
      default:
        return etat;
    }
  }

  String get etatLabel => labelForEtat(etat);
}

/// Maintenance d'un matériel (`maintenance_materiel`).
class MaintenanceMateriel {
  final String id;
  final String materielId;
  final String? dateMaintenance; // « AAAA-MM-JJ »
  final String description;
  final int? coutFcfa;
  final String? realisePar;
  final DateTime? createdAt;

  const MaintenanceMateriel({
    required this.id,
    required this.materielId,
    this.dateMaintenance,
    required this.description,
    this.coutFcfa,
    this.realisePar,
    this.createdAt,
  });

  factory MaintenanceMateriel.fromJson(Map<String, dynamic> json) =>
      MaintenanceMateriel(
        id: json['id'] as String,
        materielId: json['materiel_id'] as String,
        dateMaintenance: json['date_maintenance'] as String?,
        description: json['description'] as String,
        coutFcfa: (json['cout_fcfa'] as num?)?.toInt(),
        realisePar: json['realise_par'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}
