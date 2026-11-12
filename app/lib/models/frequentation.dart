import '../utils/format.dart';
import 'presences.dart';

/// Pointage d'un membre avec le titre et la date du culte ou de
/// l'événement (`GET /membres/:id/frequentation`).
class FrequentationItem {
  final String id;
  final String statut; // present | absent | excuse
  final String mode; // manuel | liste | scan_qr
  final DateTime? pointeAt;
  final String? titre;
  final DateTime? dateEvenement;
  final String type; // culte | evenement

  const FrequentationItem({
    required this.id,
    required this.statut,
    required this.mode,
    this.pointeAt,
    this.titre,
    this.dateEvenement,
    required this.type,
  });

  factory FrequentationItem.fromJson(Map<String, dynamic> json) =>
      FrequentationItem(
        id: json['id'] as String,
        statut: json['statut'] as String? ?? 'present',
        mode: json['mode'] as String? ?? 'manuel',
        pointeAt: parseDate(json['pointe_at'] as String?),
        titre: json['titre'] as String?,
        dateEvenement: parseDate(json['date_evenement'] as String?),
        type: json['type'] as String? ?? 'culte',
      );

  String get statutLabel => Presence.labelForStatut(statut);
}

/// Fréquentation d'un membre : total des pointages et nombre de présents.
class Frequentation {
  final int total;
  final int presents;
  final List<FrequentationItem> items;

  const Frequentation({required this.total, required this.presents, required this.items});

  factory Frequentation.fromJson(Map<String, dynamic> json) => Frequentation(
        total: (json['total'] as num?)?.toInt() ?? 0,
        presents: (json['presents'] as num?)?.toInt() ?? 0,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => FrequentationItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
