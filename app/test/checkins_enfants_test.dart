import 'package:esystem_church/demo/mock_api_service.dart';
import 'package:esystem_church/demo/mock_data.dart';
import 'package:esystem_church/models/checkin_enfant.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Check-ins enfants, double QR ECODIM : modèle et repli démo.
/// La caméra n'est pas testable ici, le test décisif reste le téléphone.
void main() {
  group('CheckinEnfant.fromJson', () {
    test('lit un check-in en classe avec noms joints', () {
      final c = CheckinEnfant.fromJson({
        'id': 'c1',
        'enfant_member_id': 'e1',
        'parent_member_id': 'p1',
        'salle': 'Salle 2',
        'code_enfant': 'KIDS-AB12',
        'allergie': 'Arachides',
        'statut': 'IN_CLASS',
        'alerte': false,
        'alerte_message': null,
        'alerte_at': null,
        'date_checkin': '2026-11-11',
        'checked_in_at': '2026-11-11T09:00:00.000Z',
        'checked_out_at': null,
        'enfant_nom': 'KOFFI MARIE',
        'parent_nom': 'KOFFI JEAN',
      });
      expect(c.enClasse, isTrue);
      expect(c.codeAffiche, '#KIDS-AB12');
      expect(c.enfantNom, 'KOFFI MARIE');
      expect(c.parentNom, 'KOFFI JEAN');
      expect(c.allergie, 'Arachides');
    });

    test('lit un check-in sorti avec alerte', () {
      final c = CheckinEnfant.fromJson({
        'id': 'c2',
        'enfant_member_id': 'e1',
        'parent_member_id': 'p1',
        'salle': null,
        'code_enfant': 'KIDS-AB12',
        'allergie': null,
        'statut': 'CHECKED_OUT',
        'alerte': true,
        'alerte_message': 'Votre enfant vous attend.',
        'alerte_at': '2026-11-11T10:00:00.000Z',
        'date_checkin': '2026-11-11',
        'checked_in_at': '2026-11-11T09:00:00.000Z',
        'checked_out_at': '2026-11-11T11:00:00.000Z',
      });
      expect(c.enClasse, isFalse);
      expect(c.alerte, isTrue);
      expect(c.alerteMessage, 'Votre enfant vous attend.');
      expect(c.checkedOutAt, isNotNull);
    });
  });

  group('repli démo', () {
    test('liste du jour vide, sans effet', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      expect(await api.getCheckinsEnfantsJour(), isEmpty);
    });

    test('check-in refusé en démo', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      expect(
        () => api.checkinEnfant(
          enfantMemberId: 'e1',
          parentMemberId: 'p1',
          codeParent: 'GD-001',
          codeEnfant: 'KIDS-AB12',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
