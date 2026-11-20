import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/bible.dart';
import 'package:esystem_church/models/ecole_biblique.dart';
import 'package:esystem_church/screens/bible_fidele_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/services/verset_du_jour.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Bible légère (T3) : verset du jour calendaire, Reprendre ma
/// lecture avec persistance locale, grille des chapitres.
/// API factice en mémoire (canon des 12 livres cités par les 26
/// versets du jour, nombres de chapitres réels, textes réels pour
/// Genèse 1:1 et Psaume 23:1, EXEMPLE ailleurs) : aucun chargement
/// d'asset en test widget, rootBundle ne répond plus après le
/// premier testWidgets d'un fichier.
class _ApiBibleT3 extends FauxApiService {
  static const _canon = <LivreBible>[
    LivreBible(code: 'GEN', nom: 'Genèse', testament: 'ancien', chapitres: 50),
    LivreBible(code: 'PSA', nom: 'Psaumes', testament: 'ancien', chapitres: 150),
    LivreBible(code: 'PRO', nom: 'Proverbes', testament: 'ancien', chapitres: 31),
    LivreBible(code: 'JHN', nom: 'Jean', testament: 'nouveau', chapitres: 21),
    LivreBible(code: 'MAT', nom: 'Matthieu', testament: 'nouveau', chapitres: 28),
    LivreBible(code: 'MRK', nom: 'Marc', testament: 'nouveau', chapitres: 16),
    LivreBible(code: 'PHP', nom: 'Philippiens', testament: 'nouveau', chapitres: 4),
    LivreBible(code: 'JER', nom: 'Jérémie', testament: 'ancien', chapitres: 52),
    LivreBible(code: 'ISA', nom: 'Ésaïe', testament: 'ancien', chapitres: 66),
    LivreBible(code: 'ROM', nom: 'Romains', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '1CO', nom: '1 Corinthiens', testament: 'nouveau', chapitres: 16),
    LivreBible(code: '2CO', nom: '2 Corinthiens', testament: 'nouveau', chapitres: 13),
  ];

  static String nomLivre(String code) =>
      _canon.firstWhere((l) => l.code == code).nom;

  /// Quand vrai, Proverbes 3 n'a que 4 versets : le verset 5 est
  /// absent et le service doit retomber sur Psaume 23:1.
  bool versetManquant = false;

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
      List.unmodifiable(_canon);

