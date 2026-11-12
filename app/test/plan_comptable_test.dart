import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/finances.dart';
import 'package:esystem_church/utils/plan_comptable_excel.dart';

/// Tranche dépenses prévisibles : plan comptable des dépenses.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('CategorieDepense', () {
    test('parse et libelle code et nom', () {
      final categorie = CategorieDepense.fromJson(const {
        'id': 'cat-02',
        'code': '02',
        'nom': 'Infrastructures',
        'description': 'Loyer, eau, électricité, entretien',
      });
      expect(categorie.code, '02');
      expect(categorie.libelle, '02 · Infrastructures');
    });
  });

  group('PosteBudgetaire', () {
    test('parse la catégorie comptable et le marqueur récurrente', () {
      final poste = PosteBudgetaire.fromJson(const {
        'id': 'poste-1',
        'nom': 'Électricité',
        'categorie': 'depense',
        'description': null,
        'categorie_id': 'cat-02',
        'est_recurrente': true,
        'created_at': null,
      });
      expect(poste.categorieId, 'cat-02');
      expect(poste.estRecurrente, isTrue);
    });

    test('poste sans catégorie : marqueur faux par défaut', () {
      final poste = PosteBudgetaire.fromJson(const {
        'id': 'poste-2',
        'nom': 'Poste manuel EXEMPLE',
        'categorie': 'depense',
        'description': null,
        'categorie_id': null,
        'est_recurrente': null,
        'created_at': null,
      });
      expect(poste.categorieId, isNull);
      expect(poste.estRecurrente, isFalse);
    });
  });

  group('Depense', () {
    test('parse les champs du plan comptable', () {
      final depense = Depense.fromJson(const {
        'id': 'dep-1',
        'poste_id': 'poste-1',
        'montant_fcfa': 15000,
        'motif': 'Facture électricité EXEMPLE',
        'justificatif_ref': 'FAC-1',
        'statut': 'soumise',
        'date_depense': '2026-11-12',
        'reference': 'DEP-2026-0001',
        'departement_id': 'dep-1',
        'mode_paiement': 'virement',
        'fournisseur_beneficiaire': 'CIE EXEMPLE',
        'responsable_depense': 'Trésorier EXEMPLE',
        'responsable_autorisation': 'Pasteur EXEMPLE',
        'devise': 'FCFA',
        'created_at': null,
      });
      expect(depense.reference, 'DEP-2026-0001');
      expect(depense.modePaiementLabel, 'Virement');
      expect(depense.devise, 'FCFA');
      expect(depense.statutLabel, 'Soumise');
    });

    test('libellés des modes de paiement', () {
      expect(Depense.labelForModePaiement('especes'), 'Espèces');
      expect(Depense.labelForModePaiement('wave'), 'Wave');
      expect(Depense.labelForModePaiement('orange_money'), 'Orange Money');
      expect(Depense.labelForModePaiement('mtn_money'), 'MTN Mobile Money');
      expect(Depense.labelForModePaiement('cheque'), 'Chèque');
      expect(Depense.labelForModePaiement(null), 'Non précisé');
    });
  });

  group('BudgetMensuel', () {
    test('parse année, mois et montant prévu', () {
      final budget = BudgetMensuel.fromJson(const {
        'id': 'bm-1',
        'poste_id': 'poste-1',
        'annee': 2026,
        'mois': 11,
        'montant_prevu': 12000,
        'created_at': null,
      });
      expect(budget.annee, 2026);
      expect(budget.mois, 11);
      expect(budget.montantPrevu, 12000);
    });
  });

  group('SuiviMensuel', () {
    test('dépassement quand le réel dépasse le prévu défini', () {
      final suivi = SuiviMensuel.fromJson(const {
        'annee': 2026,
        'mois': 11,
        'par_categories': [
          {
            'poste_id': null,
            'poste': null,
            'categorie_code': '02',
            'categorie_nom': 'Infrastructures',
            'recurrente': null,
            'prevu_fcfa': 12000,
            'reel_fcfa': 20000,
            'budget_defini': true,
          },
        ],
        'par_postes': [
          {
            'poste_id': 'poste-1',
            'poste': 'Électricité',
            'categorie_code': '02',
            'categorie_nom': 'Infrastructures',
            'recurrente': true,
            'prevu_fcfa': 12000,
            'reel_fcfa': 20000,
            'budget_defini': true,
          },
          {
            'poste_id': 'poste-2',
            'poste': 'Eau',
            'categorie_code': '02',
            'categorie_nom': 'Infrastructures',
            'recurrente': true,
            'prevu_fcfa': 0,
            'reel_fcfa': 5000,
            'budget_defini': false,
          },
        ],
        'total_prevu_fcfa': 12000,
        'total_reel_fcfa': 25000,
      });
      expect(suivi.parCategories.first.depassement, isTrue);
      expect(suivi.parPostes.first.depassement, isTrue);
      expect(suivi.parPostes.first.libelle, 'Électricité');
      // Sans budget mensuel défini, pas de dépassement signalé.
      expect(suivi.parPostes.last.depassement, isFalse);
      expect(suivi.totalReelFcfa, 25000);
    });
  });

  group('Classeur Excel du rapport', () {
    test('trois feuilles, mêmes chiffres que le rapport', () {
      final rapport = RapportPlanComptable.fromJson(const {
        'annee': 2026,
        'mois': 11,
        'par_categories': [
          {
            'poste_id': null,
            'poste': null,
            'categorie_code': '02',
            'categorie_nom': 'Infrastructures',
            'recurrente': null,
            'prevu_fcfa': 12000,
            'reel_fcfa': 20000,
            'budget_defini': true,
          },
        ],
        'par_postes': [
          {
            'poste_id': 'poste-1',
            'poste': 'Électricité',
            'categorie_code': '02',
            'categorie_nom': 'Infrastructures',
            'recurrente': true,
            'prevu_fcfa': 12000,
            'reel_fcfa': 20000,
            'budget_defini': true,
          },
        ],
        'depenses': [
          {
            'reference': 'DEP-2026-0001',
            'date_depense': '2026-11-12',
            'motif': 'Facture électricité EXEMPLE',
            'montant_fcfa': 15000,
            'statut': 'soumise',
            'mode_paiement': 'virement',
            'fournisseur_beneficiaire': 'CIE EXEMPLE',
            'devise': 'FCFA',
            'poste': 'Électricité',
            'categorie_nom': 'Infrastructures',
            'departement_nom': null,
          },
        ],
        'total_prevu_fcfa': 12000,
        'total_reel_fcfa': 20000,
      });
      final bytes = construireClasseurPlanComptable(rapport);
      expect(bytes.isNotEmpty, isTrue);
      final relu = Excel.decodeBytes(bytes);
      expect(relu.sheets.keys.toList(),
          ['Par catégorie', 'Par poste', 'Dépenses']);
      final categories = relu['Par catégorie'];
      expect(
          categories.rows[0]
              .map((c) => c?.value.toString())
              .toList(),
          ['Catégorie', 'Prévu (FCFA)', 'Réel (FCFA)']);
      expect(categories.rows[1][0]?.value.toString(),
          '02 · Infrastructures');
      expect((categories.rows[1][2]?.value as IntCellValue).value, 20000);
      expect(categories.rows[2][0]?.value.toString(), 'Total');
      final depenses = relu['Dépenses'];
      expect(depenses.rows[1][0]?.value.toString(), 'DEP-2026-0001');
      expect(depenses.rows[1][1]?.value.toString(), '12/11/2026');
      expect((depenses.rows[1][8]?.value as IntCellValue).value, 15000);
    });

    test('application vierge : totaux à zéro, feuilles présentes', () {
      final rapport = RapportPlanComptable.fromJson(const {
        'annee': 2026,
        'mois': 11,
        'par_categories': [],
        'par_postes': [],
        'depenses': [],
        'total_prevu_fcfa': 0,
        'total_reel_fcfa': 0,
      });
      final bytes = construireClasseurPlanComptable(rapport);
      final relu = Excel.decodeBytes(bytes);
      expect(relu.sheets.keys.toList(),
          ['Par catégorie', 'Par poste', 'Dépenses']);
      expect(relu['Par catégorie'].rows.length, 2);
    });
  });
}
