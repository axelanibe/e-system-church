import '../utils/format.dart';

/// Confirmation « Je serai présent » d'un membre à un culte ou à une
/// activité (tables `culte_rsvp` / `activite_rsvp`, migrations 020 / 040) :
/// nom, matricule et date de confirmation. Une confirmation n'est pas
/// une présence pointée (`presences`).
class RsvpConfirmation {
  final String memberId;
  final String membreNom;
  final String? membreMatricule;
  final DateTime? createdAt;

  const RsvpConfirmation({
    required this.memberId,
    required this.membreNom,
    this.membreMatricule,
    this.createdAt,
  });

  factory RsvpConfirmation.fromJson(Map<String, dynamic> json) =>
      RsvpConfirmation(
        memberId: json['member_id'] as String,
        membreNom: json['membre_nom'] as String? ?? '',
        membreMatricule: json['membre_matricule'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Liste des confirmations pour un culte (`GET /cultes/:id/rsvp`) ou
/// une activité (`GET /activites/:id/rsvp`) : compteur + confirmés.
class RsvpListe {
  final int total;
  final List<RsvpConfirmation> confirmes;

  const RsvpListe({required this.total, required this.confirmes});

  factory RsvpListe.fromJson(Map<String, dynamic> json) => RsvpListe(
        total: (json['total'] as num?)?.toInt() ?? 0,
        confirmes: (json['confirmes'] as List<dynamic>? ?? [])
            .map((e) => RsvpConfirmation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
