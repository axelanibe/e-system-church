import 'package:esystem_church/models/annexe.dart';
import 'package:esystem_church/models/code_tutelle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Annexe.fromJson lit nom, code, ville, niveau et chiffres', () {
    final a = Annexe.fromJson({
      'eglise_id': 'a1',
      'eglise_nom': 'Église Annexe de Yopougon',
      'eglise_code': 'ESC-ABC123',
      'eglise_ville': 'Yopougon',
      'eglise_statut': 'active',
      'niveau': 1,
      'membres_actifs': 12,
      'nombre_contributions': 5,
      'total_fcfa': 75000,
    });
    expect(a.egliseNom, 'Église Annexe de Yopougon');
    expect(a.egliseCode, 'ESC-ABC123');
    expect(a.niveau, 1);
    expect(a.membresActifs, 12);
    expect(a.totalFcfa, 75000);
  });

  test('Annexe.fromJson accepte les nombres en chaînes (bigint Postgres)', () {
    final a = Annexe.fromJson({
      'eglise_id': 'a1',
      'eglise_nom': 'Annexe',
      'eglise_code': 'ESC-ABC123',
      'eglise_statut': 'active',
      'niveau': '2',
      'membres_actifs': '3',
      'nombre_contributions': '1',
      'total_fcfa': '10000',
    });
    expect(a.niveau, 2);
    expect(a.membresActifs, 3);
    expect(a.totalFcfa, 10000);
  });

  test('AnnexeDetail.fromJson lit chiffres, compteurs et modules', () {
    final d = AnnexeDetail.fromJson({
      'eglise': {
        'id': 'a1',
        'code': 'ESC-ABC123',
        'name': 'Annexe',
        'city': 'Bouaké',
        'status': 'active',
      },
      'membres_actifs': 12,
      'nombre_contributions': 5,
      'total_fcfa': 75000,
      'depenses_fcfa': 10000,
      'cultes': 4,
      'presences': 40,
      'annonces': 2,
      'modules': [
        {'code': 'membres', 'label': 'Membres', 'noyau': true, 'actif': true},
        {'code': 'cultes', 'label': 'Cultes', 'noyau': false, 'actif': true},
        {'code': 'medias', 'label': 'Médias', 'noyau': false, 'actif': true},
      ],
    });
    expect(d.name, 'Annexe');
    expect(d.depensesFcfa, 10000);
    expect(d.cultes, 4);
    // Tous les modules sont actifs pour toutes les églises (règle
    // du 11/11/2026) : le détail renvoie `actif: true` partout.
    expect(d.modules.length, 3);
    expect(d.modules.every((m) => m.actif), isTrue);
  });

  test('CodeTutelle.fromJson lit code, statut et église utilisatrice', () {
    final c = CodeTutelle.fromJson({
      'id': 'c1',
      'code': 'ESC-T-AB12CD',
      'status': 'utilise',
      'utilisee_par_nom': 'Église Annexe',
      'utilisee_par_code': 'ESC-ABC123',
      'used_at': '2026-11-11T10:00:00.000Z',
      'created_at': '2026-11-11T09:00:00.000Z',
    });
    expect(c.code, 'ESC-T-AB12CD');
    expect(c.statusLabel, 'Utilisé');
    expect(c.estActif, isFalse);
    expect(c.utiliseeParCode, 'ESC-ABC123');
  });

  test('CodeTutelle actif : libellé et estActif', () {
    final c = CodeTutelle.fromJson({
      'id': 'c1',
      'code': 'ESC-T-XY9876',
      'status': 'actif',
    });
    expect(c.statusLabel, 'Actif');
    expect(c.estActif, isTrue);
  });
}
