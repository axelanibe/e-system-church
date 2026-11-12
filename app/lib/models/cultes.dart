import '../utils/format.dart';

/// Type de culte récurrent (`culte_types`).
class CulteType {
  final String id;
  final String nom;
  final int? jourSemaine; // 0 = dimanche … 6 = samedi
  final String? heureDebut;
  final int? dureeMinutes;
  final String? lieu;
  final bool actif;
  final DateTime? createdAt;

  const CulteType({
    required this.id,
    required this.nom,
    this.jourSemaine,
    this.heureDebut,
    this.dureeMinutes,
    this.lieu,
    this.actif = true,
    this.createdAt,
  });

  factory CulteType.fromJson(Map<String, dynamic> json) => CulteType(
        id: json['id'] as String,
        nom: json['nom'] as String,
        jourSemaine: (json['jour_semaine'] as num?)?.toInt(),
        heureDebut: json['heure_debut'] as String?,
        dureeMinutes: (json['duree_minutes'] as num?)?.toInt(),
        lieu: json['lieu'] as String?,
        actif: json['actif'] as bool? ?? true,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Culte daté (`cultes`).
class Culte {
  final String id;
  final String? culteTypeId;
  final String titre;
  final String dateHeure; // ISO « AAAA-MM-JJTHH:MM »
  final String? lieu;
  final String? orateur;
  final String? theme;
  final DateTime? createdAt;
  /// Le fidèle a confirmé sa présence à ce culte (« Je serai présent »,
  /// table culte_rsvp, migration 020). Faux sans confirmation.
  final bool seraiPresent;

  const Culte({
    required this.id,
    this.culteTypeId,
    required this.titre,
    required this.dateHeure,
    this.lieu,
    this.orateur,
    this.theme,
    this.createdAt,
    this.seraiPresent = false,
  });

  factory Culte.fromJson(Map<String, dynamic> json) => Culte(
        id: json['id'] as String,
        culteTypeId: json['culte_type_id'] as String?,
        titre: json['titre'] as String,
        dateHeure: json['date_heure'] as String,
        lieu: json['lieu'] as String?,
        orateur: json['orateur'] as String?,
        theme: json['theme'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
        seraiPresent: json['serai_present'] as bool? ?? false,
      );

  DateTime? get date => parseDate(dateHeure);
}

/// Élément de l'ordre d'un culte (`ordre_culte_items`).
class OrdreCulteItem {
  final String id;
  final String culteId;
  final int ordre;
  final String titre;
  final String? description;
  final String? intervenant;
  final int? dureeMinutes;
  final DateTime? createdAt;

  const OrdreCulteItem({
    required this.id,
    required this.culteId,
    required this.ordre,
    required this.titre,
    this.description,
    this.intervenant,
    this.dureeMinutes,
    this.createdAt,
  });

  factory OrdreCulteItem.fromJson(Map<String, dynamic> json) =>
      OrdreCulteItem(
        id: json['id'] as String,
        culteId: json['culte_id'] as String,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        intervenant: json['intervenant'] as String?,
        dureeMinutes: (json['duree_minutes'] as num?)?.toInt(),
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Événement spécial (`evenements_speciaux` : mariage, baptême d'eau,
/// dédicace, funérailles, conférence…).
class EvenementSpecial {
  final String id;
  final String type; // mariage | bapteme_eau | dedicace_enfant | funerailles | conference | campagne | jeune | autre
  final String titre;
  final String? description;
  final String dateDebut;
  final String? dateFin;
  final String? lieu;
  final String? responsable;
  final DateTime? createdAt;

  const EvenementSpecial({
    required this.id,
    required this.type,
    required this.titre,
    this.description,
    required this.dateDebut,
    this.dateFin,
    this.lieu,
    this.responsable,
    this.createdAt,
  });

  factory EvenementSpecial.fromJson(Map<String, dynamic> json) =>
      EvenementSpecial(
        id: json['id'] as String,
        type: json['type'] as String,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        dateDebut: json['date_debut'] as String,
        dateFin: json['date_fin'] as String?,
        lieu: json['lieu'] as String?,
        responsable: json['responsable'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForType(String type) {
    switch (type) {
      case 'mariage':
        return 'Mariage';
      case 'bapteme_eau':
        return 'Baptême d’eau';
      case 'dedicace_enfant':
        return 'Dédicace d’enfant';
      case 'funerailles':
        return 'Funérailles';
      case 'conference':
        return 'Conférence';
      case 'campagne':
        return 'Campagne';
      case 'jeune':
        return 'Jeûne';
      default:
        return 'Autre';
    }
  }

  String get typeLabel => labelForType(type);
}
