import 'package:esystem_church/screens/login_screen.dart';
import 'package:esystem_church/screens/register_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Identifiant de connexion', () {
    test('vide refusé', () {
      expect(validerIdentifiant(null), isNotNull);
      expect(validerIdentifiant('   '), isNotNull);
    });

    test('e-mail accepté, e-mail sans point refusé', () {
      expect(validerIdentifiant('admin@eglise.ci'), isNull);
      expect(validerIdentifiant('ADMIN@EGLISE.CI'), isNull);
      expect(validerIdentifiant('admin@eglise'), isNotNull);
    });

    test('téléphone accepté avec espaces, tirets et indicatif', () {
      expect(validerIdentifiant('07 47 12 34 01'), isNull);
      expect(validerIdentifiant('07-47-12-34-01'), isNull);
      expect(validerIdentifiant('+225 07 47 12 34 01'), isNull);
      expect(validerIdentifiant('2250747123401'), isNull);
    });

    test('téléphone trop court ou lettres refusés', () {
      expect(validerIdentifiant('0747001'), isNotNull);
      expect(validerIdentifiant('abcdef'), isNotNull);
    });
  });

  group('Téléphone admin facultatif', () {
    test('vide accepté', () {
      expect(validerTelephoneFacultatif(null), isNull);
      expect(validerTelephoneFacultatif(''), isNull);
      expect(validerTelephoneFacultatif('   '), isNull);
    });

    test('trop court refusé, numéro accepté', () {
      expect(validerTelephoneFacultatif('0747'), isNotNull);
      expect(validerTelephoneFacultatif('07 47 12 34 01'), isNull);
    });
  });
}
