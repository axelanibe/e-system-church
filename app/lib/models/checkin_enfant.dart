import '../utils/format.dart';

/// Check-in d'un enfant à l'école du dimanche, double QR ECODIM
/// (`checkins_enfants`) : arrivée jumelée bracelet parent-enfant,
/// sortie sécurisée par le code enfant, alerte silencieuse au parent.
class CheckinEnfant {
  final String id;
  final String enfantMemberId;
  final String parentMemberId;
  final String? salle;
  final String codeEnfant; // KIDS-XXXX, affiché #KIDS-XXXX
  final String? allergie;
  final String statut; // IN_CLASS | CHECKED_OUT
  final bool alerte;
  final String? alerteMessage;
  final DateTime? alerteAt;
  final String dateCheckin; // « AAAA-MM-JJ »
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;
  final String? enfantNom;
  final String? parentNom;

  const CheckinEnfant({
    required this.id,
    required this.enfantMemberId,
    required this.parentMemberId,
    this.salle,
    required this.codeEnfant,
    this.allergie,
    required this.statut,
    this.alerte = false,
    this.alerteMessage,
    this.alerteAt,
    required this.dateCheckin,
    this.checkedInAt,
    this.checkedOutAt,
    this.enfantNom,
    this.parentNom,
  });

  bool get enClasse => statut == 'IN_CLASS';

  /// Code tel qu'il figure sur le bracelet de l'enfant.
  String get codeAffiche => '#$codeEnfant';

  factory CheckinEnfant.fromJson(Map<String, dynamic> json) => CheckinEnfant(
        id: json['id'] as String,
        enfantMemberId: json['enfant_member_id'] as String,
        parentMemberId: json['parent_member_id'] as String,
        salle: json['salle'] as String?,
        codeEnfant: json['code_enfant'] as String,
        allergie: json['allergie'] as String?,
        statut: json['statut'] as String? ?? 'IN_CLASS',
        alerte: json['alerte'] as bool? ?? false,
        alerteMessage: json['alerte_message'] as String?,
        alerteAt: parseDate(json['alerte_at'] as String?),
        dateCheckin: json['date_checkin'] as String? ?? '',
        checkedInAt: parseDate(json['checked_in_at'] as String?),
        checkedOutAt: parseDate(json['checked_out_at'] as String?),
        enfantNom: json['enfant_nom'] as String?,
        parentNom: json['parent_nom'] as String?,
      );
}
