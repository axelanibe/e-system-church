/// Anniversaire proche d'un membre (`GET /membres/anniversaires`) : la
/// liste seulement, aucun message envoyé (tranche T4).
class Anniversaire {
  final String id;
  final String fullName;
  final String matricule;
  final String birthDate; // « AAAA-MM-JJ »
  final DateTime prochain;
  final int joursRestants;
  final int ageAtteint;

  const Anniversaire({
    required this.id,
    required this.fullName,
    required this.matricule,
    required this.birthDate,
    required this.prochain,
    required this.joursRestants,
    required this.ageAtteint,
  });

  factory Anniversaire.fromJson(Map<String, dynamic> json) => Anniversaire(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        matricule: json['matricule'] as String,
        birthDate: json['birth_date'] as String,
        prochain: DateTime.parse(json['prochain'] as String),
        joursRestants: (json['jours_restants'] as num).toInt(),
        ageAtteint: (json['age_atteint'] as num).toInt(),
      );
}
