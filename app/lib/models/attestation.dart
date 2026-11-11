import '../utils/format.dart';

/// Attestation annuelle de dons (US3) : un PDF par donateur identifié,
/// dons confirmés d'une année civile, total en FCFA. Une attestation
/// émise est figée ; une correction en crée une nouvelle et annule
/// l'ancienne (remplace_id). En Côte d'Ivoire, sans valeur fiscale :
/// reçu justificatif seulement.
class Attestation {
  final String id;
  final String numero;
  final int annee;
  final String? memberId;
  final String? membreNom;
  final String? membreMatricule;
  final int totalFcfa;
  final int nbDons;
  final String statut; // emise | annulee
  final String? remplaceId;
  final DateTime? dateEmission;

  const Attestation({
    required this.id,
    required this.numero,
    required this.annee,
    this.memberId,
    this.membreNom,
    this.membreMatricule,
    required this.totalFcfa,
    required this.nbDons,
    required this.statut,
    this.remplaceId,
    this.dateEmission,
  });

  factory Attestation.fromJson(Map<String, dynamic> json) => Attestation(
        id: json['id'] as String,
        numero: json['numero'] as String,
        annee: (json['annee'] as num).toInt(),
        memberId: json['member_id'] as String?,
        membreNom: json['membre_nom'] as String?,
        membreMatricule: json['membre_matricule'] as String?,
        totalFcfa: (json['total_fcfa'] as num).toInt(),
        nbDons: (json['nb_dons'] as num).toInt(),
        statut: json['statut'] as String? ?? 'emise',
        remplaceId: json['remplace_id'] as String?,
        dateEmission: parseDate(json['date_emission'] as String?),
      );

  bool get estEmise => statut == 'emise';
}
