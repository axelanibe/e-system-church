import 'api_service.dart';

/// Les 66 codes du canon, dans l'ordre (Genèse à Apocalypse).
/// L'index d'un livre dans cette liste est celui de la liste CP
/// des versets du jour.
const codesCanonBible = <String>[
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
  '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
  'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
  'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL', 'MAT',
  'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH', 'PHP',
  'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS', '1PE',
  '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
];

/// Versets du jour (liste CP, 26 références, Proverbes 3:5 inclus) :
/// chaque entrée est (index du livre dans le canon, chapitre, verset).
/// Chaque verset a été vérifié présent dans les données LSG 1910 et
/// KJV embarquées. Le verset tourne dans cette liste selon le jour
/// de l'année, un seul verset par jour calendaire.
const versetsDuJour = <List<int>>[
  [0, 1, 1],
  [18, 23, 1],
  [42, 3, 16],
  [39, 6, 33],
  [49, 4, 13],
  [23, 29, 11],
  [22, 41, 10],
  [44, 8, 28],
  [18, 121, 1],
  [19, 3, 5],
  [39, 11, 28],
  [46, 13, 4],
  [0, 28, 15],
  [42, 1, 1],
  [18, 100, 1],
  [18, 1, 1],
  [44, 10, 9],
  [39, 5, 1],
  [22, 40, 31],
  [45, 5, 8],
  [18, 34, 8],
  [18, 37, 5],
  [39, 7, 7],
  [44, 6, 12],
  [18, 119, 105],
  [40, 4, 4],
];

/// Un verset du jour, avec son texte et sa référence.
class VersetDuJour {
  final String code;
  final int chapitre;
  final int verset;
  final String livre;
  final String texte;

  const VersetDuJour({
    required this.code,
    required this.chapitre,
    required this.verset,
    required this.livre,
    required this.texte,
  });

  /// Référence courte (« Jean 3:16 »), même forme que la recherche.
  String get reference => '$livre $chapitre:$verset';
}

/// Référence du verset du jour pour une date donnée (aujourd'hui
/// par défaut) : jour de l'année modulo 26.
({String code, int chapitre, int verset}) referenceVersetDuJour(
    {DateTime? date}) {
  final maintenant = date ?? DateTime.now();
  final jourAnnee =
      maintenant.difference(DateTime(maintenant.year, 1, 1)).inDays;
  final ref = versetsDuJour[jourAnnee % versetsDuJour.length];
  return (
    code: codesCanonBible[ref[0]],
    chapitre: ref[1],
    verset: ref[2],
  );
}

/// Charge le verset du jour dans la version demandée (LSG 1910 par
/// défaut) : nom du livre depuis le canon, texte depuis le chapitre.
/// Si le verset est absent des données, secours Psaume 23:1,
/// toujours présent dans les deux versions. Le texte n'est jamais
/// inventé : si même le secours est absent, une erreur est levée
/// et l'appelant masque la carte.
Future<VersetDuJour> chargerVersetDuJour(
  ApiService api, {
  String version = 'lsg1910',
  DateTime? date,
}) async {
  final ref = referenceVersetDuJour(date: date);
  final livres = await api.getLivresBible(version: version);
  String nomLivre(String code) {
    for (final livre in livres) {
      if (livre.code == code) return livre.nom;
    }
    return code;
  }

  Future<VersetDuJour?> charger(
      String code, int chapitre, int verset) async {
    final chapitreCharge = await api.getChapitreBible(
        code: code, chapitre: chapitre, version: version);
    for (final v in chapitreCharge.versets) {
      if (v.numero == verset && v.texte.trim().isNotEmpty) {
        return VersetDuJour(
          code: code,
          chapitre: chapitre,
          verset: verset,
          livre: nomLivre(code),
          texte: v.texte.trim(),
        );
      }
    }
    return null;
  }

  final verse = await charger(ref.code, ref.chapitre, ref.verset);
  if (verse != null) return verse;
  final secours = await charger('PSA', 23, 1);
  if (secours != null) return secours;
  throw StateError('Verset du jour introuvable.');
}
