import '../utils/format.dart';

/// Demande de prière (`demandes_priere`).
class DemandePriere {
  final String id;
  final String? memberId;
  final String? demandeurNom;
  final String sujet;
  final String? details;
  final bool confidentiel;
  final String statut; // nouvelle | en_cours | terminee
  final DateTime? createdAt;

  const DemandePriere({
    required this.id,
    this.memberId,
    this.demandeurNom,
    required this.sujet,
    this.details,
    this.confidentiel = false,
    required this.statut,
    this.createdAt,
  });

  factory DemandePriere.fromJson(Map<String, dynamic> json) => DemandePriere(
        id: json['id'] as String,
        memberId: json['member_id'] as String?,
        demandeurNom: json['demandeur_nom'] as String?,
        sujet: json['sujet'] as String,
        details: json['details'] as String?,
        confidentiel: json['confidentiel'] as bool? ?? false,
        statut: json['statut'] as String? ?? 'nouvelle',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'nouvelle':
        return 'Nouvelle';
      case 'en_cours':
        return 'En cours';
      case 'terminee':
        return 'Terminée';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Message interne entre utilisateurs de l'église (`messages_internes`).
class MessageInterne {
  final String id;
  final String expediteurId;
  final String? destinataireId;
  final String sujet;
  final String corps;
  final bool lu;
  final DateTime? createdAt;

  const MessageInterne({
    required this.id,
    required this.expediteurId,
    this.destinataireId,
    required this.sujet,
    required this.corps,
    required this.lu,
    this.createdAt,
  });

  factory MessageInterne.fromJson(Map<String, dynamic> json) =>
      MessageInterne(
        id: json['id'] as String,
        expediteurId: json['expediteur_id'] as String,
        destinataireId: json['destinataire_id'] as String?,
        sujet: json['sujet'] as String,
        corps: json['corps'] as String,
        lu: json['lu'] as bool? ?? false,
        createdAt: parseDate(json['created_at'] as String?),
      );
}
