// Tests de la tranche T5, Cultes en direct : aides pures du modèle
// cultes_direct.dart. Aucun appel réseau, aucune donnée inventée.

import 'package:esystem_church/models/cultes_direct.dart';
import 'package:esystem_church/models/presences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDureeChrono', () {
    test('00:00 au départ', () {
      expect(formatDureeChrono(0), '00:00');
    });

    test('secondes sous la minute', () {
      expect(formatDureeChrono(5), '00:05');
      expect(formatDureeChrono(59), '00:59');
    });

    test('minutes et secondes', () {
      expect(formatDureeChrono(65), '01:05');
      expect(formatDureeChrono(600), '10:00');
    });

    test('au delà de l’heure', () {
      expect(formatDureeChrono(3600), '60:00');
    });

    test('négatif ramené à zéro', () {
      expect(formatDureeChrono(-30), '00:00');
    });
  });

  group('transpositionSuivante', () {
    test('monte et descend d’un demi-ton', () {
      expect(transpositionSuivante(0, 1), 1);
      expect(transpositionSuivante(0, -1), -1);
      expect(transpositionSuivante(3, -2), 1);
    });

    test('bornée à une octave', () {
      expect(transpositionSuivante(11, 1), 11);
      expect(transpositionSuivante(-11, -1), -11);
      expect(transpositionSuivante(10, 5), 11);
      expect(transpositionSuivante(-10, -5), -11);
    });
  });

  group('compteurSuivant', () {
    test('monte et descend', () {
      expect(compteurSuivant(0, 1), 1);
      expect(compteurSuivant(5, -2), 3);
    });

    test('jamais en dessous de zéro', () {
      expect(compteurSuivant(0, -1), 0);
      expect(compteurSuivant(1, -5), 0);
    });
  });

  group('momentTermine', () {
    test('faux avant la durée prévue', () {
      expect(momentTermine(299, 5), isFalse);
    });

    test('vrai à la durée prévue', () {
      expect(momentTermine(300, 5), isTrue);
      expect(momentTermine(301, 5), isTrue);
    });

    test('faux sans durée', () {
      expect(momentTermine(9999, null), isFalse);
      expect(momentTermine(9999, 0), isFalse);
    });
  });

  group('compterPresents', () {
    Presence presence(String statut) => Presence(
          id: 'p-$statut',
          memberId: 'm-$statut',
          statut: statut,
          mode: 'scan_qr',
        );

    test('compte seulement les présents', () {
      final liste = [
        presence('present'),
        presence('present'),
        presence('absent'),
        presence('excuse'),
      ];
      expect(compterPresents(liste), 2);
    });

    test('zéro sur liste vide', () {
      expect(compterPresents([]), 0);
    });
  });
}
