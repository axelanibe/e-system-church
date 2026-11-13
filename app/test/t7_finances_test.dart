import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/contribution.dart';
import 'package:esystem_church/models/finances.dart';
import 'package:esystem_church/screens/cotisations_admin_screen.dart';
import 'package:esystem_church/screens/rapprochement_screen.dart';
import 'package:esystem_church/utils/periodes.dart';

/// Tranche T7 — Finances complètes : cotisations, comptes bancaires,
/// rapprochement, clôture, reçus, budgets par département.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('CotisationConfig', () {
    test('parse montant, périodicité et actif', () {
      final c = CotisationConfig.fromJson(const {
        'montant_fcfa': 5000,
        'periodicite': 'mensuelle',
        'actif': true,
      });
      expect(c.montantFcfa, 5000);
      expect(c.periodicite, 'mensuelle');
      expect(c.periodiciteLabel, 'Mensuelle');
      expect(c.actif, isTrue);
    });

    test('annuelle par défaut mensuelle quand absente', () {
      final c = CotisationConfig.fromJson(const {'montant_fcfa': 60000});
      expect(c.periodicite, 'mensuelle');
      expect(c.actif, isTrue);
    });
  });

  group('LigneCotisation', () {
    test('payée quand le payé couvre le dû', () {
      final l = LigneCotisation.fromJson(const {
        'member_id': 'EXEMPLE-M1',
        'membre_nom': 'Membre EXEMPLE',
        'membre_matricule': 'ESC-EXEMPLE',
        'montant_du_fcfa': 5000,
        'montant_paye_fcfa': 5000,
        'reste_fcfa': 0,
        'surplus_fcfa': 0,
        'statut': 'payee',
      });
      expect(l.statutLabel, 'Payée');
      expect(l.resteFcfa, 0);
    });

    test('partielle avec reste', () {
      final l = LigneCotisation.fromJson(const {
        'member_id': 'EXEMPLE-M1',
        'membre_nom': 'Membre EXEMPLE',
        'montant_du_fcfa': 5000,
        'montant_paye_fcfa': 2000,
        'reste_fcfa': 3000,
        'surplus_fcfa': 0,
        'statut': 'partielle',
      });
      expect(l.statutLabel, 'Partielle');
      expect(l.resteFcfa, 3000);
    });

    test('impayée sans paiement', () {
      final l = LigneCotisation.fromJson(const {
        'member_id': 'EXEMPLE-M1',
        'membre_nom': 'Membre EXEMPLE',
        'montant_du_fcfa': 5000,
        'montant_paye_fcfa': 0,
        'reste_fcfa': 5000,
        'surplus_fcfa': 0,
        'statut': 'impayee',
      });
      expect(l.statutLabel, 'Impayée');
    });
  });

  group('SuiviCotisations', () {
    test('parse config, lignes et totaux', () {
      final s = SuiviCotisations.fromJson(const {
        'config': {
          'montant_fcfa': 5000,
          'periodicite': 'mensuelle',
          'actif': true,
        },
        'config_absente': false,
        'periode': '2026-11',
        'membres': [
          {
            'member_id': 'EXEMPLE-M1',
            'membre_nom': 'Membre EXEMPLE',
            'montant_du_fcfa': 5000,
            'montant_paye_fcfa': 5000,
            'reste_fcfa': 0,
            'surplus_fcfa': 0,
            'statut': 'payee',
          },
        ],
        'totaux': {
          'total_du_fcfa': 5000,
          'total_paye_fcfa': 5000,
          'total_reste_fcfa': 0,
          'membres_payes': 1,
          'membres_total': 1,
        },
      });
      expect(s.config?.montantFcfa, 5000);
      expect(s.periode, '2026-11');
      expect(s.membres.length, 1);
      expect(s.totaux.membresPayes, 1);
      expect(s.totaux.totalResteFcfa, 0);
    });

    test('config absente : lignes vides', () {
      final s = SuiviCotisations.fromJson(const {
        'config': null,
        'config_absente': true,
        'periode': '2026-11',
        'membres': [],
        'totaux': {
          'total_du_fcfa': 0,
          'total_paye_fcfa': 0,
          'total_reste_fcfa': 0,
          'membres_payes': 0,
          'membres_total': 0,
        },
      });
      expect(s.config, isNull);
      expect(s.configAbsente, isTrue);
      expect(s.membres, isEmpty);
    });
  });

  group('CompteBancaire', () {
    test('parse banque et mobile money', () {
      final banque = CompteBancaire.fromJson(const {
        'id': 'EXEMPLE-C1',
        'banque': 'Banque EXEMPLE',
        'titulaire': 'Église EXEMPLE',
        'numero_compte': 'CI00 0000 0000',
        'type': 'banque',
        'devise': 'FCFA',
        'actif': true,
      });
      expect(banque.typeLabel, 'Banque');
      final mobile = CompteBancaire.fromJson(const {
        'id': 'EXEMPLE-C2',
        'banque': 'Wave',
        'type': 'mobile_money',
        'devise': 'FCFA',
        'actif': true,
      });
      expect(mobile.typeLabel, 'Mobile Money');
      expect(mobile.titulaire, isNull);
    });
  });

  group('LigneRapprochement', () {
    test('alerte quand l’écart n’est pas nul', () {
      final l = LigneRapprochement.fromJson(const {
        'canal': 'wave',
        'entrees_confirmees_fcfa': 100000,
        'sorties_payees_fcfa': 0,
        'attendu_fcfa': 100000,
        'caisse_entrees_fcfa': 90000,
        'caisse_sorties_fcfa': 0,
        'caisse_net_fcfa': 90000,
        'ecart_fcfa': 10000,
        'alerte': true,
      });
      expect(l.canalLabel, 'Wave');
      expect(l.ecartFcfa, 10000);
      expect(l.alerte, isTrue);
    });

    test('sans alerte quand l’écart est nul', () {
      final l = LigneRapprochement.fromJson(const {
        'canal': 'especes',
        'entrees_confirmees_fcfa': 50000,
        'sorties_payees_fcfa': 0,
        'attendu_fcfa': 50000,
        'caisse_entrees_fcfa': 50000,
        'caisse_sorties_fcfa': 0,
        'caisse_net_fcfa': 50000,
        'ecart_fcfa': 0,
        'alerte': false,
      });
      expect(l.canalLabel, 'Espèces');
      expect(l.alerte, isFalse);
    });

    test('libellés de tous les canaux', () {
      expect(labelCanal('wave'), 'Wave');
      expect(labelCanal('orange_money'), 'Orange Money');
      expect(labelCanal('mtn_momo'), 'MTN MoMo');
      expect(labelCanal('especes'), 'Espèces');
      expect(labelCanal('virement'), 'Virement');
      expect(labelCanal('cheque'), 'Chèque');
      expect(labelCanal('non_ventile'), 'Non ventilé');
      expect(labelCanal(null), '—');
    });
  });

  group('ClotureCaisse', () {
    test('parse période, soldes et écart', () {
      final c = ClotureCaisse.fromJson(const {
        'id': 'EXEMPLE-K1',
        'periode': '2026-10',
        'solde_calcule_fcfa': 150000,
        'solde_compte_fcfa': 148000,
        'ecart_fcfa': -2000,
        'commentaire': 'Commentaire EXEMPLE',
      });
      expect(c.periode, '2026-10');
      expect(c.soldeCalculeFcfa, 150000);
      expect(c.ecartFcfa, -2000);
      expect(c.commentaire, 'Commentaire EXEMPLE');
    });
  });

  group('SuiviDepartements', () {
    test('dépassement quand le réel dépasse un budget défini', () {
      final s = SuiviDepartements.fromJson(const {
        'annee': 2026,
        'mois': 11,
        'par_departements': [
          {
            'departement_id': 'EXEMPLE-D1',
            'departement': 'Louange',
            'prevu_fcfa': 60000,
            'reel_fcfa': 65000,
            'ecart_fcfa': 5000,
            'depasse': true,
            'budget_defini': true,
          },
          {
            'departement_id': 'EXEMPLE-D2',
            'departement': 'Intercession',
            'prevu_fcfa': 0,
            'reel_fcfa': 10000,
            'ecart_fcfa': 10000,
            'depasse': false,
            'budget_defini': false,
          },
        ],
        'sans_departement': {
          'prevu_fcfa': 0,
          'reel_fcfa': 0,
          'ecart_fcfa': 0,
        },
        'total_prevu_fcfa': 60000,
        'total_reel_fcfa': 75000,
      });
      expect(s.parDepartements[0].depasse, isTrue);
      expect(s.parDepartements[1].depasse, isFalse);
      expect(s.parDepartements[1].budgetDefini, isFalse);
      expect(s.totalReelFcfa, 75000);
    });
  });

  group('BudgetDepartement', () {
    test('parse budget mensuel de département', () {
      final b = BudgetDepartement.fromJson(const {
        'id': 'EXEMPLE-B1',
        'departement_id': 'EXEMPLE-D1',
        'departement_nom': 'Louange',
        'annee': 2026,
        'mois': 11,
        'montant_prevu': 60000,
      });
      expect(b.departementNom, 'Louange');
      expect(b.montantPrevu, 60000);
    });
  });

  group('CaisseMouvement (T7 : source et canal)', () {
    test('parse écriture automatique avec canal', () {
      final m = CaisseMouvement.fromJson(const {
        'id': 'EXEMPLE-M1',
        'type': 'entree',
        'montant_fcfa': 10000,
        'motif': 'Contribution Dîme — reçu REC-2026-0001',
        'reference': 'REC-2026-0001',
        'source': 'contribution',
        'canal': 'wave',
        'created_at': '2026-11-13T10:00:00.000Z',
      });
      expect(m.sourceLabel, 'Automatique');
      expect(m.canalLabel, 'Wave');
    });

    test('parse écriture manuelle sans canal', () {
      final m = CaisseMouvement.fromJson(const {
        'id': 'EXEMPLE-M2',
        'type': 'sortie',
        'montant_fcfa': 5000,
        'motif': 'Motif EXEMPLE',
        'source': 'manuelle',
        'canal': null,
      });
      expect(m.sourceLabel, 'Manuelle');
      expect(m.canalLabel, '—');
    });
  });

  group('Contribution (T7 : reçu et cotisation)', () {
    test('parse numéro de reçu', () {
      final c = Contribution.fromJson(const {
        'id': 'EXEMPLE-C1',
        'type': 'dime',
        'amount_fcfa': 10000,
        'payment_method': 'wave',
        'status': 'confirme',
        'recu_numero': 'REC-2026-0001',
      });
      expect(c.recuNumero, 'REC-2026-0001');
    });

    test('libellés cotisation', () {
      expect(Contribution.labelForType('cotisation'), 'Cotisation');
      expect(Contribution.labelForTypePluriel('cotisation'),
          'Cotisations confirmées');
    });
  });

  group('Périodes', () {
    test('mois précédent et suivant, avec passage d’année', () {
      expect(moisPrecedent('2026-01'), '2025-12');
      expect(moisPrecedent('2026-11'), '2026-10');
      expect(moisSuivant('2026-12'), '2027-01');
      expect(moisSuivant('2026-11'), '2026-12');
    });

    test('dernier mois terminé', () {
      expect(dernierMoisTermine(DateTime(2026, 11, 13)), '2026-10');
      expect(dernierMoisTermine(DateTime(2027, 1, 5)), '2026-12');
    });

    test('libellé de période', () {
      expect(libellePeriodeMois('2026-11'), 'novembre 2026');
      expect(libellePeriodeMois('2026-01'), 'janvier 2026');
    });

    test('années précédente et suivante', () {
      expect(anneePrecedente('2026'), '2025');
      expect(anneeSuivante('2026'), '2027');
    });
  });

  group('Tuiles T7 (composants)', () {
    testWidgets('LigneCotisationTile affiche dû, payé, reste et statut',
        (tester) async {
      const ligne = LigneCotisation(
        memberId: 'EXEMPLE-M1',
        membreNom: 'Membre EXEMPLE',
        membreMatricule: 'ESC-EXEMPLE',
        montantDuFcfa: 5000,
        montantPayeFcfa: 2000,
        resteFcfa: 3000,
        surplusFcfa: 0,
        statut: 'partielle',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LigneCotisationTile(ligne: ligne, devise: 'FCFA'),
          ),
        ),
      );
      expect(find.text('Membre EXEMPLE'), findsOneWidget);
      expect(find.text('Partielle'), findsOneWidget);
      expect(find.textContaining('3 000'), findsWidgets);
    });

    testWidgets('RapprochementCanalTile affiche l’écart et son alerte',
        (tester) async {
      const ligne = LigneRapprochement(
        canal: 'wave',
        entreesConfirmeesFcfa: 100000,
        sortiesPayeesFcfa: 0,
        attenduFcfa: 100000,
        caisseEntreesFcfa: 90000,
        caisseSortiesFcfa: 0,
        caisseNetFcfa: 90000,
        ecartFcfa: 10000,
        alerte: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RapprochementCanalTile(ligne: ligne, devise: 'FCFA'),
          ),
        ),
      );
      expect(find.text('Wave'), findsOneWidget);
      expect(find.text('Écart'), findsOneWidget);
      expect(find.textContaining('10 000'), findsWidgets);
    });

    testWidgets(
        'RapprochementCanalTile sans alerte n’affiche pas la puce Écart',
        (tester) async {
      const ligne = LigneRapprochement(
        canal: 'especes',
        entreesConfirmeesFcfa: 50000,
        sortiesPayeesFcfa: 0,
        attenduFcfa: 50000,
        caisseEntreesFcfa: 50000,
        caisseSortiesFcfa: 0,
        caisseNetFcfa: 50000,
        ecartFcfa: 0,
        alerte: false,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RapprochementCanalTile(ligne: ligne, devise: 'FCFA'),
          ),
        ),
      );
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('Écart'), findsNothing);
    });
  });
}
