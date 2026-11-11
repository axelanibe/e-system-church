import '../utils/format.dart';

/// Serviteur : membre affecté à un département (`serviteurs`).
class Serviteur {
  final String id;
  final String memberId;
  final String departementId;
  final String role;
  final String? disponibilite;
  final bool actif;
  final DateTime? createdAt;

  const Serviteur({
    required this.id,
    required this.memberId,
    required this.departementId,
    required this.role,
    this.disponibilite,
    this.actif = true,
    this.createdAt,
  });

  factory Serviteur.fromJson(Map<String, dynamic> json) => Serviteur(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        departementId: json['departement_id'] as String,
        role: json['role'] as String? ?? 'serviteur',
        disponibilite: json['disponibilite'] as String?,
        actif: json['actif'] as bool? ?? true,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Affectation d'un serviteur à un culte ou un événement
/// (`planning_serviteurs`).
class PlanningServiteur {
  final String id;
  final String serviteurId;
  final String? culteId;
  final String? eventId;
  final String dateService; // « AAAA-MM-JJ »
  final String? roleService;
  final String statut; // prevu | confirme | absent
  final DateTime? createdAt;

  const PlanningServiteur({
    required this.id,
    required this.serviteurId,
    this.culteId,
    this.eventId,
    required this.dateService,
    this.roleService,
    required this.statut,
    this.createdAt,
  });

  factory PlanningServiteur.fromJson(Map<String, dynamic> json) =>
      PlanningServiteur(
        id: json['id'] as String,
        serviteurId: json['serviteur_id'] as String,
        culteId: json['culte_id'] as String?,
        eventId: json['event_id'] as String?,
        dateService: json['date_service'] as String,
        roleService: json['role_service'] as String?,
        statut: json['statut'] as String? ?? 'prevu',
        createdAt: parseDate(json['created_at'] as String?),
      );
}
