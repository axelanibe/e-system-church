import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/finances.dart';
import 'package:esystem_church/models/sycebnl.dart';

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
  });
}
