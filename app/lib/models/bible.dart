// Bible Louis Segond 1910 et King James Version (domaine public) :
// canon, chapitres, versets, recherche. Le texte vient du serveur
// (JSON par livre) ou des assets bundlés (mode démo / hors ligne) ;
// il n'est jamais inventé.

/// Une version biblique disponible (LS1910 par défaut, KJV en second).
class VersionBible {
  final String id; // lsg1910 | kjv
  final String nom; // Louis Segond 1910 | King James Version
  final String langue; // fr | en
  final int livres;
  final int versets;

  const VersionBible({
    required this.id,
    required this.nom,
    required this.langue,
    required this.livres,
    required this.versets,
  });

  factory VersionBible.fromJson(Map<String, dynamic> json) => VersionBible(
        id: json['id'] as String,
        nom: json['nom'] as String,
        langue: json['langue'] as String,
        livres: (json['livres'] as num).toInt(),
        versets: (json['versets'] as num).toInt(),
      );
}

/// Un livre du canon (66 livres).
class LivreBible {
  final String code; // GEN, PSA, JHN…
  final String nom; // Genèse, Psaumes, Jean…
  final String testament; // ancien | nouveau
  final int chapitres;

  const LivreBible({
    required this.code,
    required this.nom,
    required this.testament,
    required this.chapitres,
  });

  factory LivreBible.fromJson(Map<String, dynamic> json) => LivreBible(
        code: json['code'] as String,
        nom: json['nom'] as String,
        testament: json['testament'] as String,
        chapitres: (json['chapitres'] as num).toInt(),
      );
}

/// Un verset numéroté.
class VersetBible {
  final int numero;
  final String texte;

  const VersetBible({required this.numero, required this.texte});

  factory VersetBible.fromJson(Map<String, dynamic> json) => VersetBible(
        numero: (json['numero'] as num).toInt(),
        texte: json['texte'] as String,
      );
}

/// Un chapitre : ses versets numérotés.
class ChapitreBible {
  final String livre;
  final String code;
  final int chapitre;
  final int chapitres;
  final List<VersetBible> versets;

  const ChapitreBible({
    required this.livre,
    required this.code,
    required this.chapitre,
    required this.chapitres,
    required this.versets,
  });

  factory ChapitreBible.fromJson(Map<String, dynamic> json) => ChapitreBible(
        livre: json['livre'] as String,
        code: json['code'] as String,
        chapitre: (json['chapitre'] as num).toInt(),
        chapitres: (json['chapitres'] as num).toInt(),
        versets: (json['versets'] as List)
            .map((v) => VersetBible.fromJson(v as Map<String, dynamic>))
            .toList(),
      );
}

/// Un résultat de recherche plein texte (livre, chapitre, verset, texte).
class ResultatRechercheBible {
  final String livre;
  final String code;
  final int chapitre;
  final int verset;
  final String texte;

  const ResultatRechercheBible({
    required this.livre,
    required this.code,
    required this.chapitre,
    required this.verset,
    required this.texte,
  });

  factory ResultatRechercheBible.fromJson(Map<String, dynamic> json) =>
      ResultatRechercheBible(
        livre: json['livre'] as String,
        code: json['code'] as String,
        chapitre: (json['chapitre'] as num).toInt(),
        verset: (json['verset'] as num).toInt(),
        texte: json['texte'] as String,
      );

  /// Référence courte (« Jean 3:16 »).
  String get reference => '$livre $chapitre:$verset';
}

/// Contenu d'un livre bundlé en asset (mode démo / hors ligne) :
/// `{code, nom, testament, chapitres: [[versets du ch. 1], …]}`.
class LivreBibleAsset {
  final String code;
  final String nom;
  final String testament;
  final List<List<String>> chapitres;

  const LivreBibleAsset({
    required this.code,
    required this.nom,
    required this.testament,
    required this.chapitres,
  });

  factory LivreBibleAsset.fromJson(Map<String, dynamic> json) =>
      LivreBibleAsset(
        code: json['code'] as String,
        nom: json['nom'] as String,
        testament: json['testament'] as String,
        chapitres: (json['chapitres'] as List)
            .map((c) => (c as List).map((v) => v as String).toList())
            .toList(),
      );

  LivreBible get meta => LivreBible(
        code: code,
        nom: nom,
        testament: testament,
        chapitres: chapitres.length,
      );

  ChapitreBible chapitre(int numero) => ChapitreBible(
        livre: nom,
        code: code,
        chapitre: numero,
        chapitres: chapitres.length,
        versets: chapitres[numero - 1]
            .asMap()
            .entries
            .map((e) => VersetBible(numero: e.key + 1, texte: e.value))
            .toList(),
      );
}

/// Une entrée de la concordance Strong (lexique hébreu ou grec).
/// La concordance est un lexique consultable : aucun lien mot à mot
/// avec les versets (la LS1910 n'a pas de numéros Strong natifs).
class EntreeStrong {
  final String numero; // G1234 | H1234
  final String langue; // hebreu | grec
  final String lemma;
  final String translit;
  final String? pron;
  final String? derivation;
  final String? strongsDef;
  final String? kjvDef;

  const EntreeStrong({
    required this.numero,
    required this.langue,
    required this.lemma,
    required this.translit,
    this.pron,
    this.derivation,
    this.strongsDef,
    this.kjvDef,
  });

  factory EntreeStrong.fromJson(Map<String, dynamic> json) => EntreeStrong(
        numero: json['numero'] as String,
        langue: json['langue'] as String,
        lemma: json['lemma'] as String,
        translit: (json['translit'] as String?) ?? '',
        pron: json['pron'] as String?,
        derivation: json['derivation'] as String?,
        strongsDef: json['strongs_def'] as String?,
        kjvDef: json['kjv_def'] as String?,
      );

  /// Définition à afficher (définition Strong, sinon définition KJV).
  String get definition => (strongsDef?.trim().isNotEmpty ?? false)
      ? strongsDef!.trim()
      : (kjvDef?.trim().isNotEmpty ?? false)
          ? kjvDef!.trim()
          : 'Aucune définition disponible.';
}

/// Un article du dictionnaire biblique (Aquifer Open Bible Dictionary).
class ArticleDictionnaire {
  final String titre;
  final String texte;

  const ArticleDictionnaire({required this.titre, required this.texte});

  factory ArticleDictionnaire.fromJson(Map<String, dynamic> json) =>
      ArticleDictionnaire(
        titre: json['titre'] as String,
        texte: json['texte'] as String,
      );
}
