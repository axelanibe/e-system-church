import 'church.dart';
import 'contribution.dart';

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

/// Période du rapport détaillé (`GET /rapports/consolide/detail`).
class RapportDetailPeriode {
  final String type; // mois | trimestre | annee
  final String debut; // AAAA-MM-JJ
  final String fin; // AAAA-MM-JJ, exclus
  final String label; // ex. « Novembre 2026 », « 4e trimestre 2026 »

  const RapportDetailPeriode({
    required this.type,
    required this.debut,
    required this.fin,
    required this.label,
  });

  factory RapportDetailPeriode.fromJson(Map<String, dynamic> json) =>
      RapportDetailPeriode(
        type: json['type'] as String,
        debut: json['debut'] as String,
        fin: json['fin'] as String,
        label: json['label'] as String,
      );
}

/// Détail d'une branche : totaux par type sur la période, solde, et chaque
/// transaction confirmée de la période, la plus récente d'abord.
class RapportDetailBranche {
  final String egliseId;
  final String egliseCode;
  final String egliseNom;
  final String? egliseVille;
  final int membresActifs;
  final Map<String, ContributionTotals> totaux;
  final int entreesFcfa;
  final int depensesFcfa;
  final int soldeFcfa;
  final List<Contribution> transactions;

  const RapportDetailBranche({
    required this.egliseId,
    required this.egliseCode,
    required this.egliseNom,
    this.egliseVille,
    required this.membresActifs,
    required this.totaux,
    required this.entreesFcfa,
    required this.depensesFcfa,
    required this.soldeFcfa,
    required this.transactions,
  });

  factory RapportDetailBranche.fromJson(Map<String, dynamic> json) {
    final totaux = <String, ContributionTotals>{};
    (json['totaux'] as Map<String, dynamic>).forEach((key, value) {
      totaux[key] =
          ContributionTotals.fromJson(value as Map<String, dynamic>);
    });
    return RapportDetailBranche(
      egliseId: json['eglise_id'] as String,
      egliseCode: json['eglise_code'] as String,
      egliseNom: json['eglise_nom'] as String,
      egliseVille: json['eglise_ville'] as String?,
      membresActifs: (json['membres_actifs'] as num?)?.toInt() ?? 0,
      totaux: totaux,
      entreesFcfa: (json['entrees_fcfa'] as num?)?.toInt() ?? 0,
      depensesFcfa: (json['depenses_fcfa'] as num?)?.toInt() ?? 0,
      soldeFcfa: (json['solde_fcfa'] as num?)?.toInt() ?? 0,
      transactions: (json['transactions'] as List<dynamic>? ?? [])
          .map((e) => Contribution.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Rapport détaillé de la mère : total consolidé + détail par branche.
/// Le rapport agrégé [RapportConsolide] reste pour le tableau de bord ;
/// celui-ci s'ajoute à côté, il ne le remplace pas.
class RapportDetailConsolide {
  final Church eglise;
  final RapportDetailPeriode periode;
  final List<RapportDetailBranche> branches;
  final Map<String, ContributionTotals> totaux;
  final int entreesFcfa;
  final int depensesFcfa;
  final int soldeFcfa;
  final int membresActifs;

  const RapportDetailConsolide({
    required this.eglise,
    required this.periode,
    required this.branches,
    required this.totaux,
    required this.entreesFcfa,
    required this.depensesFcfa,
    required this.soldeFcfa,
    required this.membresActifs,
  });

  factory RapportDetailConsolide.fromJson(Map<String, dynamic> json) {
    final reseau = json['totaux_reseau'] as Map<String, dynamic>;
    final totaux = <String, ContributionTotals>{};
    (reseau['totaux'] as Map<String, dynamic>).forEach((key, value) {
      totaux[key] =
          ContributionTotals.fromJson(value as Map<String, dynamic>);
    });
    return RapportDetailConsolide(
      eglise: Church.fromJson(json['eglise'] as Map<String, dynamic>),
      periode: RapportDetailPeriode.fromJson(
          json['periode'] as Map<String, dynamic>),
      branches: (json['branches'] as List<dynamic>? ?? [])
          .map((e) => RapportDetailBranche.fromJson(e as Map<String, dynamic>))
          .toList(),
      totaux: totaux,
      entreesFcfa: (reseau['entrees_fcfa'] as num?)?.toInt() ?? 0,
      depensesFcfa: (reseau['depenses_fcfa'] as num?)?.toInt() ?? 0,
      soldeFcfa: (reseau['solde_fcfa'] as num?)?.toInt() ?? 0,
      membresActifs: (reseau['membres_actifs'] as num?)?.toInt() ?? 0,
    );
  }
}
