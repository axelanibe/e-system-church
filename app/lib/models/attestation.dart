import '../utils/format.dart';

/// Attestation (US3 + tranche B) : un PDF par membre, contenu figé à
/// l'émission. Type `don` : attestation annuelle de dons, total en FCFA.
/// Types `mariage`, `naissance`, `bapteme` : attestation d'événement,
/// sans total ni nombre de dons (null). Une attestation émise est figée ;
/// une correction en crée une nouvelle et annule l'ancienne (remplace_id).
/// En Côte d'Ivoire, l'attestation de dons est sans valeur fiscale :
/// reçu justificatif seulement.
class Attestation {
  final String id;
  final String numero;
  final int annee;
  final String type; // don | mariage | naissance | bapteme
  final String? memberId;
  final String? membreNom;
  final String? membreMatricule;
  final int? totalFcfa; // dons seulement, null pour un événement
  final int? nbDons; // dons seulement, null pour un événement
  final String statut; // emise | annulee
  final String? remplaceId;
  final DateTime? dateEmission;

  const Attestation({
    required this.id,
    required this.numero,
    required this.annee,
    this.type = 'don',
    this.memberId,
    this.membreNom,
    this.membreMatricule,
    this.totalFcfa,
    this.nbDons,
    required this.statut,
    this.remplaceId,
    this.dateEmission,
  });

  factory Attestation.fromJson(Map<String, dynamic> json) => Attestation(
        id: json['id'] as String,
        numero: json['numero'] as String,
        annee: (json['annee'] as num).toInt(),
        type: json['type'] as String? ?? 'don',
        memberId: json['member_id'] as String?,
        membreNom: json['membre_nom'] as String?,
        membreMatricule: json['membre_matricule'] as String?,
        totalFcfa: (json['total_fcfa'] as num?)?.toInt(),
        nbDons: (json['nb_dons'] as num?)?.toInt(),
        statut: json['statut'] as String? ?? 'emise',
        remplaceId: json['remplace_id'] as String?,
        dateEmission: parseDate(json['date_emission'] as String?),
      );

  bool get estEmise => statut == 'emise';
  bool get estDon => type == 'don';

  /// Libellé du type, pour les listes et les filtres.
  static String libelleType(String type) => switch (type) {
        'mariage' => 'Mariage',
        'naissance' => 'Naissance',
        'bapteme' => 'Baptême',
        _ => 'Dons',
      };

  String get libelle => libelleType(type);
}
