import 'finances.dart';

/// États financiers SYCEBNL, système normal (tranche P6).
///
/// Générés depuis la vraie comptabilité, en un clic : les produits et les
/// charges viennent du rapport financier de l'exercice (contributions
/// confirmées), la trésorerie d'ouverture vient des exercices antérieurs
/// (même source, avant le 1er janvier de l'exercice). Aucune donnée
/// inventée : les lignes sans source dans l'application restent à 0 FCFA.
/// Les dépenses suivies dans l'onglet Dépenses (table `depenses`,
/// validation trésorier puis pasteur) ne sont pas reprises ici : les charges
/// sont celles du registre des contributions, comme dans l'onglet Rapport.
/// Le bilan est équilibré par construction : l'application ne suit ni
/// immobilisations ni dettes, l'excédent cumulé est donc tenu en trésorerie.
class EtatsSycebnl {
  final int annee;

  /// Dîmes, offrandes et dons confirmés de l'exercice.
  final int produitsExploitation;

  /// Dépenses confirmées de l'exercice (registre des contributions).
  final int chargesExploitation;

  /// 0 : aucun produit financier suivi dans l'application.
  final int produitsFinanciers;

  /// 0 : aucune charge financière suivie dans l'application.
  final int chargesFinancieres;

  /// 0 : aucun bien immobilisé suivi dans l'application.
  final int actifImmobilise;

  /// 0 : aucune créance suivie dans l'application.
  final int actifCirculant;

  /// Trésorerie à la clôture : ouverture + variation de l'exercice.
  final int tresorerieActif;

  /// Excédent cumulé, tenu en trésorerie (aucune immobilisation, aucune
  /// dette suivie).
  final int fondsPropres;

  /// 0 : aucune dette suivie dans l'application.
  final int dettes;

  /// 0 : aucune trésorerie passive suivie dans l'application.
  final int tresoreriePassif;

  /// 0 : aucune note rédigée dans l'application.
  final int notesRedigees;

  /// 0 FCFA : aucun montant rattaché aux notes.
  final int montantsRattaches;

  const EtatsSycebnl({
    required this.annee,
    required this.produitsExploitation,
    required this.chargesExploitation,
    required this.produitsFinanciers,
    required this.chargesFinancieres,
    required this.actifImmobilise,
    required this.actifCirculant,
    required this.tresorerieActif,
    required this.fondsPropres,
    required this.dettes,
    required this.tresoreriePassif,
    required this.notesRedigees,
    required this.montantsRattaches,
  });

  int get totalProduits => produitsExploitation + produitsFinanciers;

  int get totalCharges => chargesExploitation + chargesFinancieres;

  int get resultatExercice => totalProduits - totalCharges;

  int get fluxOperationnelles => resultatExercice;

  int get fluxInvestissement => 0;

  int get fluxFinancement => 0;

  int get variationTresorerie =>
      fluxOperationnelles + fluxInvestissement + fluxFinancement;

  int get tresorerieCloture => tresorerieActif;

  int get tresorerieOuverture => tresorerieCloture - variationTresorerie;

  int get totalActif => actifImmobilise + actifCirculant + tresorerieActif;

  int get totalPassif => fondsPropres + dettes + tresoreriePassif;

  /// Construit les quatre états depuis le rapport financier de l'exercice
  /// et celui des exercices antérieurs (avant le 1er janvier).
  factory EtatsSycebnl.depuisRapports({
    required int annee,
    required RapportFinancier exercice,
    required RapportFinancier anterieur,
  }) {
    final (produits, charges) = _sommes(exercice);
    final (produitsAnt, chargesAnt) = _sommes(anterieur);
    final ouverture = produitsAnt - chargesAnt;
    final cloture = ouverture + (produits - charges);
    return EtatsSycebnl(
      annee: annee,
      produitsExploitation: produits,
      chargesExploitation: charges,
      produitsFinanciers: 0,
      chargesFinancieres: 0,
      actifImmobilise: 0,
      actifCirculant: 0,
      tresorerieActif: cloture,
      fondsPropres: cloture,
      dettes: 0,
      tresoreriePassif: 0,
      notesRedigees: 0,
      montantsRattaches: 0,
    );
  }

  /// Somme les produits et les charges d'un rapport financier.
  /// Forme serveur : une ligne par mois et par type (`type`, `total_fcfa`).
  /// Forme démo : une ligne par mois (`entrees`, `depenses`).
  static (int, int) _sommes(RapportFinancier rapport) {
    var produits = 0;
    var charges = 0;
    for (final ligne in rapport.parMois) {
      final type = ligne['type'] as String?;
      final total = (ligne['total_fcfa'] as num?)?.toInt();
      if (type != null && total != null) {
        if (type == 'depense') {
          charges += total;
        } else {
          produits += total;
        }
      } else {
        produits += (ligne['entrees'] as num?)?.toInt() ?? 0;
        charges += (ligne['depenses'] as num?)?.toInt() ?? 0;
      }
    }
    return (produits, charges);
  }
}
