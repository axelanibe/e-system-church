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
  final String? type; // domicile | hopital (T6, nullable : anciennes visites)
  final String? lieu; // T6
  final String statut; // planifiee | realisee | annulee
  final DateTime? createdAt;

  const VisitePastorale({
    required this.id,
    required this.memberId,
    this.visiteurId,
    required this.dateVisite,
    this.motif,
    this.compteRendu,
    this.type,
    this.lieu,
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
        type: json['type'] as String?,
        lieu: json['lieu'] as String?,
        statut: json['statut'] as String? ?? 'planifiee',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForType(String? type) {
    switch (type) {
      case 'domicile':
        return 'Domicile';
      case 'hopital':
        return 'Hôpital';
      default:
        return 'Non précisé';
    }
  }

  String get typeLabel => labelForType(type);

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
  final String priorite; // basse | normale | haute | urgente (T6)
  final String statut; // en_cours | termine
  final DateTime? createdAt;

  const Accompagnement({
    required this.id,
    required this.memberId,
    required this.type,
    this.accompagnateurId,
    this.description,
    this.priorite = 'normale',
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
        priorite: json['priorite'] as String? ?? 'normale',
        statut: json['statut'] as String? ?? 'en_cours',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForPriorite(String priorite) {
    switch (priorite) {
      case 'basse':
        return 'Basse';
      case 'haute':
        return 'Haute';
      case 'urgente':
        return 'Urgente';
      default:
        return 'Normale';
    }
  }

  String get prioriteLabel => labelForPriorite(priorite);

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

/// Rencontre d'accompagnement datée (`rencontres_accompagnement`, T6) :
/// un accompagnement peut avoir plusieurs rencontres, chacune datée.
class RencontreAccompagnement {
  final String id;
  final String accompagnementId;
  final String dateRencontre; // AAAA-MM-JJ
  final String? note;
  final DateTime? createdAt;

  const RencontreAccompagnement({
    required this.id,
    required this.accompagnementId,
    required this.dateRencontre,
    this.note,
    this.createdAt,
  });

  factory RencontreAccompagnement.fromJson(Map<String, dynamic> json) =>
      RencontreAccompagnement(
        id: json['id'] as String,
        accompagnementId: json['accompagnement_id'] as String,
        dateRencontre: json['date_rencontre'] as String,
        note: json['note'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Alerte du radar des absences consécutives (T6, vue calculée
/// `v_radar_absences`, `GET /radar-absences`) : l'alerte et la visite
/// suggérée sont calculées par le serveur, jamais inventées ici.
class AlerteRadar {
  final String memberId;
  final String membreNom;
  final String? membreMatricule;
  final String? membreTelephone;
  final int absencesConsecutives;
  final String? dernierePresence; // AAAA-MM-JJ ou null (jamais vu)
  final String alerte;
  final String? visiteType; // domicile (suggérée)
  final String? visiteMotif;

  const AlerteRadar({
    required this.memberId,
    required this.membreNom,
    this.membreMatricule,
    this.membreTelephone,
    required this.absencesConsecutives,
    this.dernierePresence,
    required this.alerte,
    this.visiteType,
    this.visiteMotif,
  });

  factory AlerteRadar.fromJson(Map<String, dynamic> json) {
    final suggeree = json['visite_suggeree'] as Map<String, dynamic>?;
    final derniere = json['derniere_presence'] as String?;
    return AlerteRadar(
      memberId: json['member_id'] as String,
      membreNom: json['membre_nom'] as String,
      membreMatricule: json['membre_matricule'] as String?,
      membreTelephone: json['membre_telephone'] as String?,
      absencesConsecutives: json['absences_consecutives'] as int? ?? 0,
      dernierePresence:
          derniere != null && derniere.length >= 10 ? derniere.substring(0, 10) : derniere,
      alerte: json['alerte'] as String? ?? '',
      visiteType: suggeree?['type'] as String?,
      visiteMotif: suggeree?['motif'] as String?,
    );
  }
}
