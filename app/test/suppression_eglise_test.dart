import 'package:esystem_church/models/suppression_eglise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SuppressionEgliseApercu.fromJson lit l\u2019aperçu TEST', () {
    final apercu = SuppressionEgliseApercu.fromJson({
      'eglise': {'id': 'e0', 'nom': 'TEST Église', 'code': 'ESC-4240'},
      'annexes': [
        {'id': 'e1', 'nom': 'TEST Annexe', 'code': 'ESC-4241'},
      ],
      'comptes': {
        'members': 2,
        'contributions': 3,
        'campagnes': 1,
        'attestations': 1,
        'transferts_membre': 1,
        'church_users': 1,
      },
      'utilisateurs_supprimes': 1,
      'total': 12,
    });
    expect(apercu.eglise.nom, 'TEST Église');
    expect(apercu.eglise.code, 'ESC-4240');
    expect(apercu.annexes.length, 1);
    expect(apercu.annexes.first.nom, 'TEST Annexe');
    expect(apercu.comptes['members'], 2);
    expect(apercu.utilisateursSupprimes, 1);
    expect(apercu.total, 12);
    expect(apercu.lignesComptes.first, 'Contributions : 3');
    expect(apercu.lignesComptes, contains('Membres : 2'));
  });

  test('SuppressionEgliseApercu vide : total 1 (l\u2019église seule)', () {
    final apercu = SuppressionEgliseApercu.fromJson({
      'eglise': {'id': 'e0', 'nom': 'TEST Vide', 'code': 'ESC-4242'},
      'annexes': [],
      'comptes': {},
      'utilisateurs_supprimes': 0,
    });
    expect(apercu.total, 1);
    expect(apercu.lignesComptes, isEmpty);
  });

  test('SuppressionEgliseResultat.fromJson lit le résultat', () {
    final resultat = SuppressionEgliseResultat.fromJson({
      'ok': true,
      'eglise': {'id': 'e0', 'nom': 'TEST Église', 'code': 'ESC-4240'},
      'annexes': [],
      'comptes': {'members': 2, 'contributions': 1},
      'utilisateurs_supprimes': 0,
      'total': 4,
    });
    expect(resultat.total, 4);
    expect(resultat.eglise.code, 'ESC-4240');
  });
}