  @override
  Future<ChapitreBible> getChapitreBible({
    required String code,
    required int chapitre,
    String version = 'lsg1910',
  }) async {
    final livre = _canon.firstWhere((l) => l.code == code);
    final versets = <VersetBible>[];
    final total = versetManquant && code == 'PRO' && chapitre == 3 ? 4 : 200;
    for (var n = 1; n <= total; n++) {
      var texte = 'Verset EXEMPLE $code $chapitre:$n.';
      if (code == 'GEN' && chapitre == 1 && n == 1) {
        texte = 'Au commencement, Dieu créa les cieux et la terre.';
      } else if (code == 'PSA' && chapitre == 23 && n == 1) {
        texte =
            'Cantique de David. L’Éternel est mon berger: je ne manquerai de rien.';
      }
      versets.add(VersetBible(numero: n, texte: texte));
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
  Future<List<InscriptionEcole>> getInscriptionsEcole({
    String? coursId,
    String? memberId,
  }) async =>
      const [];
}

/// Stockage sécurisé en mémoire, branché sur le canal de
/// flutter_secure_storage : la persistance est testée pour de vrai,
/// sans écrire sur l'appareil.
class _StockageFaux {
  final Map<String, String> valeurs = {};

  Future<Object?> handler(MethodCall appel) async {
    final args = appel.arguments as Map?;
    final cle = args?['key'] as String?;
    switch (appel.method) {
      case 'read':
        return valeurs[cle];
      case 'write':
        valeurs[cle!] = args!['value'] as String;
        return null;
      case 'delete':
        valeurs.remove(cle);
        return null;
      case 'deleteAll':
        valeurs.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(valeurs);
      case 'containsKey':
        return valeurs.containsKey(cle);
      default:
        return null;
    }
  }
}

class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

Future<void> _attendre(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pomperBible(
  WidgetTester tester, {
  PreferencesLocales? preferences,
  _ApiBibleT3? api,
}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(
            value: _EtatFaux(api ?? _ApiBibleT3())),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: preferences ?? PreferencesLocales(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.themePourFacteur(1.0),
        home: const Scaffold(body: BibleFideleScreen()),
      ),
    ),
  );
  await _attendre(tester);
}

Future<_ApiBibleT3> _connecterAccueil(WidgetTester tester) async {
  final api = _ApiBibleT3();
  await tester.runAsync(
    () => api.login(
        identifiant: DemoAccounts.membreEmail,
        password: DemoAccounts.password),
  );
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return api;
}

Future<void> _pomperAccueil(
  WidgetTester tester,
  _ApiBibleT3 api,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(
          value: _EtatFaux(api),
        ),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: FideleHomeScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

/// Un verset est rendu en RichText : find.text ne le voit pas.
Finder _verset(String texte) => find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(texte),
    );

Future<void> _choisirLivre(WidgetTester tester, String nom) async {
  await tester.tap(find.byKey(const Key('selecteur-livre')));
  await _attendre(tester);
  await tester.tap(find.text(nom));
  await _attendre(tester);
}

void main() {
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _StockageFaux stockage;

  setUp(() {
    MessagerieLectureService.instance.reinitialiserPourTests();
    stockage = _StockageFaux();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, stockage.handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  group('Verset du jour : référence calendaire', () {
    test('1er janvier : Genèse 1:1, 10 janvier : Proverbes 3:5', () {
      expect(referenceVersetDuJour(date: DateTime(2026, 1, 1)),
          (code: 'GEN', chapitre: 1, verset: 1));
      expect(referenceVersetDuJour(date: DateTime(2026, 1, 10)),
          (code: 'PRO', chapitre: 3, verset: 5));
    });

    test('la liste tourne : 26 janvier Marc 4:4, 27 janvier Genèse 1:1',
        () {
      expect(referenceVersetDuJour(date: DateTime(2026, 1, 26)),
          (code: 'MRK', chapitre: 4, verset: 4));
      expect(referenceVersetDuJour(date: DateTime(2026, 1, 27)),
          (code: 'GEN', chapitre: 1, verset: 1));
    });

    test('31 décembre : Genèse 1:1 (364 jours, 364 modulo 26 = 0)', () {
      expect(referenceVersetDuJour(date: DateTime(2026, 12, 31)),
          (code: 'GEN', chapitre: 1, verset: 1));
    });
  });

  group('Verset du jour : chargement', () {
    test('1er janvier : texte réel de Genèse 1:1', () async {
      final verset = await chargerVersetDuJour(
        _ApiBibleT3(),
        date: DateTime(2026, 1, 1),
      );
      expect(verset.reference, 'Genèse 1:1');
      expect(verset.texte,
          'Au commencement, Dieu créa les cieux et la terre.');
    });

    test('10 janvier : Proverbes 3:5', () async {
      final verset = await chargerVersetDuJour(
        _ApiBibleT3(),
        date: DateTime(2026, 1, 10),
      );
      expect(verset.reference, 'Proverbes 3:5');
    });

    test('verset absent des données : secours Psaume 23:1', () async {
      final api = _ApiBibleT3()..versetManquant = true;
      final verset = await chargerVersetDuJour(
        api,
        date: DateTime(2026, 1, 10),
      );
      expect(verset.reference, 'Psaumes 23:1');
      expect(verset.texte, contains('L’Éternel est mon berger'));
    });
  });

  group('Position de lecture : persistance locale', () {
    test('definirLecture puis init : la position est relue', () async {
      final prefs = PreferencesLocales();
      await prefs.init();
      await prefs.definirLecture(
          code: 'GEN', chapitre: 3, version: 'lsg1910');
      final relues = PreferencesLocales();
      await relues.init();
      expect(relues.derniereLecture?.code, 'GEN');
      expect(relues.derniereLecture?.chapitre, 3);
      expect(relues.derniereLecture?.version, 'lsg1910');
    });

    test('par défaut : aucune position', () async {
      final prefs = PreferencesLocales();
      await prefs.init();
      expect(prefs.derniereLecture, isNull);
    });

    test('valeur illisible : aucune position', () async {
      stockage.valeurs['lecture_bible'] = 'n’importe quoi';
      final prefs = PreferencesLocales();
      await prefs.init();
      expect(prefs.derniereLecture, isNull);
    });
  });

  group('Écran Bible : Reprendre ma lecture', () {
    testWidgets('sans position : pas de carte Reprendre',
        (tester) async {
      await _pomperBible(tester);
      expect(find.text('Reprendre ma lecture'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('avec position : carte, progression, reprise',
        (tester) async {
      stockage.valeurs['lecture_bible'] = 'GEN|3|lsg1910';
      final prefs = PreferencesLocales();
      await prefs.init();
      await _pomperBible(tester, preferences: prefs);
      expect(find.text('Reprendre ma lecture'), findsOneWidget);
      expect(find.text('Genèse — Chapitre 3 sur 50'), findsOneWidget);
      await tester.tap(find.text('Reprendre'));
      await _attendre(tester);
      expect(find.text('Genèse — chapitre 3'), findsOneWidget);
      expect(_verset('Verset EXEMPLE GEN 3:1.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Écran Bible : verset du jour et grille des chapitres', () {
    testWidgets('la carte Verset du jour montre la référence du jour',
        (tester) async {
      await _pomperBible(tester);
      final ref = referenceVersetDuJour();
      final attendu =
          '${_ApiBibleT3.nomLivre(ref.code)} ${ref.chapitre}:${ref.verset}';
      expect(find.text('Verset du jour'), findsOneWidget);
      expect(find.text(attendu), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la grille des chapitres saute au chapitre touché',
        (tester) async {
      await _pomperBible(tester);
      await _choisirLivre(tester, 'Genèse');
      expect(find.byKey(const Key('grille-chapitre-3')), findsOneWidget);
      expect(find.text('Précédent'), findsOneWidget);
      expect(find.text('Suivant'), findsOneWidget);
      await tester.tap(find.byKey(const Key('grille-chapitre-3')));
      await _attendre(tester);
      expect(find.text('Genèse — chapitre 3'), findsOneWidget);
      expect(_verset('Verset EXEMPLE GEN 3:1.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ouvrir un chapitre mémorise la position',
        (tester) async {
      final prefs = PreferencesLocales();
      await prefs.init();
      await _pomperBible(tester, preferences: prefs);
      await _choisirLivre(tester, 'Genèse');
      await tester.tap(find.byKey(const Key('grille-chapitre-3')));
      await _attendre(tester);
      expect(prefs.derniereLecture?.code, 'GEN');
      expect(prefs.derniereLecture?.chapitre, 3);
      expect(prefs.derniereLecture?.version, 'lsg1910');
      expect(tester.takeException(), isNull);
    });
  });

  group('Accueil fidèle : verset du jour calendaire', () {
    testWidgets('le verset du jour remplace le Psaume 118:24 fixe',
        (tester) async {
      final api = await _connecterAccueil(tester);
      await _pomperAccueil(tester, api);
      final ref = referenceVersetDuJour();
      final attendu =
          '${_ApiBibleT3.nomLivre(ref.code)} ${ref.chapitre}:${ref.verset}';
      expect(find.text('Psaume 118, 24'), findsNothing);
      expect(find.text(attendu), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });
}
