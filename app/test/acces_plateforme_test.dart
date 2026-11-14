import 'package:esystem_church/models/acces_plateforme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AccesPlateforme.fromJson lit un aide', () {
    final acces = AccesPlateforme.fromJson({
      'user_id': 'u1',
      'nom': 'Aide Exemple',
      'email': 'aide@exemple.ci',
      'role': 'aide_plateforme',
      'droits': ['chiffres'],
      'cree_le': '2026-11-13T10:00:00.000Z',
    });
    expect(acces.userId, 'u1');
    expect(acces.nom, 'Aide Exemple');
    expect(acces.estSuperAdmin, isFalse);
    expect(acces.roleLabel, 'Aide Plateforme');
    expect(acces.droits, ['chiffres']);
    expect(acces.creeLe?.year, 2026);
  });

  test('AccesPlateforme.fromJson lit un super_admin', () {
    final acces = AccesPlateforme.fromJson({
      'user_id': 'u0',
      'nom': 'Admin',
      'email': 'admin@exemple.ci',
      'role': 'super_admin',
      'droits': ['chiffres', 'acces'],
      'cree_le': null,
    });
    expect(acces.estSuperAdmin, isTrue);
    expect(acces.roleLabel, 'Admin plateforme');
    expect(acces.creeLe, isNull);
  });

  test('AccesPlateformeCree.fromJson lit un nouveau compte avec lien', () {
    final cree = AccesPlateformeCree.fromJson({
      'user': {
        'id': 'u2',
        'email': 'nouveau@exemple.ci',
        'full_name': 'Nouveau',
      },
      'deja_membre': false,
      'lien_invitation': 'https://exemple.ci/initialiser?token=abc',
      'expires_at': '2026-11-20T10:00:00.000Z',
    });
    expect(cree.dejaMembre, isFalse);
    expect(cree.lienInvitation, contains('initialiser?token='));
    expect(cree.expiresAt?.day, 20);
  });

  test('AccesPlateformeCree.fromJson lit un membre existant sans lien', () {
    final cree = AccesPlateformeCree.fromJson({
      'user': {
        'id': 'u3',
        'email': 'admin@exemple.ci',
        'full_name': 'Admin',
      },
      'deja_membre': true,
    });
    expect(cree.dejaMembre, isTrue);
    expect(cree.lienInvitation, isNull);
  });
}
