import 'package:esystem_church/demo/mock_api_service.dart';
import 'package:esystem_church/demo/mock_data.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/utils/qr_carte.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scan QR réel : lecture du QR de la carte et pointage en mode démo.
/// La caméra elle-même n'est pas testable ici : aucun test sur un vrai
/// téléphone, le test décisif reste le téléphone d'Axel.
void main() {
  group('lireQrCarte', () {
    test('QR complet code:matricule de la même église', () {
      final r = lireQrCarte('GD-PLAT:GD-002', codeEglise: 'GD-PLAT');
      expect(r.ok, isTrue);
      expect(r.matricule, 'GD-002');
    });

    test('QR d’une autre église refusé avec un message clair', () {
      final r = lireQrCarte('GD-YOP:GY-001', codeEglise: 'GD-PLAT');
      expect(r.ok, isFalse);
      expect(r.erreur, contains('autre église'));
      expect(r.erreur, contains('GD-YOP'));
    });

    test('ancienne carte sans code, matricule seul accepté', () {
      final r = lireQrCarte('GD-002', codeEglise: 'GD-PLAT');
      expect(r.ok, isTrue);
      expect(r.matricule, 'GD-002');
    });

    test('matricule normalisé en majuscules', () {
      final r = lireQrCarte('gd-plat:gd-002', codeEglise: 'GD-PLAT');
      expect(r.ok, isTrue);
      expect(r.matricule, 'GD-002');
    });

    test('QR vide refusé', () {
      final r = lireQrCarte('   ', codeEglise: 'GD-PLAT');
      expect(r.ok, isFalse);
    });

    test('QR avec un membre vide refusé', () {
      final r = lireQrCarte('GD-PLAT:', codeEglise: 'GD-PLAT');
      expect(r.ok, isFalse);
    });

    test('sans église de session, le code n’est pas vérifié', () {
      final r = lireQrCarte('GD-YOP:GY-001');
      expect(r.ok, isTrue);
      expect(r.matricule, 'GY-001');
    });
  });

  group('pointage scanné en démo', () {
    test('QR scanné pointe le membre en mode scan_qr', () async {
      final api = MockApiService();
      await api.login(
        email: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      final lecture = lireQrCarte('GD-PLAT:GD-002', codeEglise: 'GD-PLAT');
      expect(lecture.ok, isTrue);
      final presence = await api.pointerPresence(
        matricule: lecture.matricule,
        culteId: 'demo-culte-1',
        statut: 'present',
        mode: 'scan_qr',
      );
      expect(presence.membreNom, 'Koffi Yao');
      expect(presence.mode, 'scan_qr');
      expect(presence.statut, 'present');
    });

    test('matricule d’une autre église introuvable dans la session', () async {
      final api = MockApiService();
      await api.login(
        email: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      await expectLater(
        api.pointerPresence(
          matricule: 'GY-001',
          culteId: 'demo-culte-1',
          statut: 'present',
          mode: 'scan_qr',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
