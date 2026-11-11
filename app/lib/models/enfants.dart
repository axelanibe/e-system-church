import '../utils/format.dart';

/// Classe de l'école du dimanche (`classes_enfants`).
class ClasseEnfant {
  final String id;
  final String nom;
  final int? ageMin;
  final int? ageMax;
  final String? salle;
  final DateTime? createdAt;

  const ClasseEnfant({
    required this.id,
    required this.nom,
    this.ageMin,
    this.ageMax,
    this.salle,
    this.createdAt,
  });

  factory ClasseEnfant.fromJson(Map<String, dynamic> json) => ClasseEnfant(
        id: json['id'] as String,
        nom: json['nom'] as String,
        ageMin: (json['age_min'] as num?)?.toInt(),
        ageMax: (json['age_max'] as num?)?.toInt(),
        salle: json['salle'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Enseignant (ou assistant) d'une classe d'enfants
/// (`enseignants_classes`).
class EnseignantClasse {
  final String id;
  final String classeId;
  final String memberId;
  final String role; // enseignant | assistant
  final DateTime? createdAt;

  const EnseignantClasse({
    required this.id,
    required this.classeId,
    required this.memberId,
    required this.role,
    this.createdAt,
  });

  factory EnseignantClasse.fromJson(Map<String, dynamic> json) =>
      EnseignantClasse(
        id: json['id'] as String,
        classeId: json['classe_id'] as String,
        memberId: json['member_id'] as String,
        role: json['role'] as String? ?? 'enseignant',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Autorisation parentale de sortie d'un enfant
/// (`autorisations_sorties`).
class AutorisationSortie {
  final String id;
  final String enfantMemberId;
  final String? parentMemberId;
  final String activite;
  final String dateSortie; // « AAAA-MM-JJ »
  final String statut; // en_attente | autorisee | refusee
  final DateTime? createdAt;

  const AutorisationSortie({
    required this.id,
    required this.enfantMemberId,
    this.parentMemberId,
    required this.activite,
    required this.dateSortie,
    required this.statut,
    this.createdAt,
  });

  factory AutorisationSortie.fromJson(Map<String, dynamic> json) =>
      AutorisationSortie(
        id: json['id'] as String,
        enfantMemberId: json['enfant_member_id'] as String,
        parentMemberId: json['parent_member_id'] as String?,
        activite: json['activite'] as String,
        dateSortie: json['date_sortie'] as String,
        statut: json['statut'] as String? ?? 'en_attente',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'en_attente':
        return 'En attente';
      case 'autorisee':
        return 'Autorisée';
      case 'refusee':
        return 'Refusée';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Activité de la jeunesse (`activites_jeunesse`).
class ActiviteJeunesse {
  final String id;
  final String titre;
  final String? description;
  final String dateActivite;
  final String? lieu;
  final String? responsableMemberId;
  final DateTime? createdAt;

  const ActiviteJeunesse({
    required this.id,
    required this.titre,
    this.description,
    required this.dateActivite,
    this.lieu,
    this.responsableMemberId,
    this.createdAt,
  });

  factory ActiviteJeunesse.fromJson(Map<String, dynamic> json) =>
      ActiviteJeunesse(
        id: json['id'] as String,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        dateActivite: json['date_activite'] as String,
        lieu: json['lieu'] as String?,
        responsableMemberId: json['responsable_member_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}
