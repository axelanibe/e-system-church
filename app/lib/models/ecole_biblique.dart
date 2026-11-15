import '../utils/format.dart';

/// École biblique : cours, leçons, inscriptions et progression.
/// Le contenu des cours et des leçons est créé par l'église (admin /
/// responsable de culte), jamais pré-rempli.

/// Un cours (`cours_ecole`).
class CoursEcole {
  final String id;
  final String titre;
  final String? description;
  final String? niveau; // debutant | intermediaire | avance
  final bool actif;
  final DateTime? createdAt;

  const CoursEcole({
    required this.id,
    required this.titre,
    this.description,
    this.niveau,
    this.actif = true,
    this.createdAt,
  });

  factory CoursEcole.fromJson(Map<String, dynamic> json) => CoursEcole(
        id: json['id'] as String,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        niveau: json['niveau'] as String?,
        actif: json['actif'] as bool? ?? true,
        createdAt: parseDate(json['created_at'] as String?),
      );

  String get niveauLabel => switch (niveau) {
        'debutant' => 'Débutant',
        'intermediaire' => 'Intermédiaire',
        'avance' => 'Avancé',
        _ => 'Tous niveaux',
      };
}

/// Une leçon d'un cours (`lecons_ecole`).
class LeconEcole {
  final String id;
  final String coursId;
  final int ordre;
  final String titre;
  final String? contenu;
  final String? referenceBiblique;
  final DateTime? createdAt;

  const LeconEcole({
    required this.id,
    required this.coursId,
    required this.ordre,
    required this.titre,
    this.contenu,
    this.referenceBiblique,
    this.createdAt,
  });

  factory LeconEcole.fromJson(Map<String, dynamic> json) => LeconEcole(
        id: json['id'] as String,
        coursId: json['cours_id'] as String,
        ordre: (json['ordre'] as num).toInt(),
        titre: json['titre'] as String,
        contenu: json['contenu'] as String?,
        referenceBiblique: json['reference_biblique'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Une inscription à un cours (`inscriptions_ecole`).
class InscriptionEcole {
  final String id;
  final String coursId;
  final String memberId;
  final String statut; // inscrit | termine | abandonne
  final String? dateInscription; // « AAAA-MM-JJ »
  final DateTime? createdAt;

  const InscriptionEcole({
    required this.id,
    required this.coursId,
    required this.memberId,
    required this.statut,
    this.dateInscription,
    this.createdAt,
  });

  factory InscriptionEcole.fromJson(Map<String, dynamic> json) =>
      InscriptionEcole(
        id: json['id'] as String,
        coursId: json['cours_id'] as String,
        memberId: json['member_id'] as String,
        statut: json['statut'] as String,
        dateInscription: json['date_inscription'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  String get statutLabel => switch (statut) {
        'termine' => 'Terminé',
        'abandonne' => 'Abandonné',
        _ => 'Inscrit',
      };
}

/// Une leçon avec son état d'avancement pour une inscription.
class ProgressionLecon {
  final String id;
  final int ordre;
  final String titre;
  final String? referenceBiblique;
  final bool termine;
  final DateTime? termineLe;

  const ProgressionLecon({
    required this.id,
    required this.ordre,
    required this.titre,
    this.referenceBiblique,
    required this.termine,
    this.termineLe,
  });

  factory ProgressionLecon.fromJson(Map<String, dynamic> json) =>
      ProgressionLecon(
        id: json['id'] as String,
        ordre: (json['ordre'] as num).toInt(),
        titre: json['titre'] as String,
        referenceBiblique: json['reference_biblique'] as String?,
        termine: json['termine'] as bool? ?? false,
        termineLe: parseDate(json['termine_le'] as String?),
      );
}

/// Le détail de progression d'une inscription : leçons + avancement.
class ProgressionCours {
  final InscriptionEcole inscription;
  final List<ProgressionLecon> lecons;
  final int terminees;
  final int total;
  final int pourcentage;

  const ProgressionCours({
    required this.inscription,
    required this.lecons,
    required this.terminees,
    required this.total,
    required this.pourcentage,
  });

  factory ProgressionCours.fromJson(Map<String, dynamic> json) =>
      ProgressionCours(
        inscription:
            InscriptionEcole.fromJson(json['inscription'] as Map<String, dynamic>),
        lecons: (json['lecons'] as List)
            .map((l) => ProgressionLecon.fromJson(l as Map<String, dynamic>))
            .toList(),
        terminees: (json['terminees'] as num).toInt(),
        total: (json['total'] as num).toInt(),
        pourcentage: (json['pourcentage'] as num).toInt(),
      );
}
