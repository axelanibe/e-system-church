import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/confiance.dart';
import 'package:esystem_church/models/parametres.dart';
import 'package:esystem_church/services/file_hors_ligne_service.dart';

/// Tranche T11 : confiance, sauvegarde, hors ligne, 2FA, audit,
/// notifications. Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('Sauvegarde', () {
    test('parse une sauvegarde disponible, taille lisible', () {
      final s = Sauvegarde.fromJson(const {
        'id': 'EXEMPLE-SVG-1',
        'taille_octets': 2048,
        'empreinte': 'abc123',
        'nb_tables': 12,
        'tables': ['members', 'contributions'],
        'statut': 'ok',
        'created_at': '2026-11-14T03:00:00Z',
      });
      expect(s.tailleLabel, '2.0 Ko');
      expect(s.statutLabel, 'Disponible');
      expect(s.nbTables, 12);
    });

    test('une sauvegarde restaurée porte son statut', () {
      final s = Sauvegarde.fromJson(const {
        'id': 'EXEMPLE-SVG-2',
        'taille_octets': 512,
        'empreinte': 'def456',
        'nb_tables': 3,
        'tables': ['members'],
        'statut': 'restauree',
      });
      expect(s.statutLabel, 'Restaurée');
      expect(s.tailleLabel, '512 o');
    });
  });

  group('NotificationConfiance', () {
    test('statut non configurée quand aucun fournisseur', () {
      final n = NotificationConfiance.fromJson(const {
        'id': 'EXEMPLE-NOT-1',
        'canal': 'sms',
        'titre': 'Rappel',
        'message': 'Culte dimanche.',
        'statut': 'non_configurée',
        'erreur': 'fournisseur_non_configure',
      });
      expect(n.canalLabel, 'SMS');
      expect(n.statutLabel, 'Non configurée');
    });
  });

  group('AuditEntree et VerificationAudit', () {
    test('parse une ligne avec hash chaîné', () {
      final e = AuditEntree.fromJson(const {
        'id': 'EXEMPLE-AUD-1',
        'user_nom': 'Admin EXEMPLE',
        'action': 'membre.cree',
        'details': {'membre_nom': 'Membre EXEMPLE'},
        'hash': 'aabbcc',
        'hash_precedent': '001122',
        'created_at': '2026-11-14T05:00:00Z',
      });
      expect(e.action, 'membre.cree');
      expect(e.hashPrecedent, '001122');
      expect(e.utilisateur, 'Admin EXEMPLE');
    });

    test('chaîne rompue signalée avec la rupture', () {
      final v = VerificationAudit.fromJson(const {
        'ok': false,
        'total': 10,
        'verifies': 7,
        'ruptureId': 'EXEMPLE-AUD-8',
      });
      expect(v.ok, isFalse);
      expect(v.verifies, 7);
      expect(v.ruptureId, 'EXEMPLE-AUD-8');
    });
  });

  group('ActionHorsLigne', () {
    test('libellés pointage et contribution', () {
      final p = ActionHorsLigne.fromJson(const {
        'id': 'EXEMPLE-ACT-1',
        'type_action': 'presence.pointer',
        'charge': {'matricule': 'EXEMPLE-MAT-1'},
        'cle_client': 'EXEMPLE-CLE-1',
        'statut': 'en_attente',
      });
      expect(p.typeLabel, 'Pointage');
      expect(p.statutLabel, 'En attente');
      final c = ActionHorsLigne.fromJson(const {
        'id': 'EXEMPLE-ACT-2',
        'type_action': 'contribution.creer',
        'charge': {'type': 'offrande', 'amount_fcfa': 5000},
        'cle_client': 'EXEMPLE-CLE-2',
        'statut': 'echouee',
        'erreur': 'Charge de contribution invalide.',
      });
      expect(c.typeLabel, 'Contribution');
      expect(c.statutLabel, 'En échec');
    });
  });

  group('ParametresConfiance', () {
    test('jamais par défaut, clé jamais renvoyée', () {
      final p = ParametresConfiance.fromJson(const {
        'sauvegarde_frequence': 'jamais',
        'sauvegarde_heure': '03:00',
        'notification_fournisseur': null,
        'notification_plafond_mensuel': 0,
        'notifications_actives': false,
        'notifications_configurees': false,
      });
      expect(p.frequenceLabel, 'Jamais');
      expect(p.notificationsConfigurees, isFalse);
      expect(p.notificationFournisseur, isNull);
    });
  });

  group('Demarrage2fa', () {
    test('parse l’URI otpauth et le secret', () {
      final d = Demarrage2fa.fromJson(const {
        'otpauth_uri':
            'otpauth://totp/e-System%20Church:EXEMPLE?secret=EXEMPLESECRET&issuer=e-System%20Church',
        'secret': 'EXEMPLESECRET',
      });
      expect(d.secret, 'EXEMPLESECRET');
      expect(d.otpauthUri, startsWith('otpauth://totp/'));
    });
  });

  group('ActionEnFile', () {
    test('sérialisation aller-retour de la file locale', () {
      final action = ActionEnFile(
        cleClient: 'EXEMPLE-CLE-LOCALE-1',
        typeAction: 'presence.pointer',
        charge: const {'matricule': 'EXEMPLE-MAT-1', 'culte_id': 'EXEMPLE-C1'},
        createdAt: DateTime.utc(2026, 11, 14, 5, 0),
      );
      final relue = ActionEnFile.fromJson(action.toJson());
      expect(relue.cleClient, 'EXEMPLE-CLE-LOCALE-1');
      expect(relue.typeAction, 'presence.pointer');
      expect(relue.charge['matricule'], 'EXEMPLE-MAT-1');
      expect(relue.erreur, isNull);
    });
  });
}
