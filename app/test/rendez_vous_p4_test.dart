import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/fidele.dart';

/// Tranche P4 : rendez-vous membre.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('RendezVous', () {
    test('parse une demande avec date ISO', () {
      final rdv = RendezVous.fromJson(const {
        'id': 'EXEMPLE-1',
        'date_souhaitee': '2026-11-20T00:00:00.000Z',
        'creneau': null,
        'motif': 'Motif EXEMPLE',
        'statut': 'en_attente',
        'created_at': '2026-11-12T10:00:00.000Z',
      });
      expect(rdv.id, 'EXEMPLE-1');
      expect(rdv.dateSouhaitee, '2026-11-20');
      expect(rdv.date, DateTime(2026, 11, 20));
      expect(rdv.creneau, isNull);
      expect(rdv.motif, 'Motif EXEMPLE');
      expect(rdv.statut, 'en_attente');
      expect(rdv.createdAt, isNotNull);
    });

    test('parse une demande avec créneau et statut confirmé', () {
      final rdv = RendezVous.fromJson(const {
        'id': 'EXEMPLE-2',
        'date_souhaitee': '2026-11-21',
        'creneau': 'Créneau EXEMPLE',
        'motif': 'Motif EXEMPLE',
        'statut': 'confirme',
        'created_at': null,
      });
      expect(rdv.dateSouhaitee, '2026-11-21');
      expect(rdv.date, DateTime(2026, 11, 21));
      expect(rdv.creneau, 'Créneau EXEMPLE');
      expect(rdv.statut, 'confirme');
      expect(rdv.createdAt, isNull);
    });

    test('statut par défaut en_attente', () {
      final rdv = RendezVous.fromJson(const {
        'id': 'EXEMPLE-3',
        'date_souhaitee': '2026-11-22',
        'motif': 'Motif EXEMPLE',
      });
      expect(rdv.statut, 'en_attente');
      expect(rdv.creneau, isNull);
      expect(rdv.date, DateTime(2026, 11, 22));
    });
  });
}
