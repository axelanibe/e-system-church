import '../utils/format.dart';

/// Pointage d'un membre à un culte ou à un événement (`presences`).
class Presence {
  final String id;
  final String? eventId;
  final String? culteId;
  final String memberId;
  final String statut; // present | absent | excuse
  final String mode; // manuel | liste | scan_qr
  final DateTime? pointeAt;
  final String? membreNom;

  const Presence({
    required this.id,
    this.eventId,
    this.culteId,
    required this.memberId,
    required this.statut,
    required this.mode,
    this.pointeAt,
    this.membreNom,
  });

  factory Presence.fromJson(Map<String, dynamic> json) => Presence(
        id: json['id'] as String,
        eventId: json['event_id'] as String?,
        culteId: json['culte_id'] as String?,
        memberId: json['member_id'] as String,
        statut: json['statut'] as String? ?? 'present',
        mode: json['mode'] as String? ?? 'manuel',
        pointeAt: parseDate(json['pointe_at'] as String?),
        membreNom: json['membre_nom'] as String?,
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'present':
        return 'Présent';
      case 'absent':
        return 'Absent';
      case 'excuse':
        return 'Excusé';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Statistiques de présence (`GET /presences/stats` :
/// `{ global: { total, presents, absents, excuses },
///    par_culte: […], par_membre: […] }`).
class PresenceStats {
  final int total;
  final int presents;
  final int absents;
  final int excuses;
  final List<Map<String, dynamic>> parCulte;
  final List<Map<String, dynamic>> parMembre;

  const PresenceStats({
    required this.total,
    required this.presents,
    required this.absents,
    required this.excuses,
    required this.parCulte,
    required this.parMembre,
  });

  factory PresenceStats.fromJson(Map<String, dynamic> json) {
    final global = json['global'] as Map<String, dynamic>? ?? json;
    return PresenceStats(
      total: (global['total'] as num?)?.toInt() ?? 0,
      presents: (global['presents'] as num?)?.toInt() ?? 0,
      absents: (global['absents'] as num?)?.toInt() ?? 0,
      excuses: (global['excuses'] as num?)?.toInt() ?? 0,
      parCulte: (json['par_culte'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      parMembre: (json['par_membre'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// Taux de présence (0 à 1), 0 si aucune présence enregistrée.
  double get tauxPresence => total == 0 ? 0 : presents / total;
}
