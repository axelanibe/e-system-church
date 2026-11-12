import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Note privée du journal du fidèle : titre, texte, dates. Les notes
/// ne quittent jamais l'appareil, elles ne sont jamais envoyées.
class NoteJournal {
  final String id;
  final String titre;
  final String texte;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteJournal({
    required this.id,
    required this.titre,
    required this.texte,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteJournal.fromJson(Map<String, dynamic> json) => NoteJournal(
        id: json['id'] as String,
        titre: json['titre'] as String? ?? '',
        texte: json['texte'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'texte': texte,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// Journal privé du fidèle, conservé sur l'appareil seulement
/// (stockage sécurisé, une clé par compte). Export et import JSON
/// par fusion, comme dans CONNEXION PROPHÉTIQUE : l'import ajoute
/// les notes sans effacer celles déjà présentes.
class JournalService {
  static const _storage = FlutterSecureStorage();

  String _cle(String userId) => 'journal_notes_$userId';

  Future<List<NoteJournal>> lire(String userId) async {
    final brut = await _storage.read(key: _cle(userId));
    if (brut == null || brut.isEmpty) return [];
    try {
      final liste = jsonDecode(brut) as List<dynamic>;
      final notes = liste
          .map((e) => NoteJournal.fromJson(e as Map<String, dynamic>))
          .toList();
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    } catch (_) {
      return [];
    }
  }

  Future<void> _sauver(String userId, List<NoteJournal> notes) async {
    final brut = jsonEncode(notes.map((n) => n.toJson()).toList());
    await _storage.write(key: _cle(userId), value: brut);
  }

  Future<NoteJournal> ajouter(
    String userId, {
    required String titre,
    required String texte,
  }) async {
    final notes = await lire(userId);
    final maintenant = DateTime.now();
    final note = NoteJournal(
      id: 'n${maintenant.microsecondsSinceEpoch}',
      titre: titre,
      texte: texte,
      createdAt: maintenant,
      updatedAt: maintenant,
    );
    notes.insert(0, note);
    await _sauver(userId, notes);
    return note;
  }

  Future<void> modifier(
    String userId,
    NoteJournal note, {
    required String titre,
    required String texte,
  }) async {
    final notes = await lire(userId);
    final i = notes.indexWhere((n) => n.id == note.id);
    if (i < 0) return;
    notes[i] = NoteJournal(
      id: note.id,
      titre: titre,
      texte: texte,
      createdAt: note.createdAt,
      updatedAt: DateTime.now(),
    );
    await _sauver(userId, notes);
  }

  Future<void> supprimer(String userId, String noteId) async {
    final notes = await lire(userId);
    notes.removeWhere((n) => n.id == noteId);
    await _sauver(userId, notes);
  }

  /// Exporte les notes en JSON (octets UTF-8, à partager ou à garder).
  Future<List<int>> exporterJson(String userId) async {
    final notes = await lire(userId);
    return utf8.encode(
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }

  /// Importe des notes depuis un JSON, par fusion : les notes déjà
  /// présentes sont gardées, la plus récente gagne en cas de même
  /// identifiant. Renvoie le nombre de notes ajoutées ou mises à jour.
  Future<int> importerJson(String userId, List<int> octets) async {
    final liste = jsonDecode(utf8.decode(octets)) as List<dynamic>;
    final importees = liste
        .map((e) => NoteJournal.fromJson(e as Map<String, dynamic>))
        .toList();
    final notes = await lire(userId);
    var changes = 0;
    for (final importee in importees) {
      final i = notes.indexWhere((n) => n.id == importee.id);
      if (i < 0) {
        notes.add(importee);
        changes++;
      } else if (importee.updatedAt.isAfter(notes[i].updatedAt)) {
        notes[i] = importee;
        changes++;
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _sauver(userId, notes);
    return changes;
  }
}
