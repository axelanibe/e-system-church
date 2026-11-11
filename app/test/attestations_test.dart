import 'package:esystem_church/models/attestation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Attestation.fromJson lit une attestation émise', () {
    final a = Attestation.fromJson({
      'id': 'a1',
      'numero': 'ATT-2026-0001',
      'annee': 2026,
      'member_id': 'm1',
      'membre_nom': 'KOFFI JEAN',
      'membre_matricule': 'M-0001',
      'total_fcfa': 75000,
      'nb_dons': 3,
      'statut': 'emise',
      'remplace_id': null,
      'date_emission': '2026-11-11T10:00:00.000Z',
    });
    expect(a.numero, 'ATT-2026-0001');
    expect(a.annee, 2026);
    expect(a.totalFcfa, 75000);
    expect(a.nbDons, 3);
    expect(a.estEmise, isTrue);
    expect(a.membreNom, 'KOFFI JEAN');
  });

  test('Attestation annulée n’est pas émise', () {
    final a = Attestation.fromJson({
      'id': 'a2',
      'numero': 'ATT-2026-0001',
      'annee': 2026,
      'total_fcfa': 1000,
      'nb_dons': 1,
      'statut': 'annulee',
      'remplace_id': 'a3',
    });
    expect(a.estEmise, isFalse);
    expect(a.remplaceId, 'a3');
  });
}
