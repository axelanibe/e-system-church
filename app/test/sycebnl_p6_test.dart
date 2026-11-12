import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/finances.dart';
import 'package:esystem_church/models/sycebnl.dart';
import 'package:esystem_church/utils/sycebnl_excel.dart';

/// Tranche P6 : export SYCEBNL.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('EtatsSycebnl', () {
    RapportFinancier rapport(List<Map<String, dynamic>> parMois) =>
        RapportFinancier(parMois: parMois, parPoste: [], parBranche: []);

    const vide = RapportFinancier(parMois: [], parPoste: [], parBranche: []);

    test('application vierge : tous les états à 0, bilan équilibré', () {
      final etats = EtatsSycebnl.depuisRapports(
        annee: 2026,
        exercice: vide,
        anterieur: vide,
      );
      expect(etats.totalProduits, 0);
      expect(etats.totalCharges, 0);
      expect(etats.resultatExercice, 0);
      expect(etats.variationTresorerie, 0);
      expect(etats.tresorerieOuverture, 0);
      expect(etats.tresorerieCloture, 0);
      expect(etats.totalActif, 0);
      expect(etats.totalPassif, 0);
      expect(etats.totalActif, etats.totalPassif);
      expect(etats.notesRedigees, 0);
      expect(etats.montantsRattaches, 0);
    });

    test('exercice EXEMPLE : 12 000 000 de produits, 3 000 000 de charges',
        () {
      final exercice = rapport([
        {'mois': '2026-01', 'type': 'dime', 'total_fcfa': 8000000},
        {'mois': '2026-02', 'type': 'offrande', 'total_fcfa': 3000000},
        {'mois': '2026-03', 'type': 'don', 'total_fcfa': 1000000},
        {'mois': '2026-04', 'type': 'depense', 'total_fcfa': 3000000},
      ]);
      final etats = EtatsSycebnl.depuisRapports(
        annee: 2026,
        exercice: exercice,
        anterieur: vide,
      );
      expect(etats.produitsExploitation, 12000000);
      expect(etats.chargesExploitation, 3000000);
      expect(etats.totalProduits, 12000000);
      expect(etats.totalCharges, 3000000);
      expect(etats.resultatExercice, 9000000);
      expect(etats.fluxOperationnelles, 9000000);
      expect(etats.variationTresorerie, 9000000);
      expect(etats.tresorerieOuverture, 0);
      expect(etats.tresorerieCloture, 9000000);
      expect(etats.totalActif, 9000000);
      expect(etats.totalPassif, 9000000);
      expect(etats.totalActif, etats.totalPassif);
    });

    test('exercices antérieurs : ouverture reprise, bilan équilibré', () {
      final anterieur = rapport([
        {'mois': '2025-06', 'type': 'don', 'total_fcfa': 5000000},
        {'mois': '2025-09', 'type': 'depense', 'total_fcfa': 2000000},
      ]);
      final exercice = rapport([
        {'mois': '2026-01', 'type': 'dime', 'total_fcfa': 4000000},
        {'mois': '2026-02', 'type': 'depense', 'total_fcfa': 1000000},
      ]);
      final etats = EtatsSycebnl.depuisRapports(
        annee: 2026,
        exercice: exercice,
        anterieur: anterieur,
      );
      expect(etats.resultatExercice, 3000000);
      expect(etats.tresorerieOuverture, 3000000);
      expect(etats.tresorerieCloture, 6000000);
      expect(etats.totalActif, 6000000);
      expect(etats.totalPassif, 6000000);
      expect(etats.totalActif, etats.totalPassif);
    });

    test('forme démo (entrees, depenses) : mêmes totaux', () {
      final exercice = rapport([
        {'mois': '2026-01', 'entrees': 2000000, 'depenses': 500000},
        {'mois': '2026-02', 'entrees': 1000000, 'depenses': 0},
      ]);
      final etats = EtatsSycebnl.depuisRapports(
        annee: 2026,
        exercice: exercice,
        anterieur: vide,
      );
      expect(etats.produitsExploitation, 3000000);
      expect(etats.chargesExploitation, 500000);
      expect(etats.resultatExercice, 2500000);
      expect(etats.totalActif, etats.totalPassif);
    });

    test(
        'depuisDonnees : charges avec Budget et caisse, bilan équilibré',
        () {
      // EXEMPLE : produits 12 000 000, charges 3 500 000 (3 000 000 du
      // registre et 500 000 de Budget et caisse), ouverture 3 000 000.
      final etats = EtatsSycebnl.depuisDonnees(
        annee: 2026,
        produits: 12000000,
        charges: 3500000,
        ouverture: 3000000,
      );
      expect(etats.produitsExploitation, 12000000);
      expect(etats.chargesExploitation, 3500000);
      expect(etats.resultatExercice, 8500000);
      expect(etats.tresorerieOuverture, 3000000);
      expect(etats.tresorerieCloture, 11500000);
      expect(etats.totalActif, 11500000);
      expect(etats.totalPassif, 11500000);
      expect(etats.totalActif, etats.totalPassif);
    });
  });

  group('Classeur Excel SYCEBNL', () {
    int? valeur(Excel classeur, String feuille, String label) {
      final lignes = classeur.tables[feuille]?.rows ?? [];
      for (final ligne in lignes) {
        if (ligne.length < 2) continue;
        final texte = (ligne[0]?.value as TextCellValue?)?.value.text;
        if (texte == label) {
          final v = ligne[1]?.value;
          if (v is IntCellValue) return v.value;
        }
      }
      return null;
    }

    test('un classeur, une feuille par état, mêmes chiffres que l\'écran',
        () {
      final etats = EtatsSycebnl.depuisDonnees(
        annee: 2026,
        produits: 12000000,
        charges: 3500000,
        ouverture: 3000000,
      );
      final classeur = Excel.decodeBytes(construireClasseurSycebnl(etats));
      expect(
        classeur.tables.keys.toList(),
        [
          'Bilan',
          'Compte de résultat',
          'Flux de trésorerie',
          'Notes annexes',
        ],
      );
      expect(valeur(classeur, 'Bilan', 'Total de l\'actif'), 11500000);
      expect(valeur(classeur, 'Bilan', 'Total du passif'), 11500000);
      expect(
        valeur(classeur, 'Compte de résultat', 'Charges d\'exploitation'),
        3500000,
      );
      expect(
        valeur(
          classeur,
          'Compte de résultat',
          'Résultat de l\'exercice',
        ),
        8500000,
      );
      expect(
        valeur(classeur, 'Flux de trésorerie', 'Trésorerie à l\'ouverture'),
        3000000,
      );
      expect(
        valeur(classeur, 'Flux de trésorerie', 'Trésorerie à la clôture'),
        11500000,
      );
      expect(valeur(classeur, 'Notes annexes', 'Notes rédigées'), 0);
    });

    test('application vierge : classeur à 0', () {
      final etats = EtatsSycebnl.depuisDonnees(
        annee: 2026,
        produits: 0,
        charges: 0,
        ouverture: 0,
      );
      final classeur = Excel.decodeBytes(construireClasseurSycebnl(etats));
      expect(classeur.tables.keys.length, 4);
      expect(valeur(classeur, 'Bilan', 'Total de l\'actif'), 0);
      expect(
        valeur(classeur, 'Compte de résultat', 'Résultat de l\'exercice'),
        0,
      );
    });
  });
}
