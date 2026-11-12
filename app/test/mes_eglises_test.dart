import 'package:esystem_church/models/church.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _egliseJson(String id, String code, String nom) => {
      'role': 'admin_eglise',
      'church': {
        'id': id,
        'code': code,
        'name': nom,
        'parent_church_id': null,
        'city': 'Bingerville',
        'status': 'active',
      },
    };

void main() {
  test('MesEglisesPage.fromJson lit les églises, le total et la pagination',
      () {
    final page = MesEglisesPage.fromJson({
      'eglises': [
        _egliseJson('1', 'ESC-AAAAAA', 'Ministère Évangélique Charismatique'),
        _egliseJson('2', 'ESC-BBBBBB', 'MEC Collège Moderne'),
      ],
      'total': 520,
      'page': 1,
      'limite': 50,
      'pages': 11,
    });
    expect(page.eglises.length, 2);
    expect(page.eglises.first.church.code, 'ESC-AAAAAA');
    expect(page.eglises.first.church.isMere, isTrue);
    expect(page.total, 520);
    expect(page.page, 1);
    expect(page.limite, 50);
    expect(page.pages, 11);
    expect(page.aUneSuite, isTrue);
  });

  test('MesEglisesPage.fromJson : dernière page, sans suite', () {
    final page = MesEglisesPage.fromJson({
      'eglises': [_egliseJson('1', 'ESC-AAAAAA', 'Église Mère')],
      'total': 520,
      'page': 11,
      'limite': 50,
      'pages': 11,
    });
    expect(page.aUneSuite, isFalse);
  });

  test('MesEglisesPage.fromJson : champs absents, valeurs par défaut', () {
    final page = MesEglisesPage.fromJson({});
    expect(page.eglises, isEmpty);
    expect(page.total, 0);
    expect(page.page, 1);
    expect(page.limite, 50);
    expect(page.pages, 0);
    expect(page.aUneSuite, isFalse);
  });
}
