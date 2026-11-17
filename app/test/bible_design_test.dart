import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/bible.dart';
import 'package:esystem_church/models/ecole_biblique.dart';
import 'package:esystem_church/screens/bible_fidele_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';

/// API factice en mémoire pour les tests widgets : le canon réel (66
/// livres, noms et nombres de chapitres lus des assets T9) et les
/// versets réels cités dans les assertions ; les autres versets sont
/// marqués EXEMPLE, comme les autres données de test du dépôt.
/// Aucun chargement d'asset en test widget : après le premier
/// testWidgets d'un fichier, rootBundle ne répond plus (gestionnaire
/// 'flutter/assets' effacé), le chargement du canon reste alors en
/// attente et les tests suivants échouent. Les vrais assets sont
/// couverts par bible_hors_ligne_test et ecole_biblique_t9_test.
class _ApiBibleTest extends FauxApiService {
  static const _canonLsg = <LivreBible>[
    LivreBible(code: 'GEN', nom: 'Genèse', testament: 'ancien', chapitres: 50),
    LivreBible(code: 'EXO', nom: 'Exode', testament: 'ancien', chapitres: 40),
    LivreBible(code: 'LEV', nom: 'Lévitique', testament: 'ancien', chapitres: 27),
    LivreBible(code: 'NUM', nom: 'Nombres', testament: 'ancien', chapitres: 36),
    LivreBible(code: 'DEU', nom: 'Deutéronome', testament: 'ancien', chapitres: 34),
    LivreBible(code: 'JOS', nom: 'Josué', testament: 'ancien', chapitres: 24),
    LivreBible(code: 'JDG', nom: 'Juges', testament: 'ancien', chapitres: 21),
    LivreBible(code: 'RUT', nom: 'Ruth', testament: 'ancien', chapitres: 4),
    LivreBible(code: '1SA', nom: 'Premier livre de Samuel', testament: 'ancien', chapitres: 31),
    LivreBible(code: '2SA', nom: 'Deuxième livre de Samuel', testament: 'ancien', chapitres: 24),
    LivreBible(code: '1KI', nom: 'Premier livre des Rois', testament: 'ancien', chapitres: 22),
    LivreBible(code: '2KI', nom: 'Second livre des Rois', testament: 'ancien', chapitres: 25),
    LivreBible(code: '1CH', nom: 'Premier livre des Chroniques', testament: 'ancien', chapitres: 29),
    LivreBible(code: '2CH', nom: 'Second livre des Chroniques', testament: 'ancien', chapitres: 36),
    LivreBible(code: 'EZR', nom: 'Esdras', testament: 'ancien', chapitres: 10),
    LivreBible(code: 'NEH', nom: 'Néhémie', testament: 'ancien', chapitres: 13),
    LivreBible(code: 'EST', nom: 'Esther', testament: 'ancien', chapitres: 10),
    LivreBible(code: 'JOB', nom: 'Job', testament: 'ancien', chapitres: 42),
    LivreBible(code: 'PSA', nom: 'Psaumes', testament: 'ancien', chapitres: 150),
    LivreBible(code: 'PRO', nom: 'Proverbes', testament: 'ancien', chapitres: 31),
    LivreBible(code: 'ECC', nom: 'L\'Ecclésiaste', testament: 'ancien', chapitres: 12),
    LivreBible(code: 'SNG', nom: 'Cantique des Cantiques', testament: 'ancien', chapitres: 8),
    LivreBible(code: 'ISA', nom: 'Ésaïe', testament: 'ancien', chapitres: 66),
    LivreBible(code: 'JER', nom: 'Jérémie', testament: 'ancien', chapitres: 52),
    LivreBible(code: 'LAM', nom: 'Lamentations', testament: 'ancien', chapitres: 5),
    LivreBible(code: 'EZK', nom: 'Ézékiel', testament: 'ancien', chapitres: 48),
    LivreBible(code: 'DAN', nom: 'Daniel', testament: 'ancien', chapitres: 12),
    LivreBible(code: 'HOS', nom: 'Osée', testament: 'ancien', chapitres: 14),
    LivreBible(code: 'JOL', nom: 'Joël', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'AMO', nom: 'Amos', testament: 'ancien', chapitres: 9),
    LivreBible(code: 'OBA', nom: 'Abdias', testament: 'ancien', chapitres: 1),
    LivreBible(code: 'JON', nom: 'Jonas', testament: 'ancien', chapitres: 4),
    LivreBible(code: 'MIC', nom: 'Michée', testament: 'ancien', chapitres: 7),
    LivreBible(code: 'NAM', nom: 'Nahum', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'HAB', nom: 'Habacuc', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'ZEP', nom: 'Sophonie', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'HAG', nom: 'Aggée', testament: 'ancien', chapitres: 2),
    LivreBible(code: 'ZEC', nom: 'Zacharie', testament: 'ancien', chapitres: 14),
    LivreBible(code: 'MAL', nom: 'Malachie', testament: 'ancien', chapitres: 4),
    LivreBible(code: 'MAT', nom: 'Évangile selon Matthieu', testament: 'nouveau', chapitres: 28),
    LivreBible(code: 'MRK', nom: 'Évangile selon Marc', testament: 'nouveau', chapitres: 16),
    LivreBible(code: 'LUK', nom: 'Évangile selon Luc', testament: 'nouveau', chapitres: 24),
    LivreBible(code: 'JHN', nom: 'Évangile selon Jean', testament: 'nouveau', chapitres: 21),
    LivreBible(code: 'ACT', nom: 'Actes des Apôtres', testament: 'nouveau', chapitres: 28),
    LivreBible(code: 'ROM', nom: 'Épître de Paul aux Romains', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '1CO', nom: 'Première épître de Paul aux Corinthiens', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '2CO', nom: 'Seconde épître de Paul aux Corinthiens', testament: 'nouveau', chapitres: 13),
    LivreBible(code: 'GAL', nom: 'Épître de Paul aux Galates', testament: 'nouveau', chapitres: 6),
    LivreBible(code: 'EPH', nom: 'Épître de Paul aux Éphésiens', testament: 'nouveau', chapitres: 6),
    LivreBible(code: 'PHP', nom: 'Épître de Paul aux Philippiens', testament: 'nouveau', chapitres: 4),
    LivreBible(code: 'COL', nom: 'Épître de Paul aux Colossiens', testament: 'nouveau', chapitres: 4),
    LivreBible(code: '1TH', nom: 'Première épître de Paul aux Thessaloniciens', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2TH', nom: 'Second épître de Paul aux Thessaloniciens', testament: 'nouveau', chapitres: 3),
    LivreBible(code: '1TI', nom: 'Première épître de Paul à Timothée', testament: 'nouveau', chapitres: 6),
    LivreBible(code: '2TI', nom: 'Second épître de Paul à Timothée', testament: 'nouveau', chapitres: 4),
    LivreBible(code: 'TIT', nom: 'Épître de Paul à Tite', testament: 'nouveau', chapitres: 3),
    LivreBible(code: 'PHM', nom: 'Épître de Paul à Philémon', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'HEB', nom: 'Épître aux Hébreux', testament: 'nouveau', chapitres: 13),
    LivreBible(code: 'JAS', nom: 'Épître de Jacques', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '1PE', nom: 'Première épître de Pierre', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2PE', nom: 'Seconde épître de Pierre', testament: 'nouveau', chapitres: 3),
    LivreBible(code: '1JN', nom: 'Première épître de Jean', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2JN', nom: 'Seconde épître de Jean', testament: 'nouveau', chapitres: 1),
    LivreBible(code: '3JN', nom: 'Troisième épître de Jean', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'JUD', nom: 'Épître de Jude', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'REV', nom: 'Apocalypse de Jean', testament: 'nouveau', chapitres: 22),
  ];

  static const _canonKjv = <LivreBible>[
    LivreBible(code: 'GEN', nom: 'Genesis', testament: 'ancien', chapitres: 50),
    LivreBible(code: 'EXO', nom: 'Exodus', testament: 'ancien', chapitres: 40),
    LivreBible(code: 'LEV', nom: 'Leviticus', testament: 'ancien', chapitres: 27),
    LivreBible(code: 'NUM', nom: 'Numbers', testament: 'ancien', chapitres: 36),
    LivreBible(code: 'DEU', nom: 'Deuteronomy', testament: 'ancien', chapitres: 34),
    LivreBible(code: 'JOS', nom: 'Joshua', testament: 'ancien', chapitres: 24),
    LivreBible(code: 'JDG', nom: 'Judges', testament: 'ancien', chapitres: 21),
    LivreBible(code: 'RUT', nom: 'Ruth', testament: 'ancien', chapitres: 4),
    LivreBible(code: '1SA', nom: '1 Samuel', testament: 'ancien', chapitres: 31),
    LivreBible(code: '2SA', nom: '2 Samuel', testament: 'ancien', chapitres: 24),
    LivreBible(code: '1KI', nom: '1 Kings', testament: 'ancien', chapitres: 22),
    LivreBible(code: '2KI', nom: '2 Kings', testament: 'ancien', chapitres: 25),
    LivreBible(code: '1CH', nom: '1 Chronicles', testament: 'ancien', chapitres: 29),
    LivreBible(code: '2CH', nom: '2 Chronicles', testament: 'ancien', chapitres: 36),
    LivreBible(code: 'EZR', nom: 'Ezra', testament: 'ancien', chapitres: 10),
    LivreBible(code: 'NEH', nom: 'Nehemiah', testament: 'ancien', chapitres: 13),
    LivreBible(code: 'EST', nom: 'Esther', testament: 'ancien', chapitres: 10),
    LivreBible(code: 'JOB', nom: 'Job', testament: 'ancien', chapitres: 42),
    LivreBible(code: 'PSA', nom: 'Psalms', testament: 'ancien', chapitres: 150),
    LivreBible(code: 'PRO', nom: 'Proverbs', testament: 'ancien', chapitres: 31),
    LivreBible(code: 'ECC', nom: 'Ecclesiastes', testament: 'ancien', chapitres: 12),
    LivreBible(code: 'SNG', nom: 'Song of Solomon', testament: 'ancien', chapitres: 8),
    LivreBible(code: 'ISA', nom: 'Isaiah', testament: 'ancien', chapitres: 66),
    LivreBible(code: 'JER', nom: 'Jeremiah', testament: 'ancien', chapitres: 52),
    LivreBible(code: 'LAM', nom: 'Lamentations', testament: 'ancien', chapitres: 5),
    LivreBible(code: 'EZK', nom: 'Ezekiel', testament: 'ancien', chapitres: 48),
    LivreBible(code: 'DAN', nom: 'Daniel', testament: 'ancien', chapitres: 12),
    LivreBible(code: 'HOS', nom: 'Hosea', testament: 'ancien', chapitres: 14),
    LivreBible(code: 'JOL', nom: 'Joel', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'AMO', nom: 'Amos', testament: 'ancien', chapitres: 9),
    LivreBible(code: 'OBA', nom: 'Obadiah', testament: 'ancien', chapitres: 1),
    LivreBible(code: 'JON', nom: 'Jonah', testament: 'ancien', chapitres: 4),
    LivreBible(code: 'MIC', nom: 'Micah', testament: 'ancien', chapitres: 7),
    LivreBible(code: 'NAM', nom: 'Nahum', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'HAB', nom: 'Habakkuk', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'ZEP', nom: 'Zephaniah', testament: 'ancien', chapitres: 3),
    LivreBible(code: 'HAG', nom: 'Haggai', testament: 'ancien', chapitres: 2),
    LivreBible(code: 'ZEC', nom: 'Zechariah', testament: 'ancien', chapitres: 14),
    LivreBible(code: 'MAL', nom: 'Malachi', testament: 'ancien', chapitres: 4),
    LivreBible(code: 'MAT', nom: 'Matthew', testament: 'nouveau', chapitres: 28),
    LivreBible(code: 'MRK', nom: 'Mark', testament: 'nouveau', chapitres: 16),
    LivreBible(code: 'LUK', nom: 'Luke', testament: 'nouveau', chapitres: 24),
    LivreBible(code: 'JHN', nom: 'John', testament: 'nouveau', chapitres: 21),
    LivreBible(code: 'ACT', nom: 'Acts', testament: 'nouveau', chapitres: 28),
    LivreBible(code: 'ROM', nom: 'Romans', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '1CO', nom: '1 Corinthians', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '2CO', nom: '2 Corinthians', testament: 'nouveau', chapitres: 13),
    LivreBible(code: 'GAL', nom: 'Galatians', testament: 'nouveau', chapitres: 6),
    LivreBible(code: 'EPH', nom: 'Ephesians', testament: 'nouveau', chapitres: 6),
    LivreBible(code: 'PHP', nom: 'Philippians', testament: 'nouveau', chapitres: 4),
    LivreBible(code: 'COL', nom: 'Colossians', testament: 'nouveau', chapitres: 4),
    LivreBible(code: '1TH', nom: '1 Thessalonians', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2TH', nom: '2 Thessalonians', testament: 'nouveau', chapitres: 3),
    LivreBible(code: '1TI', nom: '1 Timothy', testament: 'nouveau', chapitres: 6),
    LivreBible(code: '2TI', nom: '2 Timothy', testament: 'nouveau', chapitres: 4),
    LivreBible(code: 'TIT', nom: 'Titus', testament: 'nouveau', chapitres: 3),
    LivreBible(code: 'PHM', nom: 'Philemon', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'HEB', nom: 'Hebrews', testament: 'nouveau', chapitres: 13),
    LivreBible(code: 'JAS', nom: 'James', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '1PE', nom: '1 Peter', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2PE', nom: '2 Peter', testament: 'nouveau', chapitres: 3),
    LivreBible(code: '1JN', nom: '1 John', testament: 'nouveau', chapitres: 5),
    LivreBible(code: '2JN', nom: '2 John', testament: 'nouveau', chapitres: 1),
    LivreBible(code: '3JN', nom: '3 John', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'JUD', nom: 'Jude', testament: 'nouveau', chapitres: 1),
    LivreBible(code: 'REV', nom: 'Revelation', testament: 'nouveau', chapitres: 22),
  ];

  List<LivreBible> _canon(String version) =>
      version == 'kjv' ? _canonKjv : _canonLsg;

  @override
  Future<List<VersionBible>> getVersionsBible() async => const [
        VersionBible(
            id: 'lsg1910',
            nom: 'Louis Segond 1910',
            langue: 'fr',
            livres: 66,
            versets: 31170),
        VersionBible(
            id: 'kjv',
            nom: 'King James Version',
            langue: 'en',
            livres: 66,
            versets: 31102),
      ];

  @override
  Future<List<LivreBible>> getLivresBible(
          {String version = 'lsg1910'}) async =>
      List.unmodifiable(_canon(version));

  @override
  Future<ChapitreBible> getChapitreBible({
    required String code,
    required int chapitre,
    String version = 'lsg1910',
  }) async {
    final livre = _canon(version).firstWhere((l) => l.code == code);
    final versets = <VersetBible>[];
    if (code == 'GEN' && chapitre == 1 && version == 'lsg1910') {
      versets.add(const VersetBible(
          numero: 1,
          texte: 'Au commencement, Dieu créa les cieux et la terre.'));
    } else if (code == 'GEN' && chapitre == 1 && version == 'kjv') {
      versets.add(const VersetBible(
          numero: 1,
          texte:
              'In the beginning God created the heaven and the earth.'));
    } else if (code == 'PSA' && chapitre == 23) {
      versets.add(const VersetBible(
          numero: 1,
          texte:
              'Cantique de David. L’Éternel est mon berger: je ne manquerai de rien.'));
    } else {
      versets.add(const VersetBible(numero: 1, texte: 'Verset EXEMPLE.'));
    }
    return ChapitreBible(
      livre: livre.nom,
      code: code,
      chapitre: chapitre,
      chapitres: livre.chapitres,
      versets: versets,
    );
  }

  @override
  Future<List<ResultatRechercheBible>> rechercherBible(
    String terme, {
    String version = 'lsg1910',
  }) async {
    if (terme.trim().toLowerCase().contains('berger')) {
      return const [
        ResultatRechercheBible(
          livre: 'Psaumes',
          code: 'PSA',
          chapitre: 23,
          verset: 1,
          texte:
              'Cantique de David. L’Éternel est mon berger: je ne manquerai de rien.',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<List<CoursEcole>> getCoursEcole() async => const [
        CoursEcole(
            id: 'cours-1', titre: 'Fondements de la foi', niveau: 'debutant'),
        CoursEcole(
            id: 'cours-2', titre: 'Vie de prière', niveau: 'intermediaire'),
      ];

  @override
  Future<List<InscriptionEcole>> getInscriptionsEcole({
    String? coursId,
    String? memberId,
  }) async =>
      const [
        InscriptionEcole(
            id: 'insc-1',
            coursId: 'cours-1',
            memberId: 'membre-1',
            statut: 'inscrit'),
      ];

  @override
  Future<ProgressionCours> getProgressionEcole(
      String inscriptionId) async {
    const inscription = InscriptionEcole(
        id: 'insc-1',
        coursId: 'cours-1',
        memberId: 'membre-1',
        statut: 'inscrit');
    return const ProgressionCours(
      inscription: inscription,
      lecons: [
        ProgressionLecon(
            id: 'lecon-1', ordre: 1, titre: 'Leçon EXEMPLE 1', termine: true),
        ProgressionLecon(
            id: 'lecon-2', ordre: 2, titre: 'Leçon EXEMPLE 2', termine: false),
      ],
      terminees: 1,
      total: 2,
      pourcentage: 50,
    );
  }
}

/// État faux minimal : seule l'API est branchée sur le faux service.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

Future<void> _pomper(WidgetTester tester, {double facteur = 1.0}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _EtatFaux(_ApiBibleTest())),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.themePourFacteur(facteur),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(facteur),
          ),
          child: child!,
        ),
        home: const Scaffold(body: BibleFideleScreen()),
      ),
    ),
  );
  await _attendre(tester);
}

/// Pompes bornées : les futurs du faux service se résolvent en
/// microtâches, quelques pompes suffisent.
Future<void> _attendre(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Un verset est rendu en RichText : find.text ne le voit pas.
Finder _verset(String texte) => find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(texte),
    );

/// Choisit un livre dans le sélecteur (testament Ancien par défaut).
Future<void> _choisirLivre(WidgetTester tester, String nom) async {
  await tester.tap(find.byKey(const Key('selecteur-livre')));
  await _attendre(tester);
  await tester.tap(find.text(nom));
  await _attendre(tester);
}

void main() {
  group('Bible, refonte écran 40 : trois cartes, pas de grille', () {
    testWidgets('les trois cartes sont présentes, sans grille ni pastilles',
        (tester) async {
      await _pomper(tester);
      expect(find.text('Bible'), findsOneWidget);
      expect(find.text('École biblique, cours'), findsOneWidget);
      expect(find.text('Ma progression'), findsOneWidget);
      expect(find.text('Ouvrir l’école biblique'), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sélecteurs Livre et Chapitre côte à côte, cellules '
        'uniformes avec nombre de chapitres', (tester) async {
      await _pomper(tester);
      await tester.tap(find.byKey(const Key('selecteur-livre')));
      await _attendre(tester);
      expect(find.text('Genèse'), findsOneWidget);
      expect(find.text('50 chapitres'), findsOneWidget);
      expect(find.text('150 chapitres'), findsNothing);
      await tester.tap(find.text('Nouveau'));
      await _attendre(tester);
      expect(find.text('150 chapitres'), findsNothing);
      expect(find.text('Évangile selon Jean'), findsOneWidget);
      expect(find.text('21 chapitres'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lecture : Genèse 1, texte exact, précédent et suivant',
        (tester) async {
      await _pomper(tester);
      await _choisirLivre(tester, 'Genèse');
      expect(find.text('Genèse — chapitre 1'), findsOneWidget);
      expect(_verset('Au commencement, Dieu créa les cieux'),
          findsOneWidget);
      await tester.tap(find.text('Suivant'));
      await _attendre(tester);
      expect(find.text('Genèse — chapitre 2'), findsOneWidget);
      await tester.tap(find.text('Précédent'));
      await _attendre(tester);
      expect(find.text('Genèse — chapitre 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chapitre : saisie du numéro et regroupement par dizaines',
        (tester) async {
      await _pomper(tester);
      await _choisirLivre(tester, 'Genèse');
      await tester.tap(find.byKey(const Key('selecteur-chapitre')));
      await _attendre(tester);
      expect(find.text('Chapitres 1 à 10'), findsOneWidget);
      final listeChapitres = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListView),
      );
      for (var i = 0;
          i < 6 && find.text('Chapitres 41 à 50').evaluate().isEmpty;
          i++) {
        await tester.drag(listeChapitres, const Offset(0, -500));
        await _attendre(tester);
      }
      expect(find.text('Chapitres 41 à 50'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('numero-chapitre')), '3');
      await tester.tap(find.text('Aller'));
      await _attendre(tester);
      expect(find.text('Genèse — chapitre 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recherche de passages : « berger » trouve Psaumes 23:1, '
        'le résultat ouvre le chapitre', (tester) async {
      await _pomper(tester);
      await tester.enterText(
          find.byKey(const Key('recherche-passages')), 'berger');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _attendre(tester);
      expect(find.text('1 PASSAGE(S) TROUVÉ(S)'), findsOneWidget);
      expect(find.text('Psaumes 23:1'), findsOneWidget);
      await tester.tap(find.text('Psaumes 23:1'));
      await _attendre(tester);
      expect(find.text('Psaumes — chapitre 23'), findsOneWidget);
      expect(_verset('L’Éternel est mon berger'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changer de version garde le livre et le chapitre',
        (tester) async {
      await _pomper(tester);
      await _choisirLivre(tester, 'Genèse');
      expect(find.text('Genèse — chapitre 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('selecteur-version')));
      await _attendre(tester);
      await tester.tap(find.text('King James Version'));
      await _attendre(tester);
      expect(find.text('Genesis — chapitre 1'), findsOneWidget);
      expect(
          _verset('In the beginning God created the heaven and the earth'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('progression partagée : 50 %, 1 leçon sur 2',
        (tester) async {
      await _pomper(tester);
      expect(find.text('50 %'), findsOneWidget);
      expect(find.text('1 leçon(s) terminée(s) sur 2.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Très grand (1,3) : lecture sans débordement',
        (tester) async {
      await _pomper(tester, facteur: 1.3);
      await _choisirLivre(tester, 'Genèse');
      expect(find.text('Genèse — chapitre 1'), findsOneWidget);
      expect(find.text('Bible'), findsOneWidget);
      expect(find.text('Ma progression'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
