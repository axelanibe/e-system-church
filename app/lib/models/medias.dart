import '../utils/format.dart';

/// Prédication enregistrée (`predications` : audio et/ou vidéo).
class Predication {
  final String id;
  final String titre;
  final String? orateur;
  final String datePredication; // « AAAA-MM-JJ »
  final String? culteId;
  final String? serie;
  final String? urlAudio;
  final String? urlVideo;
  final int? dureeMinutes;
  final DateTime? createdAt;

  const Predication({
    required this.id,
    required this.titre,
    this.orateur,
    required this.datePredication,
    this.culteId,
    this.serie,
    this.urlAudio,
    this.urlVideo,
    this.dureeMinutes,
    this.createdAt,
  });

  factory Predication.fromJson(Map<String, dynamic> json) => Predication(
        id: json['id'] as String,
        titre: json['titre'] as String,
        orateur: json['orateur'] as String?,
        datePredication: json['date_predication'] as String,
        culteId: json['culte_id'] as String?,
        serie: json['serie'] as String?,
        urlAudio: json['url_audio'] as String?,
        urlVideo: json['url_video'] as String?,
        dureeMinutes: (json['duree_minutes'] as num?)?.toInt(),
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Plan de lecture de la Bible (`plans_lecture`).
class PlanLecture {
  final String id;
  final String nom;
  final String? description;
  final int? dureeJours;
  final bool actif;
  final DateTime? createdAt;

  const PlanLecture({
    required this.id,
    required this.nom,
    this.description,
    this.dureeJours,
    this.actif = true,
    this.createdAt,
  });

  factory PlanLecture.fromJson(Map<String, dynamic> json) => PlanLecture(
        id: json['id'] as String,
        nom: json['nom'] as String,
        description: json['description'] as String?,
        dureeJours: (json['duree_jours'] as num?)?.toInt(),
        actif: json['actif'] as bool? ?? true,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Livre de la bibliothèque (`livres`).
class Livre {
  final String id;
  final String titre;
  final String? auteur;
  final String? categorie;
  final String? isbn;
  final int exemplaires;
  final DateTime? createdAt;

  const Livre({
    required this.id,
    required this.titre,
    this.auteur,
    this.categorie,
    this.isbn,
    required this.exemplaires,
    this.createdAt,
  });

  factory Livre.fromJson(Map<String, dynamic> json) => Livre(
        id: json['id'] as String,
        titre: json['titre'] as String,
        auteur: json['auteur'] as String?,
        categorie: json['categorie'] as String?,
        isbn: json['isbn'] as String?,
        exemplaires: (json['exemplaires'] as num?)?.toInt() ?? 1,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Prêt d'un livre (`prets_livres`).
class PretLivre {
  final String id;
  final String livreId;
  final String memberId;
  final String? datePret; // « AAAA-MM-JJ »
  final String? dateRetourPrevue; // « AAAA-MM-JJ »
  final String? dateRetour; // « AAAA-MM-JJ »
  final String statut; // en_cours | rendu | en_retard
  final DateTime? createdAt;

  const PretLivre({
    required this.id,
    required this.livreId,
    required this.memberId,
    this.datePret,
    this.dateRetourPrevue,
    this.dateRetour,
    required this.statut,
    this.createdAt,
  });

  factory PretLivre.fromJson(Map<String, dynamic> json) => PretLivre(
        id: json['id'] as String,
        livreId: json['livre_id'] as String,
        memberId: json['member_id'] as String,
        datePret: json['date_pret'] as String?,
        dateRetourPrevue: json['date_retour_prevue'] as String?,
        dateRetour: json['date_retour'] as String?,
        statut: json['statut'] as String? ?? 'en_cours',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'en_cours':
        return 'En cours';
      case 'rendu':
        return 'Rendu';
      case 'en_retard':
        return 'En retard';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}
