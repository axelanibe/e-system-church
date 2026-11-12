import 'package:esystem_church/models/nettoyage_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NettoyageTestApercu.fromJson lit les 7 éléments TEST de l’audit', () {
    final apercu = NettoyageTestApercu.fromJson({
      'elements': [
        {'type': 'transfert', 'id': 't1', 'label': 'Transfert TEST Membre Audit (M-0002 → M-0001, accepte)'},
        {'type': 'attestation', 'id': 'a1', 'label': 'Attestation ATT-2026-0001 (2026, 1 000 FCFA)'},
        {'type': 'contribution', 'id': 'c1', 'label': 'Dîme 1 000 FCFA (TEST-001)'},
        {'type': 'contribution', 'id': 'c2', 'label': 'Dépense 500 FCFA (TEST-DEP-001)'},
        {'type': 'campagne', 'id': 'ca1', 'label': 'Campagne TEST Campagne Audit (objectif 10 000 FCFA)'},
        {'type': 'membre', 'id': 'm1', 'label': 'Membre TEST Membre Audit (M-0001)'},
        {'type': 'eglise', 'id': 'e1', 'label': 'Sous-église TEST Sous-église Audit (ESC-PWBYKY)'},
      ],
      'total': 7,
    });
    expect(apercu.total, 7);
    expect(apercu.elements.map((e) => e.type).toSet(),
        {'transfert', 'attestation', 'contribution', 'campagne', 'membre', 'eglise'});
    expect(apercu.elements[2].label, 'Dîme 1 000 FCFA (TEST-001)');
  });

  test('NettoyageTestApercu vide : total 0', () {
    final apercu = NettoyageTestApercu.fromJson({'elements': [], 'total': 0});
    expect(apercu.total, 0);
    expect(apercu.elements, isEmpty);
  });

  test('NettoyageTestResultat.fromJson lit les éléments supprimés', () {
    final resultat = NettoyageTestResultat.fromJson({
      'ok': true,
      'supprimes': [
        {'type': 'membre', 'id': 'm1', 'label': 'Membre TEST Membre Audit (M-0001)'},
      ],
      'total': 1,
    });
    expect(resultat.total, 1);
    expect(resultat.supprimes.first.type, 'membre');
  });
}
