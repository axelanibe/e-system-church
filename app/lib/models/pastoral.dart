import '../utils/format.dart';

/// Parcours d'un nouveau converti (`parcours_nouveaux` : accueil →
/// formation → baptême → intégration en cellule → intégré).
class ParcoursNouveau {
  final String id;
  final String memberId;
  final String etape; // accueil | formation | bapteme | integration_cellule | integre
  final String? dateEtape; // « AAAA-MM-JJ »
  final String? note;
  final DateTime? createdAt;

  const ParcoursNouveau({
    required this.id,
    required this.memberId,
    required this.etape,
    this.dateEtape,
    this.note,
    this.createdAt,
  });

  factory ParcoursNouveau.fromJson(Map<String, dynamic> json) =>
      ParcoursNouveau(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        etape: json['etape'] as String? ?? 'accueil',
        dateEtape: json['date_etape'] as String?,
        note: json['note'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForEtape(String etape) {
    switch (etape) {
      case 'accueil':
        return 'Accueil';
      case 'formation':
        return 'Formation';
      case 'bapteme':
        return 'Baptême';
      case 'integration_cellule':
        return 'Intégration en cellule';
      case 'integre':
        return 'Intégré';
      default:
        return etape;
    }
  }

  String get etapeLabel => labelForEtape(etape);
}

/// Visite pastorale (`visites_pastorales`).
class VisitePastorale {
  final String id;
  final String memberId;
  final String? visiteurId;
  final String dateVisite;
  final String? motif;
  final String? compteRendu;
  final String statut; // planifiee | realisee | annulee
  final DateTime? createdAt;

  const VisitePastorale({
    required this.id,
    required this.memberId,
    this.visiteurId,
    required this.dateVisite,
    this.motif,
    this.compteRendu,
    required this.statut,
    this.createdAt,
  });

  factory VisitePastorale.fromJson(Map<String, dynamic> json) =>
      VisitePastorale(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        visiteurId: json['visiteur_id'] as String?,
        dateVisite: json['date_visite'] as String,
        motif: json['motif'] as String?,
        compteRendu: json['compte_rendu'] as String?,
        statut: json['statut'] as String? ?? 'planifiee',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'planifiee':
        return 'Planifiée';
      case 'realisee':
        return 'Réalisée';
      case 'annulee':
        return 'Annulée';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Accompagnement pastoral (`accompagnements` : couple, famille, malade,
/// difficulté, autre).
class Accompagnement {
  final String id;
  final String memberId;
  final String type; // couple | famille | malade | difficulte | autre
  final String? accompagnateurId;
  final String? description;
  final String statut; // en_cours | termine
  final DateTime? createdAt;

  const Accompagnement({
    required this.id,
    required this.memberId,
    required this.type,
    this.accompagnateurId,
    this.description,
    required this.statut,
    this.createdAt,
  });

  factory Accompagnement.fromJson(Map<String, dynamic> json) =>
      Accompagnement(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        type: json['type'] as String,
        accompagnateurId: json['accompagnateur_id'] as String?,
        description: json['description'] as String?,
        statut: json['statut'] as String? ?? 'en_cours',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForType(String type) {
    switch (type) {
      case 'couple':
        return 'Couple';
      case 'famille':
        return 'Famille';
      case 'malade':
        return 'Malade';
      case 'difficulte':
        return 'Difficulté';
      default:
        return 'Autre';
    }
  }

  String get typeLabel => labelForType(type);
}
