import 'finances.dart';

/// États financiers SYCEBNL, système normal (tranches P6 et dépôt SYCEBNL).
///
/// Générés depuis la vraie comptabilité, en un clic. Les charges
/// additionnent les dépenses confirmées du registre des contributions
/// (type `depense`) et les dépenses de Budget et caisse hors refusées
/// (table `depenses`), comme le tableau de bord et les totaux des
/// contributions. Une même dépense ne se saisit qu'une seule fois.
/// La trésorerie est l'excédent cumulé de cette comptabilité, la caisse
/// se tient à part : ses mouvements sont saisis à la main et les
/// contributions ne l'alimentent pas. Aucune donnée inventée : les lignes
/// sans source dans l'application restent à 0 FCFA.
/// Le bilan est équilibré par construction : les immobilisations nettes,
/// les créances et les dettes viennent des registres SYCEBNL (migration
/// 043), les fonds propres sont le solde (actif moins dettes).
class EtatsSycebnl {
  final int annee;

  /// Dîmes, offrandes et dons confirmés de l'exercice.
  final int produitsExploitation;

  /// Dépenses confirmées de l'exercice : registre des contributions
  /// (type `depense`) et dépenses de Budget et caisse hors refusées.
  final int chargesExploitation;

  /// 0 : aucun produit financier suivi dans l'application.
  final int produitsFinanciers;

  /// 0 : aucune charge financière suivie dans l'application.
  final int chargesFinancieres;

  /// Immobilisations nettes (valeur d'acquisition moins amortissement
  /// cumulé) du registre des immobilisations.
  final int actifImmobilise;

  /// Créances en cours du registre des créances.
  final int actifCirculant;

  /// Trésorerie à la clôture : ouverture + variation de l'exercice.
  final int tresorerieActif;

  /// Solde du bilan : actif immobilisé + actif circulant + trésorerie
  /// moins dettes.
  final int fondsPropres;

  /// Dettes en cours du registre des dettes.
  final int dettes;

  /// 0 : aucune trésorerie passive suivie dans l'application.
  final int tresoreriePassif;

  /// Nombre de notes rédigées dans le registre des notes annexes.
  final int notesRedigees;

  /// 0 FCFA : aucun montant rattaché aux notes.
  final int montantsRattaches;

  /// Flux d'investissement de l'exercice : moins les acquisitions
  /// d'immobilisations de l'exercice.
  final int fluxInvestissement;

  /// Flux de financement de l'exercice : dettes contractées dans
  /// l'exercice.
  final int fluxFinancement;

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
    this.fluxInvestissement = 0,
    this.fluxFinancement = 0,
  });

  int get totalProduits => produitsExploitation + produitsFinanciers;

  int get totalCharges => chargesExploitation + chargesFinancieres;

  int get resultatExercice => totalProduits - totalCharges;

  /// Flux des activités opérationnelles : le solde. Dans cette
  /// comptabilité à partie simple, les achats d'immobilisations et les
  /// emprunts sont déjà dans le résultat ; les flux d'investissement
  /// et de financement en sont isolés pour les montrer, donc le flux
  /// opérationnel est le résultat moins ces deux flux, et la variation
  /// de trésorerie reste égale au résultat.
  int get fluxOperationnelles =>
      resultatExercice - fluxInvestissement - fluxFinancement;

  int get variationTresorerie =>
      fluxOperationnelles + fluxInvestissement + fluxFinancement;

  int get tresorerieCloture => tresorerieActif;

  int get tresorerieOuverture => tresorerieCloture - variationTresorerie;

  int get totalActif => actifImmobilise + actifCirculant + tresorerieActif;

  int get totalPassif => fondsPropres + dettes + tresoreriePassif;

  /// Construit les quatre états depuis les sommes de
  /// GET /exports/sycebnl/donnees : produits et charges de l'exercice,
  /// trésorerie d'ouverture (exercices antérieurs), immobilisations
  /// nettes, créances et dettes en cours, flux de l'exercice, nombre de
  /// notes annexes rédigées. Mêmes chiffres que l'export PDF, qui lit
  /// les mêmes sommes côté serveur.
  factory EtatsSycebnl.depuisDonnees({
    required int annee,
    required int produits,
    required int charges,
    required int ouverture,
    int actifImmobilise = 0,
    int actifCirculant = 0,
    int dettes = 0,
    int fluxInvestissement = 0,
    int fluxFinancement = 0,
    int notesRedigees = 0,
  }) {
    final cloture = ouverture + (produits - charges);
    return EtatsSycebnl(
      annee: annee,
      produitsExploitation: produits,
      chargesExploitation: charges,
      produitsFinanciers: 0,
      chargesFinancieres: 0,
      actifImmobilise: actifImmobilise,
      actifCirculant: actifCirculant,
      tresorerieActif: cloture,
      fondsPropres: actifImmobilise + actifCirculant + cloture - dettes,
      dettes: dettes,
      tresoreriePassif: 0,
      notesRedigees: notesRedigees,
      montantsRattaches: 0,
      fluxInvestissement: fluxInvestissement,
      fluxFinancement: fluxFinancement,
    );
  }

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
