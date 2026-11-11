/// Chiffres globaux de la plateforme (`GET /plateforme/chiffres`,
/// super_admin seulement). Chiffres seulement : aucun détail nominatif,
/// aucune liste de membres, aucune gestion des membres au jour le jour.
class ChiffresPlateforme {
  final int eglisesMeres;
  final int branches;
  final int eglisesTotal;
  final int membresActifs;
  final int nombreContributions;
  final int totalContributionsFcfa;
  final int depensesFcfa;

  const ChiffresPlateforme({
    required this.eglisesMeres,
    required this.branches,
    required this.eglisesTotal,
    required this.membresActifs,
    required this.nombreContributions,
    required this.totalContributionsFcfa,
    required this.depensesFcfa,
  });

  factory ChiffresPlateforme.fromJson(Map<String, dynamic> json) =>
      ChiffresPlateforme(
        eglisesMeres: (json['eglises_meres'] as num?)?.toInt() ?? 0,
        branches: (json['branches'] as num?)?.toInt() ?? 0,
        eglisesTotal: (json['eglises_total'] as num?)?.toInt() ?? 0,
        membresActifs: (json['membres_actifs'] as num?)?.toInt() ?? 0,
        nombreContributions:
            (json['nombre_contributions'] as num?)?.toInt() ?? 0,
        totalContributionsFcfa:
            (json['total_contributions_fcfa'] as num?)?.toInt() ?? 0,
        depensesFcfa: (json['depenses_fcfa'] as num?)?.toInt() ?? 0,
      );
}
