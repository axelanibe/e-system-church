import 'rapport.dart';

/// Statistiques globales d'une église (`GET /stats/globales` :
/// `{ eglise: {…vue v_stats_eglise…}, reseau: […] }`).
class StatsGlobales {
  final int membresActifs;
  final int nouveauxConvertis;
  final int baptemes;
  final int cultesMois;
  final int presencesMois;
  final int recettesMoisFcfa;
  final int depensesMoisFcfa;
  final List<RapportSousEglise> reseau;

  const StatsGlobales({
    required this.membresActifs,
    required this.nouveauxConvertis,
    required this.baptemes,
    required this.cultesMois,
    required this.presencesMois,
    required this.recettesMoisFcfa,
    required this.depensesMoisFcfa,
    required this.reseau,
  });

  factory StatsGlobales.fromJson(Map<String, dynamic> json) {
    final eglise = json['eglise'] as Map<String, dynamic>? ?? json;
    return StatsGlobales(
      membresActifs: (eglise['membres_actifs'] as num?)?.toInt() ?? 0,
      nouveauxConvertis:
          (eglise['nouveaux_convertis'] as num?)?.toInt() ?? 0,
      baptemes: (eglise['baptemes'] as num?)?.toInt() ?? 0,
      cultesMois: (eglise['cultes_mois'] as num?)?.toInt() ?? 0,
      presencesMois: (eglise['presences_mois'] as num?)?.toInt() ?? 0,
      recettesMoisFcfa:
          (eglise['recettes_mois_fcfa'] as num?)?.toInt() ?? 0,
      depensesMoisFcfa:
          (eglise['depenses_mois_fcfa'] as num?)?.toInt() ?? 0,
      reseau: (json['reseau'] as List<dynamic>? ?? [])
          .map((e) => RapportSousEglise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
