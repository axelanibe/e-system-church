import 'package:esystem_church/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formatage des dates et heures : l'heure murale renvoyée en UTC par
/// le serveur s'affiche telle quelle, sans décalage vers l'heure
/// locale de l'appareil (activités à venir et cultes : 14:00 saisies
/// affichées 09:00 à Toronto avant le correctif).
void main() {
  group('formatDateTimeSansDecalage', () {
    test('heure UTC affichée telle quelle', () {
      expect(
        formatDateTimeSansDecalage(DateTime.utc(2026, 11, 25, 14, 0)),
        '25/11/2026 14:00',
      );
    });

    test('valeur nulle', () {
      expect(formatDateTimeSansDecalage(null), '—');
    });
  });

  group('afficherDateTimeSansDecalage', () {
    test('chaîne ISO UTC affichée telle quelle', () {
      expect(
        afficherDateTimeSansDecalage('2026-11-25T14:00:00.000Z'),
        '25/11/2026 14:00',
      );
    });

    test('DateTime UTC affiché tel quel', () {
      expect(
        afficherDateTimeSansDecalage(DateTime.utc(2026, 11, 25, 14, 0)),
        '25/11/2026 14:00',
      );
    });

    test('valeur nulle', () {
      expect(afficherDateTimeSansDecalage(null), '—');
    });

    test('chaîne non datée renvoyée telle quelle', () {
      expect(afficherDateTimeSansDecalage('texte libre'), 'texte libre');
    });
  });
}
