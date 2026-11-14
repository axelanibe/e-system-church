import 'package:esystem_church/models/us_restantes.dart';
import 'package:esystem_church/services/t12_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tranche T12 — US4 à US17 restantes : modèles et chaînes FR/EN.
void main() {
  group('Promesse.fromJson', () {
    test('lit les totaux et la progression', () {
      final p = Promesse.fromJson({
        'id': 'p1',
        'member_id': 'm1',
        'membre_nom': 'Membre Test',
        'montant_total_fcfa': 9000,
        'date_debut': '2026-11-14',
        'nb_versements': 3,
        'statut': 'en_cours',
        'recu_fcfa': 3000,
        'reste_fcfa': 6000,
        'echeances': [
          {
            'id': 'e1',
            'date_echeance': '2026-11-14',
            'montant_fcfa': 3000,
            'statut': 'recu',
          },
          {
            'id': 'e2',
            'date_echeance': '2026-12-14',
            'montant_fcfa': 3000,
            'statut': 'en_attente',
          },
        ],
      });
      expect(p.estEnCours, isTrue);
      expect(p.progression, closeTo(1 / 3, 0.001));
      expect(p.echeances.length, 2);
      expect(p.echeances.first.estRecue, isTrue);
      expect(p.echeances.last.estEnAttente, isTrue);
    });
  });

  group('DonNature.fromJson', () {
    test('lit un don anonyme sans membre', () {
      final d = DonNature.fromJson({
        'id': 'd1',
        'member_id': null,
        'description': 'Sacs de riz',
        'quantite': 5,
        'unite': 'sacs',
        'type_don': 'nourriture',
        'heures': null,
        'date_don': '2026-11-14',
        'anonyme': true,
      });
      expect(d.anonyme, isTrue);
      expect(d.memberId, isNull);
      expect(d.typeDon, 'nourriture');
    });
  });

  group('Transparence.fromJson', () {
    test('lit les totaux sans ligne nominative', () {
      final t = Transparence.fromJson({
        'eglise': 'Mère Test',
        'periode': '2026-11',
        'totaux_par_type': [
          {'type': 'dime', 'total_fcfa': 50000, 'nombre': 10},
          {'type': 'depense', 'total_fcfa': 20000, 'nombre': 3},
        ],
        'depenses_par_poste': [
          {'poste': 'Culte', 'total_fcfa': 15000},
        ],
        'total_recettes_fcfa': 50000,
        'total_depenses_fcfa': 20000,
        'solde_fcfa': 30000,
      });
      expect(t.soldeFcfa, 30000);
      expect(t.totauxParType.length, 2);
      expect(t.depensesParPoste.first.poste, 'Culte');
    });
  });

  group('CartePortefeuille.fromJson', () {
    test('aucun compte Wallet branché', () {
      final c = CartePortefeuille.fromJson({
        'nom': 'Membre Test',
        'matricule': 'M-001',
        'fonction': null,
        'telephone': null,
        'eglise_nom': 'Mère Test',
        'eglise_code': 'ESC-T12',
        'qr_donnees': '{"type":"carte_membre"}',
        'compte_wallet': null,
        'note': 'Aucun compte.',
      });
      expect(c.compteWallet, isNull);
      expect(c.matricule, 'M-001');
    });
  });

  group('T12Strings', () {
    test('français par défaut, anglais au choix', () {
      const fr = T12Strings(false);
      const en = T12Strings(true);
      expect(fr.promesses, 'Promesses de don');
      expect(en.promesses, 'Giving pledges');
      expect(fr.donsNature, 'Dons en nature');
      expect(en.donsNature, 'In-kind gifts');
      expect(fr.aucunCompteWallet, contains('Aucun compte'));
      expect(en.aucunCompteWallet, contains('No Apple Wallet'));
      expect(fr.modeEconomique, 'Mode économique');
      expect(en.modeEconomique, 'Low-data mode');
    });
  });
}
