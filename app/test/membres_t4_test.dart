import 'package:esystem_church/models/anniversaire.dart';
import 'package:esystem_church/models/frequentation.dart';
import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/models/membres_complement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T4 — statut ancien', () {
    test('labelForStatus ancien vaut Ancien', () {
      expect(Member.labelForStatus('ancien'), 'Ancien');
    });

    test('membre au statut riche ancien affiche Ancien', () {
      final membre = Member.fromJson(<String, dynamic>{
        'id': 'm1',
        'full_name': 'Jean Dupont',
        'matricule': 'ESC-0001',
        'status': 'inactif',
        'statut_riche': 'ancien',
      });
      expect(membre.estAncien, isTrue);
      expect(membre.statutAffiche, 'Ancien');
    });

    test('membre actif sans statut riche affiche Actif', () {
      final membre = Member.fromJson(<String, dynamic>{
        'id': 'm2',
        'full_name': 'Marie Konan',
        'matricule': 'ESC-0002',
        'status': 'actif',
      });
      expect(membre.estAncien, isFalse);
      expect(membre.statutAffiche, 'Actif');
    });

    test('MembreStatut ancien vaut Ancien', () {
      expect(MembreStatut.labelForStatut('ancien'), 'Ancien');
    });
  });

  group('T4 — dates d’événements de vie (migration 019)', () {
    test('date de mariage et de conversion lues depuis le JSON', () {
      final membre = Member.fromJson(<String, dynamic>{
        'id': 'm3',
        'full_name': 'Paul Kouassi',
        'matricule': 'ESC-0003',
        'status': 'actif',
        'date_mariage': '2015-06-14',
        'date_conversion': '2010-03-02',
      });
      expect(membre.dateMariage, '2015-06-14');
      expect(membre.dateConversion, '2010-03-02');
    });

    test('dates absentes restent nulles, jamais inventées', () {
      final membre = Member.fromJson(<String, dynamic>{
        'id': 'm4',
        'full_name': 'Anne Bamba',
        'matricule': 'ESC-0004',
        'status': 'actif',
      });
      expect(membre.dateMariage, isNull);
      expect(membre.dateConversion, isNull);
    });
  });

  group('T4 — anniversaires proches', () {
    test('anniversaire lu depuis le JSON', () {
      final anniversaire = Anniversaire.fromJson(<String, dynamic>{
        'id': 'm5',
        'full_name': 'Luc Yao',
        'matricule': 'ESC-0005',
        'birth_date': '1990-11-20',
        'prochain': '2026-11-20',
        'jours_restants': 8,
        'age_atteint': 36,
      });
      expect(anniversaire.fullName, 'Luc Yao');
      expect(anniversaire.joursRestants, 8);
      expect(anniversaire.ageAtteint, 36);
    });
  });

  group('T4 — fréquentation', () {
    test('fréquentation lue depuis le JSON', () {
      final frequentation = Frequentation.fromJson(<String, dynamic>{
        'total': 4,
        'presents': 3,
        'items': [
          {
            'id': 'p1',
            'statut': 'present',
            'mode': 'scan_qr',
            'titre': 'Culte du dimanche',
            'date_evenement': '2026-11-08',
            'type': 'culte',
          },
          {
            'id': 'p2',
            'statut': 'absent',
            'mode': 'manuel',
            'titre': 'Culte du dimanche',
            'date_evenement': '2026-11-01',
            'type': 'culte',
          },
        ],
      });
      expect(frequentation.total, 4);
      expect(frequentation.presents, 3);
      expect(frequentation.items.length, 2);
      expect(frequentation.items.first.statutLabel, 'Présent');
      expect(frequentation.items.last.statutLabel, 'Absent');
    });

    test('fréquentation vide : 0 sur 0', () {
      final frequentation = Frequentation.fromJson(<String, dynamic>{
        'total': 0,
        'presents': 0,
        'items': [],
      });
      expect(frequentation.total, 0);
      expect(frequentation.items, isEmpty);
    });
  });
}
