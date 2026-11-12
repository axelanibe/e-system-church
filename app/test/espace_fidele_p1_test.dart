import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/models/fidele.dart';
import 'package:esystem_church/services/journal_service.dart';

/// Tranche P1 : espace membre et coquille fidèle.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('MessageFidele', () {
    test('parse un message du fidèle', () {
      final message = MessageFidele.fromJson(const {
        'id': 'EXEMPLE-1',
        'auteur': 'membre',
        'corps': 'Bonjour, EXEMPLE',
        'created_at': '2026-11-12T10:00:00.000Z',
      });
      expect(message.id, 'EXEMPLE-1');
      expect(message.auteur, 'membre');
      expect(message.corps, 'Bonjour, EXEMPLE');
      expect(message.deMoi, isTrue);
      expect(message.createdAt, isNotNull);
    });

    test('parse un message de l’église', () {
      final message = MessageFidele.fromJson(const {
        'id': 'EXEMPLE-2',
        'auteur': 'eglise',
        'corps': 'Bonjour, EXEMPLE',
        'created_at': null,
      });
      expect(message.deMoi, isFalse);
      expect(message.createdAt, isNull);
    });

    test('FilMessages parse le destinataire et le fil', () {
      final fil = FilMessages.fromJson(const {
        'destinataire_nom': 'Église EXEMPLE',
        'messages': [
          {
            'id': 'EXEMPLE-1',
            'auteur': 'membre',
            'corps': 'Premier message EXEMPLE',
            'created_at': '2026-11-12T10:00:00.000Z',
          },
          {
            'id': 'EXEMPLE-2',
            'auteur': 'eglise',
            'corps': 'Réponse EXEMPLE',
            'created_at': '2026-11-12T10:05:00.000Z',
          },
        ],
      });
      expect(fil.destinataireNom, 'Église EXEMPLE');
      expect(fil.messages.length, 2);
      expect(fil.messages.first.deMoi, isTrue);
      expect(fil.messages.last.deMoi, isFalse);
    });
  });

  group('Culte seraiPresent', () {
    test('faux par défaut sans le champ', () {
      final culte = Culte.fromJson(const {
        'id': 'EXEMPLE-culte-1',
        'titre': 'Culte EXEMPLE',
        'date_heure': '2026-11-15T09:00:00.000Z',
      });
      expect(culte.seraiPresent, isFalse);
    });

    test('vrai quand le serveur renvoie serai_present', () {
      final culte = Culte.fromJson(const {
        'id': 'EXEMPLE-culte-1',
        'titre': 'Culte EXEMPLE',
        'date_heure': '2026-11-15T09:00:00.000Z',
        'serai_present': true,
      });
      expect(culte.seraiPresent, isTrue);
    });
  });

  group('NoteJournal', () {
    test('aller-retour JSON', () {
      final note = NoteJournal(
        id: 'EXEMPLE-note-1',
        titre: 'Note EXEMPLE',
        texte: 'Texte EXEMPLE',
        createdAt: DateTime.utc(2026, 11, 12, 10),
        updatedAt: DateTime.utc(2026, 11, 12, 11),
      );
      final relue = NoteJournal.fromJson(note.toJson());
      expect(relue.id, note.id);
      expect(relue.titre, 'Note EXEMPLE');
      expect(relue.texte, 'Texte EXEMPLE');
      expect(relue.createdAt, note.createdAt);
      expect(relue.updatedAt, note.updatedAt);
    });

    test('fusion par id : la plus récente gagne, les autres restent', () {
      final anciennes = [
        NoteJournal(
          id: 'EXEMPLE-a',
          titre: 'Ancienne EXEMPLE',
          texte: 'Texte ancien',
          createdAt: DateTime.utc(2026, 11, 10),
          updatedAt: DateTime.utc(2026, 11, 10),
        ),
        NoteJournal(
          id: 'EXEMPLE-b',
          titre: 'Gardée EXEMPLE',
          texte: 'Texte gardé',
          createdAt: DateTime.utc(2026, 11, 10),
          updatedAt: DateTime.utc(2026, 11, 10),
        ),
      ];
      final importees = [
        NoteJournal(
          id: 'EXEMPLE-a',
          titre: 'Nouvelle EXEMPLE',
          texte: 'Texte nouveau',
          createdAt: DateTime.utc(2026, 11, 10),
          updatedAt: DateTime.utc(2026, 11, 12),
        ),
        NoteJournal(
          id: 'EXEMPLE-c',
          titre: 'Ajoutée EXEMPLE',
          texte: 'Texte ajouté',
          createdAt: DateTime.utc(2026, 11, 12),
          updatedAt: DateTime.utc(2026, 11, 12),
        ),
      ];
      // Même règle que JournalService.importerJson : par id, la plus
      // récente gagne, l'import ajoute sans effacer.
      final parId = {for (final n in anciennes) n.id: n};
      for (final n in importees) {
        final existante = parId[n.id];
        if (existante == null ||
            n.updatedAt.isAfter(existante.updatedAt)) {
          parId[n.id] = n;
        }
      }
      final fusionnees = parId.values.toList();
      expect(fusionnees.length, 3);
      expect(
        fusionnees.firstWhere((n) => n.id == 'EXEMPLE-a').titre,
        'Nouvelle EXEMPLE',
      );
      expect(
        fusionnees.firstWhere((n) => n.id == 'EXEMPLE-b').titre,
        'Gardée EXEMPLE',
      );
      expect(
        fusionnees.firstWhere((n) => n.id == 'EXEMPLE-c').titre,
        'Ajoutée EXEMPLE',
      );
    });
  });

  group('Compte à rebours', () {
    test('découpe jours, heures, minutes', () {
      final maintenant = DateTime.utc(2026, 11, 12, 10, 0);
      final culte = DateTime.utc(2026, 11, 15, 9, 30);
      final reste = culte.difference(maintenant);
      expect(reste.inDays, 2);
      expect(reste.inHours % 24, 23);
      expect(reste.inMinutes % 60, 30);
    });
  });

  group('Mon Parcours', () {
    test('pourcentage = étapes faites / 4', () {
      int pourcentage(List<bool> etapes) =>
          (etapes.where((e) => e).length * 100 / 4).round();
      expect(pourcentage([false, false, false, false]), 0);
      expect(pourcentage([true, false, false, false]), 25);
      expect(pourcentage([true, true, false, false]), 50);
      expect(pourcentage([true, true, true, true]), 100);
    });
  });
}
