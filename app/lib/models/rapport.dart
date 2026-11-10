import 'church.dart';

/// Chiffres d'une église : membres actifs + contributions confirmées.
class RapportChiffres {
  final int membresActifs;
  final int nombreContributions;
  final int totalFcfa;

  const RapportChiffres({
    required this.membresActifs,
    required this.nombreContributions,
    required this.totalFcfa,
  });

  factory RapportChiffres.fromJson(Map<String, dynamic> json) =>
      RapportChiffres(
        membresActifs: (json['membres_actifs'] as num?)?.toInt() ?? 0,
        nombreContributions:
            (json['nombre_contributions'] as num?)?.toInt() ?? 0,
        totalFcfa: (json['total_fcfa'] as num?)?.toInt() ?? 0,
      );
}

/// Agrégats d'une sous-église (vue `v_rapports_consolides`).
class RapportSousEglise {
  final String egliseId;
  final String egliseNom;
  final int membresActifs;
  final int nombreContributions;
  final int totalFcfa;

  const RapportSousEglise({
    required this.egliseId,
    required this.egliseNom,
    required this.membresActifs,
    required this.nombreContributions,
    required this.totalFcfa,
  });

  factory RapportSousEglise.fromJson(Map<String, dynamic> json) =>
      RapportSousEglise(
        egliseId: json['eglise_id'] as String,
        egliseNom: json['eglise_nom'] as String,
        membresActifs: (json['membres_actifs'] as num?)?.toInt() ?? 0,
        nombreContributions:
            (json['nombre_contributions'] as num?)?.toInt() ?? 0,
        totalFcfa: (json['total_fcfa'] as num?)?.toInt() ?? 0,
      );
}

/// Rapport consolidé (`GET /rapports/consolide`, mère seulement) :
/// `{ eglise, propre, sous_eglises, totaux_reseau }`.
class RapportConsolide {
  final Church eglise;
  final RapportChiffres propre;
  final List<RapportSousEglise> sousEglises;
  final RapportChiffres totauxReseau;

  const RapportConsolide({
    required this.eglise,
    required this.propre,
    required this.sousEglises,
    required this.totauxReseau,
  });

  factory RapportConsolide.fromJson(Map<String, dynamic> json) =>
      RapportConsolide(
        eglise: Church.fromJson(json['eglise'] as Map<String, dynamic>),
        propre: RapportChiffres.fromJson(
            json['propre'] as Map<String, dynamic>),
        sousEglises: (json['sous_eglises'] as List<dynamic>? ?? [])
            .map((e) => RapportSousEglise.fromJson(e as Map<String, dynamic>))
            .toList(),
        totauxReseau: RapportChiffres.fromJson(
            json['totaux_reseau'] as Map<String, dynamic>),
      );
}
