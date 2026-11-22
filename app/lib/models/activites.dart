import '../utils/format.dart';

/// Activité à venir (`activites`) : titre, description facultative,
/// date et heure, lieu, responsable (nom libre), statut brouillon ou
/// publié. Pas de présence, pas de notification en V1.
class Activite {
  final String id;
  final String titre;
  final String? description;
  final String dateHeure; // ISO « AAAA-MM-JJTHH:MM »
  final String? lieu;
  final String? responsable;
  final String statut; // brouillon | publié
  final DateTime? createdAt;
  /// Le fidèle a confirmé sa présence à cette activité
  /// (« Je serai présent », table activite_rsvp, migration 040).
  /// Faux sans confirmation.
  final bool seraiPresent;

  const Activite({
    required this.id,
    required this.titre,
    this.description,
    required this.dateHeure,
    this.lieu,
    this.responsable,
    this.statut = 'brouillon',
    this.createdAt,
    this.seraiPresent = false,
  });

  factory Activite.fromJson(Map<String, dynamic> json) => Activite(
        id: json['id'] as String,
        titre: json['titre'] as String,
        description: json['description'] as String?,
        dateHeure: json['date_heure'] as String,
        lieu: json['lieu'] as String?,
        responsable: json['responsable'] as String?,
        statut: json['statut'] as String? ?? 'brouillon',
        createdAt: parseDate(json['created_at'] as String?),
        seraiPresent: json['serai_present'] as bool? ?? false,
      );

  DateTime? get date => parseDate(dateHeure);

  bool get publiee => statut == 'publié';
}
