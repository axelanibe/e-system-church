// Service Bible hors ligne — tranche T9.
//
// Lit la Bible (Louis Segond 1910 et King James, domaine public), la
// concordance Strong et le dictionnaire biblique depuis les JSON
// bundlés dans l'appli (`assets/bible/`, déclarés dans pubspec.yaml).
// Aucun appel réseau : il sert de repli quand l'API est injoignable
// ([ApiException] avec le code `hors_ligne`) — voir [HttpApiService].
// L'école biblique (cours, inscriptions, progression) reste côté
// serveur : pas de repli hors ligne.

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/bible.dart';
import 'api_service.dart';

/// Bible hors ligne : lectures depuis les assets bundlés, avec cache
/// en mémoire (un livre chargé le reste ; la recherche parcourt le
/// canon chargé).
class BibleHorsLigneService {
  /// Canon (métadonnées des 66 livres) lu depuis l'asset livres.json,
  /// par version (lsg1910, kjv).
  final Map<String, List<LivreBible>> _canonBible = {};

  /// Livres déjà chargés depuis les assets (« version:CODE » -> contenu).
  final Map<String, LivreBibleAsset> _livresBible = {};

  /// Lexiques Strong déjà chargés (grec, hebreu).
  final Map<String, Map<String, dynamic>> _lexiquesStrong = {};

  /// Dictionnaires déjà chargés (fra, eng).
  final Map<String, List<ArticleDictionnaire>> _dictionnaires = {};

  Future<List<LivreBible>> _canon({String version = 'lsg1910'}) async {
    final enCache = _canonBible[version];
    if (enCache != null) return enCache;
    final brut =
        await rootBundle.loadString('assets/bible/$version/livres.json');
    final liste = (jsonDecode(brut) as List)
        .map((e) => LivreBible.fromJson(e as Map<String, dynamic>))
        .toList();
    _canonBible[version] = liste;
    return liste;
  }

  Future<LivreBibleAsset> _livreBible(String code,
      {String version = 'lsg1910'}) async {
    final maj = code.toUpperCase();
    final cle = '$version:$maj';
    final enCache = _livresBible[cle];
    if (enCache != null) return enCache;
    final brut =
        await rootBundle.loadString('assets/bible/$version/$maj.json');
    final livre =
        LivreBibleAsset.fromJson(jsonDecode(brut) as Map<String, dynamic>);
    _livresBible[cle] = livre;
    return livre;
  }

  Future<Map<String, dynamic>> _lexiqueStrong(String langue) async {
    final enCache = _lexiquesStrong[langue];
    if (enCache != null) return enCache;
    final fichier =
        langue == 'hebreu' ? 'strong-hébreu.json' : 'strong-grec.json';
    final brut = await rootBundle.loadString('assets/bible/strong/$fichier');
    final lexique = Map<String, dynamic>.from(
        jsonDecode(brut) as Map<String, dynamic>);
    _lexiquesStrong[langue] = lexique;
    return lexique;
  }

  Future<List<ArticleDictionnaire>> _dictionnaire(
      {String langue = 'fra'}) async {
    final enCache = _dictionnaires[langue];
    if (enCache != null) return enCache;
    final brut = await rootBundle
        .loadString('assets/bible/dictionnaire/dictionnaire-$langue.json');
    // Le JSON bundlé est compact (clés « t » / « c ») ; l'API renvoie
    // « titre » / « texte » — on traduit ici.
    final articles = (jsonDecode(brut) as List).map((e) {
      final entree = e as Map<String, dynamic>;
      return ArticleDictionnaire(
        titre: entree['t'] as String,
        texte: entree['c'] as String,
      );
    }).toList();
    _dictionnaires[langue] = articles;
    return articles;
  }

  /// Normalisation insensible à la casse et aux accents (recherche).
  String _normaliser(String texte) {
    const accents = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    final bas = texte.toLowerCase();
    final tampon = StringBuffer();
    for (var i = 0; i < bas.length; i++) {
      tampon.write(accents[bas[i]] ?? bas[i]);
    }
    return tampon.toString();
  }

  Future<List<VersionBible>> getVersionsBible() async {
    // Totaux de versets vérifiés à la source (eBible.org) : LS1910
    // 31 170 versets, KJV 31 102 versets (voir SOURCES.md).
    const versets = {'lsg1910': 31170, 'kjv': 31102};
    const noms = {
      'lsg1910': 'Louis Segond 1910',
      'kjv': 'King James Version',
    };
    const langues = {'lsg1910': 'fr', 'kjv': 'en'};
    final versions = <VersionBible>[];
    for (final id in ['lsg1910', 'kjv']) {
      final livres = await _canon(version: id);
      versions.add(VersionBible(
        id: id,
        nom: noms[id]!,
        langue: langues[id]!,
        livres: livres.length,
        versets: versets[id]!,
      ));
    }
    return versions;
  }

  Future<List<LivreBible>> getLivresBible({String version = 'lsg1910'}) async {
    return List.unmodifiable(await _canon(version: version));
  }

