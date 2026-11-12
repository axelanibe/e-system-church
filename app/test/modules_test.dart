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

  test('ModuleEglise.fromJson : tous actifs par règle (11/11/2026)', () {
    // Le serveur renvoie désormais `actif: true` pour tous les modules,
    // noyau compris, sans choix d'activation.
    final modules = [
      ModuleEglise.fromJson({
        'code': 'membres',
        'label': 'Membres',
        'noyau': true,
        'actif': true,
      }),
      ModuleEglise.fromJson({
        'code': 'cultes',
        'label': 'Cultes',
        'noyau': false,
        'actif': true,
      }),
    ];
    expect(modules.length, 2);
    expect(modules.every((m) => m.actif), isTrue);
    expect(modules.where((m) => m.noyau).length, 1);
  });
}
