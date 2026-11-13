// Tests de la tranche T5 r3, compléments de l'écran Cultes en direct :
// jauge et capacité du compteur de portes, statistiques par culte et
// par membre. Aides pures du modèle cultes_direct.dart, aucun appel
// réseau, aucune donnée inventée.

import 'package:esystem_church/models/cultes_direct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capaciteValide', () {
    test('entier strictement positif accepté', () {
      expect(capaciteValide('120'), 120);
      expect(capaciteValide(' 80 '), 80);
      expect(capaciteValide('1'), 1);
    });

    test('vide, texte ou zéro et moins rejetés', () {
      expect(capaciteValide(''), isNull);
      expect(capaciteValide('abc'), isNull);
      expect(capaciteValide('0'), isNull);
      expect(capaciteValide('-5'), isNull);
      expect(capaciteValide('12,5'), isNull);
    });
  });

  group('pourcentageJauge', () {
    test('nul sans capacité', () {
      expect(pourcentageJauge(25, null), isNull);
      expect(pourcentageJauge(25, 0), isNull);
    });

    test('pourcentage arrondi', () {
      expect(pourcentageJauge(25, 100), 25);
      expect(pourcentageJauge(1, 3), 33);
      expect(pourcentageJauge(0, 100), 0);
    });

    test('au delà de la capacité, le dépassement se voit', () {
      expect(pourcentageJauge(150, 100), 150);
    });
  });

  group('progressionJauge', () {
    test('zéro sans capacité', () {
      expect(progressionJauge(25, null), 0);
      expect(progressionJauge(25, 0), 0);
    });

    test('moitié à 50 sur 100', () {
      expect(progressionJauge(50, 100), 0.5);
      expect(progressionJauge(0, 100), 0);
    });

    test('bornée à 1 au delà de la capacité', () {
      expect(progressionJauge(150, 100), 1.0);
    });
  });

  group('titreStatCulte', () {
    test('clé serveur culte_titre', () {
      expect(
          titreStatCulte({'culte_titre': 'Culte du dimanche'}), 'Culte du dimanche');
    });

    test('clé démo titre', () {
      expect(titreStatCulte({'titre': 'Culte EXEMPLE'}), 'Culte EXEMPLE');
    });

    test('repli sans titre', () {
      expect(titreStatCulte({}), 'Culte');
      expect(titreStatCulte({'titre': ''}), 'Culte');
    });
  });

  group('nomStatMembre', () {
    test('nom du membre', () {
      expect(nomStatMembre({'membre_nom': 'Jean Dupont'}), 'Jean Dupont');
    });

    test('repli sur le matricule puis sur Membre', () {
      expect(nomStatMembre({'membre_matricule': 'ESC-EXEMPLE'}), 'ESC-EXEMPLE');
      expect(nomStatMembre({}), 'Membre');
    });
  });

  group('presentsStat', () {
    test('nombre de présents', () {
      expect(presentsStat({'presents': 3}), 3);
    });

    test('zéro par défaut', () {
      expect(presentsStat({}), 0);
    });
  });
}