  Future<ChapitreBible> getChapitreBible({
    required String code,
    required int chapitre,
    String version = 'lsg1910',
  }) async {
    final livre = await _livreBible(code, version: version);
    if (chapitre < 1 || chapitre > livre.chapitres.length) {
      throw const ApiException('Chapitre introuvable.');
    }
    return livre.chapitre(chapitre);
  }

  Future<List<ResultatRechercheBible>> rechercherBible(
    String terme, {
    String version = 'lsg1910',
  }) async {
    final aiguille = _normaliser(terme.trim());
    if (aiguille.length < 2) {
      throw const ApiException('Recherche : au moins 2 caractères.');
    }
    final resultats = <ResultatRechercheBible>[];
    for (final meta in await _canon(version: version)) {
      final livre = await _livreBible(meta.code, version: version);
      for (var c = 0; c < livre.chapitres.length; c++) {
        final chapitre = livre.chapitres[c];
        for (var v = 0; v < chapitre.length; v++) {
          if (_normaliser(chapitre[v]).contains(aiguille)) {
            resultats.add(ResultatRechercheBible(
              livre: livre.nom,
              code: livre.code,
              chapitre: c + 1,
              verset: v + 1,
              texte: chapitre[v],
            ));
            if (resultats.length >= 50) return resultats;
          }
        }
      }
    }
    return resultats;
  }

  Future<EntreeStrong> getEntreeStrong(String numero) async {
    final maj = numero.trim().toUpperCase();
    if (!RegExp(r'^[GH][0-9]{1,4}$').hasMatch(maj)) {
      throw const ApiException('Numéro Strong invalide.');
    }
    final lexique =
        await _lexiqueStrong(maj.startsWith('H') ? 'hebreu' : 'grec');
    final brut = lexique[maj] as Map<String, dynamic>?;
    if (brut == null) {
      throw const ApiException('Entrée Strong introuvable.');
    }
    return EntreeStrong(
      numero: maj,
      langue: maj.startsWith('H') ? 'hebreu' : 'grec',
      lemma: brut['lemma'] as String,
      translit: (brut['translit'] as String?) ??
          (brut['xlit'] as String?) ??
          '',
      pron: brut['pron'] as String?,
      derivation: brut['derivation'] as String?,
      strongsDef: brut['strongs_def'] as String?,
      kjvDef: brut['kjv_def'] as String?,
    );
  }

  Future<List<EntreeStrong>> rechercherStrong(String terme) async {
    final aiguille = _normaliser(terme.trim());
    if (aiguille.length < 2) {
      throw const ApiException('Recherche : au moins 2 caractères.');
    }
    final resultats = <EntreeStrong>[];
    final numero = terme.trim().toUpperCase();
    if (RegExp(r'^[GH][0-9]{1,4}$').hasMatch(numero)) {
      try {
        resultats.add(await getEntreeStrong(numero));
      } on ApiException {
        // Numéro absent : on continue avec la recherche par mot.
      }
    }
    for (final langue in ['hebreu', 'grec']) {
      final lexique = await _lexiqueStrong(langue);
      for (final entree in lexique.entries) {
        if (resultats.length >= 50) return resultats;
        if (entree.key == numero) continue;
        final brut = entree.value as Map<String, dynamic>;
        final champs = [
          brut['lemma'] as String? ?? '',
          (brut['translit'] as String?) ?? (brut['xlit'] as String?) ?? '',
          brut['strongs_def'] as String? ?? '',
          brut['kjv_def'] as String? ?? '',
        ];
        if (champs.any((c) => _normaliser(c).contains(aiguille))) {
          resultats.add(EntreeStrong(
            numero: entree.key,
            langue: langue,
            lemma: brut['lemma'] as String,
            translit: (brut['translit'] as String?) ??
                (brut['xlit'] as String?) ??
                '',
            pron: brut['pron'] as String?,
            derivation: brut['derivation'] as String?,
            strongsDef: brut['strongs_def'] as String?,
            kjvDef: brut['kjv_def'] as String?,
          ));
        }
      }
    }
    return resultats;
  }

  Future<ArticleDictionnaire> getArticleDictionnaire(
    String titre, {
    String langue = 'fra',
  }) async {
    final aiguille = titre.trim().toLowerCase();
    if (aiguille.isEmpty) {
      throw const ApiException('Titre d’article invalide.');
    }
    final articles = await _dictionnaire(langue: langue);
    for (final article in articles) {
      if (article.titre.toLowerCase() == aiguille) return article;
    }
    throw const ApiException('Article introuvable.');
  }

  Future<List<ArticleDictionnaire>> rechercherDictionnaire(
    String terme, {
    String langue = 'fra',
  }) async {
    final aiguille = _normaliser(terme.trim());
    if (aiguille.length < 2) {
      throw const ApiException('Recherche : au moins 2 caractères.');
    }
    final articles = await _dictionnaire(langue: langue);
    final parTitre = <ArticleDictionnaire>[];
    final parTexte = <ArticleDictionnaire>[];
    for (final article in articles) {
      if (_normaliser(article.titre).contains(aiguille)) {
        parTitre.add(article);
      } else if (_normaliser(article.texte).contains(aiguille)) {
        parTexte.add(article);
      }
    }
    return [...parTitre, ...parTexte].take(50).toList();
  }
}
