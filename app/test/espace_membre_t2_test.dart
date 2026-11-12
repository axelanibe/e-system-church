import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/contribution.dart';
import 'package:esystem_church/models/member.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tranche T2, espace membre : photo du membre, bannière de l'église,
/// dîme validée. Toutes les données ci-dessous sont étiquetées EXEMPLE :
/// elles ne servent qu'aux tests, jamais en production.
void main() {
  group('T2 espace membre (EXEMPLE)', () {
    test('photo_url du membre lue, null quand aucune photo fournie', () {
      final avec = Member.fromJson({
        'id': 'EXEMPLE-m1',
        'matricule': 'EXEMPLE-M-01',
        'full_name': 'EXEMPLE Membre',
        'status': 'actif',
        'photo_url': 'https://exemple.invalid/photo.jpg',
      });
      expect(avec.photoUrl, 'https://exemple.invalid/photo.jpg');
      final sans = Member.fromJson({
        'id': 'EXEMPLE-m2',
        'matricule': 'EXEMPLE-M-02',
        'full_name': 'EXEMPLE Autre',
        'status': 'actif',
      });
      expect(sans.photoUrl, isNull);
    });

    test('banniere_url de l’église lue, null quand aucune bannière', () {
      final avec = Church.fromJson({
        'id': 'EXEMPLE-e1',
        'code': 'EXEMPLE-ESC-01',
        'name': 'EXEMPLE Église',
        'status': 'active',
        'banniere_url': 'https://exemple.invalid/banniere.jpg',
      });
      expect(avec.banniereUrl, 'https://exemple.invalid/banniere.jpg');
      final sans = Church.fromJson({
        'id': 'EXEMPLE-e2',
        'code': 'EXEMPLE-ESC-02',
        'name': 'EXEMPLE Église 2',
        'status': 'active',
      });
      expect(sans.banniereUrl, isNull);
    });

    test('dîme validée : seules les dîmes confirmées comptent', () {
      final dons = [
        _contribution('dime', 'confirme', 10000),
        _contribution('dime', 'en_attente', 5000),
        _contribution('offrande', 'confirme', 2000),
        _contribution('dime', 'annule', 3000),
      ];
      final dimeValidee = dons
          .where((c) => c.type == 'dime' && c.status == 'confirme')
          .fold<int>(0, (s, c) => s + c.amountFcfa);
      expect(dimeValidee, 10000);
    });
  });
}

Contribution _contribution(String type, String status, int montant) =>
    Contribution.fromJson({
      'id': 'EXEMPLE-c-$type-$status-$montant',
      'type': type,
      'amount_fcfa': montant,
      'payment_method': 'especes',
      'status': status,
    });
