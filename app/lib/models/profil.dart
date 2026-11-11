import 'church.dart';

/// Horaire de culte affiché dans la présentation de l'église
/// (`horaires_cultes` : `[{ jour, heure, titre }]`).
class HoraireCulte {
  final String jour;
  final String heure;
  final String titre;

  const HoraireCulte({
    required this.jour,
    required this.heure,
    required this.titre,
  });

  factory HoraireCulte.fromJson(Map<String, dynamic> json) => HoraireCulte(
        jour: json['jour'] as String,
        heure: json['heure'] as String,
        titre: json['titre'] as String,
      );

  Map<String, dynamic> toJson() => {
        'jour': jour,
        'heure': heure,
        'titre': titre,
      };
}

/// Présentation publique d'une église (`GET /eglises/:code/presentation` :
/// `{ eglise, pasteur_principal, antennes }`).
class ProfilEglise {
  final Church eglise;
  final String? pasteurPrincipal;
  final List<Church> antennes;

  const ProfilEglise({
    required this.eglise,
    this.pasteurPrincipal,
    required this.antennes,
  });

  factory ProfilEglise.fromJson(Map<String, dynamic> json) => ProfilEglise(
        eglise: Church.fromJson(json['eglise'] as Map<String, dynamic>),
        pasteurPrincipal: json['pasteur_principal'] as String?,
        antennes: (json['antennes'] as List<dynamic>? ?? [])
            .map((e) => Church.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
