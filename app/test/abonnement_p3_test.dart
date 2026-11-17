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

    test('parse date_debut', () {
      final abo = Abonnement.fromJson(const {
        'est_annexe': false,
        'abonnement': {
          'statut': 'essai',
          'date_debut': '2026-11-06',
          'date_expiration': null,
          'essai_jours': 30,
        },
      });
      expect(abo.dateDebut, DateTime(2026, 11, 6));
    });
  });

  group('Jours restants', () {
    // Date de référence fixe : le calcul ne dépend jamais de l'heure
    // d'exécution des tests.
    final ref = DateTime(2026, 11, 16);

    Abonnement abo({
      required String statut,
      DateTime? dateDebut,
      DateTime? dateExpiration,
    }) =>
        Abonnement(
          estAnnexe: false,
          statut: statut,
          plan: 'annuel',
          montantFcfa: 200000,
          dateDebut: dateDebut,
          dateExpiration: dateExpiration,
          essaiJours: 30,
          lectureSeule: false,
        );

    test('essai commencé il y a 10 jours : 20 restants', () {
      expect(
        abo(statut: 'essai', dateDebut: DateTime(2026, 11, 6))
            .joursRestantsLe(ref),
        20,
      );
    });

    test('expiration dans 45 jours : 45', () {
      expect(
        abo(statut: 'actif', dateExpiration: DateTime(2026, 12, 31))
            .joursRestantsLe(ref),
        45,
      );
    });

    test('grâce, expiration passée de 5 jours : 25 restants', () {
      expect(
        abo(statut: 'grace', dateExpiration: DateTime(2026, 11, 11))
            .joursRestantsLe(ref),
        25,
      );
    });

    test('expiré depuis 40 jours : borné à 0, jamais négatif', () {
      expect(
        abo(statut: 'expire', dateExpiration: DateTime(2026, 10, 7))
            .joursRestantsLe(ref),
        0,
      );
    });

    test('aucune date : null, rien à afficher', () {
      expect(abo(statut: 'actif').joursRestantsLe(ref), isNull);
      expect(
        abo(statut: 'essai').joursRestantsLe(ref),
        isNull,
      );
    });

    test('dates avec heure : comparaison en dates seules', () {
      // Essai commencé le 6 à 23 h, référence le 16 à 1 h : 20 jours,
      // pas 19 à cause des heures.
      expect(
        abo(
          statut: 'essai',
          dateDebut: DateTime(2026, 11, 6, 23),
        ).joursRestantsLe(DateTime(2026, 11, 16, 1)),
        20,
      );
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
