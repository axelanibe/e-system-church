import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/fidele.dart';
import 'package:esystem_church/models/pastoral.dart';

/// Tranche T6 : écran pastoral admin (radar, rendez-vous, visites
/// typées, rencontres datées, priorité, cas ouverts).
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('AlerteRadar', () {
    test('parse une alerte avec visite suggérée', () {
      final a = AlerteRadar.fromJson(const {
        'member_id': 'EXEMPLE-M1',
        'membre_nom': 'Membre EXEMPLE',
        'membre_matricule': 'ESC-EXEMPLE',
        'membre_telephone': '+225 00 00 00 00',
        'absences_consecutives': 4,
        'derniere_presence': '2026-10-18T10:00:00.000Z',
        'alerte': 'Alerte EXEMPLE',
        'visite_suggeree': {
          'type': 'domicile',
          'motif': 'Absence prolongée (4 cultes consécutifs)',
        },
      });
      expect(a.memberId, 'EXEMPLE-M1');
      expect(a.membreNom, 'Membre EXEMPLE');
      expect(a.absencesConsecutives, 4);
      expect(a.dernierePresence, '2026-10-18');
      expect(a.alerte, 'Alerte EXEMPLE');
      expect(a.visiteType, 'domicile');
      expect(a.visiteMotif, 'Absence prolongée (4 cultes consécutifs)');
    });

    test('parse une alerte sans dernière présence ni visite suggérée', () {
      final a = AlerteRadar.fromJson(const {
        'member_id': 'EXEMPLE-M2',
        'membre_nom': 'Membre EXEMPLE',
        'absences_consecutives': 3,
        'derniere_presence': null,
        'alerte': 'Alerte EXEMPLE',
      });
      expect(a.dernierePresence, isNull);
      expect(a.visiteType, isNull);
      expect(a.visiteMotif, isNull);
    });
  });

  group('RendezVous admin', () {
    test('parse une demande avec membre joint', () {
      final r = RendezVous.fromJson(const {
        'id': 'EXEMPLE-R1',
        'member_id': 'EXEMPLE-M1',
        'membre_nom': 'Membre EXEMPLE',
        'membre_matricule': 'ESC-EXEMPLE',
        'date_souhaitee': '2026-11-20',
        'creneau': 'Samedi 10 h',
        'motif': 'Motif EXEMPLE',
        'statut': 'confirme',
      });
      expect(r.memberId, 'EXEMPLE-M1');
      expect(r.membreNom, 'Membre EXEMPLE');
      expect(r.membreMatricule, 'ESC-EXEMPLE');
      expect(r.dateSouhaitee, '2026-11-20');
      expect(r.creneau, 'Samedi 10 h');
      expect(r.statut, 'confirme');
    });
  });

  group('VisitePastorale typée', () {
    test('parse une visite domicile avec lieu', () {
      final v = VisitePastorale.fromJson(const {
        'id': 'EXEMPLE-V1',
        'member_id': 'EXEMPLE-M1',
        'date_visite': '2026-11-15',
        'motif': 'Motif EXEMPLE',
        'type': 'domicile',
        'lieu': 'Lieu EXEMPLE',
        'statut': 'planifiee',
      });
      expect(v.type, 'domicile');
      expect(v.typeLabel, 'Domicile');
      expect(v.lieu, 'Lieu EXEMPLE');
    });

    test('visite sans type : Non précisé', () {
      final v = VisitePastorale.fromJson(const {
        'id': 'EXEMPLE-V2',
        'member_id': 'EXEMPLE-M1',
        'date_visite': '2026-11-15',
        'statut': 'planifiee',
      });
      expect(v.type, isNull);
      expect(v.typeLabel, 'Non précisé');
    });
  });

  group('Accompagnement avec priorité', () {
    test('parse une priorité urgente, défaut normale', () {
      final urgent = Accompagnement.fromJson(const {
        'id': 'EXEMPLE-A1',
        'member_id': 'EXEMPLE-M1',
        'type': 'difficulte',
        'priorite': 'urgente',
        'statut': 'en_cours',
      });
      expect(urgent.priorite, 'urgente');
      expect(urgent.prioriteLabel, 'Urgente');

      final defaut = Accompagnement.fromJson(const {
        'id': 'EXEMPLE-A2',
        'member_id': 'EXEMPLE-M1',
        'type': 'famille',
        'statut': 'en_cours',
      });
      expect(defaut.priorite, 'normale');
      expect(defaut.prioriteLabel, 'Normale');
    });
  });

  group('RencontreAccompagnement', () {
    test('parse une rencontre datée', () {
      final r = RencontreAccompagnement.fromJson(const {
        'id': 'EXEMPLE-RC1',
        'accompagnement_id': 'EXEMPLE-A1',
        'date_rencontre': '2026-11-14',
        'note': 'Note EXEMPLE',
      });
      expect(r.accompagnementId, 'EXEMPLE-A1');
      expect(r.dateRencontre, '2026-11-14');
      expect(r.note, 'Note EXEMPLE');
    });
  });
}
