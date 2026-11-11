import 'package:esystem_church/models/module_eglise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ModuleEglise.fromJson lit code, label, noyau et actif', () {
    final m = ModuleEglise.fromJson({
      'code': 'cultes',
      'label': 'Cultes',
      'noyau': false,
      'actif': true,
    });
    expect(m.code, 'cultes');
    expect(m.label, 'Cultes');
    expect(m.noyau, isFalse);
    expect(m.actif, isTrue);
    expect(m.copyWith(actif: false).actif, isFalse);
  });

  test('ModuleEglise.fromJson : actif absent vaut faux', () {
    final m = ModuleEglise.fromJson({
      'code': 'annonces',
      'label': 'Annonces',
      'noyau': false,
    });
    expect(m.actif, isFalse);
  });

  test('CodesModules : 13 codes activables, noyau à part', () {
    const activables = [
      CodesModules.annonces,
      CodesModules.familles,
      CodesModules.cultes,
      CodesModules.presences,
      CodesModules.budget,
      CodesModules.prieres,
      CodesModules.pastoral,
      CodesModules.serviteurs,
      CodesModules.enfants,
      CodesModules.medias,
      CodesModules.biens,
      CodesModules.parametres,
      CodesModules.monEglise,
    ];
    expect(activables.toSet().length, 13);
    expect(CodesModules.noyau, ['membres', 'finances', 'rapports']);
    for (final code in activables) {
      expect(CodesModules.noyau.contains(code), isFalse);
    }
  });
}
