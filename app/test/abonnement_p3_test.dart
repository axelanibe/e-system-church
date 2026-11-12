import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/abonnement.dart';

/// Tranche P3 : Mon abonnement.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('Abonnement', () {
    test('parse la réponse mère sans ligne en base', () {
      final abo = Abonnement.fromJson(const {
        'est_annexe': false,
        'eglise_mere_nom': 'Église EXEMPLE',
        'abonnement': {
          'plan': 'annuel',
          'duree_annees': 1,
          'montant_fcfa': 200000,
          'statut': 'actif',
          'date_debut': null,
          'date_expiration': null,
          'essai_jours': 30,
          'lecture_seule': false,
        },
      });
      expect(abo.estAnnexe, isFalse);
      expect(abo.egliseMereNom, 'Église EXEMPLE');
      expect(abo.statut, 'actif');
      expect(abo.statutLibelle, 'Actif');
      expect(abo.plan, 'annuel');
      expect(abo.montantFcfa, 200000);
      expect(abo.dateExpiration, isNull);
      expect(abo.essaiJours, 30);
      expect(abo.lectureSeule, isFalse);
    });

    test('parse la réponse annexe', () {
      final abo = Abonnement.fromJson(const {
        'est_annexe': true,
        'eglise_mere_nom': 'Église mère EXEMPLE',
        'abonnement': null,
      });
      expect(abo.estAnnexe, isTrue);
      expect(abo.egliseMereNom, 'Église mère EXEMPLE');
      expect(abo.statut, 'actif');
      expect(abo.dateExpiration, isNull);
    });

    test('parse l’expiration et la lecture seule', () {
      final abo = Abonnement.fromJson(const {
        'est_annexe': false,
        'eglise_mere_nom': 'Église EXEMPLE',
        'abonnement': {
          'plan': 'annuel',
          'duree_annees': 3,
          'montant_fcfa': 540000,
          'statut': 'expire',
          'date_debut': '2025-01-01',
          'date_expiration': '2025-12-31',
          'essai_jours': 30,
          'lecture_seule': true,
        },
      });
      expect(abo.statutLibelle, 'Expiré');
      expect(abo.dateExpiration, DateTime(2025, 12, 31));
      expect(abo.lectureSeule, isTrue);
    });

    test('libellés des statuts', () {
      Abonnement statut(String s) => Abonnement(
            estAnnexe: false,
            statut: s,
            plan: 'annuel',
            montantFcfa: 200000,
            essaiJours: 30,
            lectureSeule: false,
          );
      expect(statut('essai').statutLibelle, 'Essai gratuit');
      expect(statut('grace').statutLibelle, 'Période de grâce');
      expect(statut('expire').statutLibelle, 'Expiré');
      expect(statut('actif').statutLibelle, 'Actif');
    });
  });

  group('Tarifs abonnement', () {
    test('tarifs validés : 1, 3 et 10 ans', () {
      expect(tarifsAbonnement[1], 200000);
      expect(tarifsAbonnement[3], 540000);
      expect(tarifsAbonnement[10], 1600000);
    });

    test('anciens prix avant remise', () {
      expect(ancienTarifAbonnement(1), isNull);
      expect(ancienTarifAbonnement(3), 600000);
      expect(ancienTarifAbonnement(10), 2000000);
    });
  });

  group('ValidationCodePromo', () {
    test('parse une validation en pourcentage', () {
      final validation = ValidationCodePromo.fromJson(const {
        'valide': true,
        'code': 'LANCEMENT10',
        'type_reduction': 'pourcentage',
        'valeur': 10,
        'total_avant': 200000,
        'total_apres': 180000,
      });
      expect(validation.valide, isTrue);
      expect(validation.code, 'LANCEMENT10');
      expect(validation.typeReduction, 'pourcentage');
      expect(validation.valeur, 10);
      expect(validation.totalAvant, 200000);
      expect(validation.totalApres, 180000);
    });
  });
}
