import 'package:excel/excel.dart';

import '../models/sycebnl.dart';

/// Classeur Excel des quatre états SYCEBNL : une feuille par état, mêmes
/// chiffres que l'écran et que l'export PDF (tranche P6, correctif).
/// Même librairie `excel` que l'import de membres, aucune autre ajoutée.
List<int> construireClasseurSycebnl(EtatsSycebnl etats) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Bilan');
  _feuille(
    excel['Bilan'],
    'Bilan SYCEBNL',
    etats.annee,
    [
      ('Actif immobilisé', etats.actifImmobilise),
      ('Actif circulant', etats.actifCirculant),
      ('Trésorerie actif', etats.tresorerieActif),
      ('Fonds propres', etats.fondsPropres),
      ('Dettes', etats.dettes),
      ('Trésorerie passif', etats.tresoreriePassif),
      ('Total de l\'actif', etats.totalActif),
      ('Total du passif', etats.totalPassif),
    ],
  );
  _feuille(
    excel['Compte de résultat'],
    'Compte de résultat SYCEBNL',
    etats.annee,
    [
      ('Produits d\'exploitation', etats.produitsExploitation),
      ('Charges d\'exploitation', etats.chargesExploitation),
      ('Produits financiers', etats.produitsFinanciers),
      ('Charges financières', etats.chargesFinancieres),
      ('Total des produits', etats.totalProduits),
      ('Total des charges', etats.totalCharges),
      ('Résultat de l\'exercice', etats.resultatExercice),
    ],
  );
  _feuille(
    excel['Flux de trésorerie'],
    'Tableau des flux de trésorerie SYCEBNL',
    etats.annee,
    [
      ('Flux des activités opérationnelles', etats.fluxOperationnelles),
      ('Flux des activités d\'investissement', etats.fluxInvestissement),
      ('Flux des activités de financement', etats.fluxFinancement),
      ('Trésorerie à l\'ouverture', etats.tresorerieOuverture),
      ('Trésorerie à la clôture', etats.tresorerieCloture),
      ('Variation de trésorerie', etats.variationTresorerie),
    ],
  );
  _feuille(
    excel['Notes annexes'],
    'Notes annexes SYCEBNL',
    etats.annee,
    [
      ('Notes rédigées', etats.notesRedigees),
      ('Montants rattachés', etats.montantsRattaches),
    ],
  );
  return excel.encode() ?? [];
}

void _feuille(
  Sheet feuille,
  String titre,
  int annee,
  List<(String, int)> lignes,
) {
  feuille.insertRowIterables(
    [TextCellValue(titre), TextCellValue('Exercice $annee')],
    0,
  );
  feuille.insertRowIterables(
    [TextCellValue('Poste'), TextCellValue('Montant (FCFA)')],
    1,
  );
  for (var i = 0; i < lignes.length; i++) {
    final (label, montant) = lignes[i];
    feuille.insertRowIterables(
      [TextCellValue(label), IntCellValue(montant)],
      i + 2,
    );
  }
}
