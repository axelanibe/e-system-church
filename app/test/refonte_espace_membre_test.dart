import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/bible.dart';
import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/screens/bible_fidele_screen.dart';
import 'package:esystem_church/screens/culte_detail_fidele_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/carte_membre_visuelle.dart';
import 'package:esystem_church/widgets/compte_rebours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Refonte de l'espace membre (maquette validée le 24 novembre 2026) :
/// héros compact en dégradé violet royal, bannière Verset + Prière
/// sans l'emplacement « Le texte s'affichera ici. », tuiles d'actions
/// rapides sur une ligne, sections secondaires en accordéons sous
/// « Mon église », compte à rebours partagé, détail du culte, pass
/// vertical de la carte, Bible avec ses sélecteurs Livre et Chapitre
/// gardés. Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api, {this.eglise});

  final ApiService _api;
  final Church? eglise;

  @override
  ApiService get api => _api;

  @override
  Church? get church => eglise ?? super.church;
}

const _eglisePlateau = Church(
  id: DemoIds.plateau,
  code: 'GD-PLAT',
  name: 'Grâce Divine — Plateau',
  status: 'active',
);

const _culteAvenir = Culte(
  id: 'test-culte-avenir',
  titre: 'Culte EXEMPLE',
  dateHeure: '2027-01-04T09:00',
  lieu: 'Temple EXEMPLE',
  orateur: 'Pasteur EXEMPLE',
);

const _membre = Member(
  id: 'demo-m-001',
  matricule: 'GD-001',
  fullName: 'Awa Koné',
  status: 'actif',
  createdAt: null,
);

/// Bible en mémoire (pas d'asset) : les sélecteurs Livre et Chapitre
/// s'affichent sans charger les fichiers LSG.
class _ApiBibleRefonte extends FauxApiService {
  static const _canon = <LivreBible>[
    LivreBible(code: 'GEN', nom: 'Genèse', testament: 'ancien', chapitres: 50),
    LivreBible(code: 'PSA', nom: 'Psaumes', testament: 'ancien', chapitres: 150),
    LivreBible(code: 'JHN', nom: 'Jean', testament: 'nouveau', chapitres: 21),
  ];

  @override
  Future<List<VersionBible>> getVersionsBible() async => const [
        VersionBible(
            id: 'lsg1910',
            nom: 'Louis Segond 1910',
            langue: 'fr',
            livres: 66,
            versets: 31170),
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
    return ChapitreBible(
      livre: livre.nom,
      code: code,
      chapitre: chapitre,
      chapitres: livre.chapitres,
      versets: [
        for (var n = 1; n <= 3; n++)
          VersetBible(numero: n, texte: 'Verset EXEMPLE $code $chapitre:$n.'),
      ],
    );
  }
}

Future<FauxApiService> _connecter(
  WidgetTester tester, {
  String identifiant = DemoAccounts.membreEmail,
}) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(identifiant: identifiant, password: 'demo1234'),
  );
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return api;
}

Future<void> _pomper(
  WidgetTester tester,
  Widget ecran,
  FauxApiService api, {
  Church? eglise,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(
          value: _EtatFaux(api, eglise: eglise),
        ),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: ecran)),
    ),
  );
  // Pompes manuelles, pas pumpAndSettle : le compte à rebours tourne
  // sur un minuteur périodique.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Démonte l'écran pompé : annule le minuteur périodique du compte
/// à rebours, sinon le test échoue (« Timer is still pending »).
Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

void main() {
  setUp(() => MessagerieLectureService.instance.reinitialiserPourTests());

  group('Bible : sélecteurs Livre et Chapitre gardés', () {
    testWidgets('Livre, Chapitre, recherche et grille présents',
        (tester) async {
      final api = _ApiBibleRefonte();
      await tester.runAsync(
        () => api.login(
            identifiant: DemoAccounts.membreEmail, password: 'demo1234'),
      );
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.themePourFacteur(1.0),
            home: const Scaffold(body: BibleFideleScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('selecteur-livre')), findsOneWidget);
      expect(find.byKey(const Key('selecteur-chapitre')), findsOneWidget);
      expect(find.text('Rechercher dans la Bible'), findsOneWidget);
      expect(find.text('Concordance Strong'), findsOneWidget);
      expect(find.text('Dictionnaire'), findsOneWidget);
      expect(find.text('Verset du jour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compte à rebours partagé', () {
    testWidgets('jours et heures calculés depuis la date réelle',
        (tester) async {
      final date = DateTime.now().add(
        const Duration(days: 2, hours: 3, minutes: 25),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CompteRebours(date: date)),
        ),
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Jours'), findsOneWidget);
      expect(find.text('Heures'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans date : trois tirets', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CompteRebours(date: null)),
        ),
      );
      expect(find.text('--'), findsNWidgets(3));
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Détail du culte', () {
    testWidgets('titre, lieu, orateur, compte à rebours, retour',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CulteDetailFideleScreen(culte: _culteAvenir),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Culte EXEMPLE'), findsOneWidget);
      expect(find.text('Temple EXEMPLE'), findsOneWidget);
      expect(find.text('Pasteur EXEMPLE'), findsOneWidget);
      expect(find.text('Retour au prochain culte'), findsOneWidget);
      expect(find.text('Jours'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Carte : pass vertical', () {
    testWidgets('nom, matricule, QR réel, code de vérification',
        (tester) async {
      final api = FauxApiService();
      await tester.runAsync(
        () => api.login(
            identifiant: DemoAccounts.adminEmail, password: 'demo1234'),
      );
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(
              value: _EtatFaux(api, eglise: _eglisePlateau),
            ),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CarteMembreVisuelle(
                  member: _membre,
                  qrData: 'GD-PLAT:GD-001',
                  vertical: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('GD-001 · Église mère'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('GD-PLAT:GD-001'), findsOneWidget);
      expect(find.text('Église'), findsOneWidget);
      expect(find.text('Grâce Divine — Plateau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Accueil refonte', () {
    testWidgets('héros compact : salutation, nom, matricule, QR, Ma carte',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.textContaining('Bonjour'), findsOneWidget);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('ID · GD-001'), findsOneWidget);
      expect(find.text('Ma carte'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
      expect(find.text('Voir ma carte de membre'), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Prière du jour : phrase d’Axel, mention à confirmer, '
        'jamais l’emplacement vide', (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Verset du jour'), findsOneWidget);
      expect(
        find.text('Un moment calme pour commencer la journée.'),
        findsOneWidget,
      );
      expect(
        find.text('Texte à confirmer par la structure.'),
        findsOneWidget,
      );
      expect(find.text('Le texte s’affichera ici.'), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('actions rapides : libellés sur une ligne, sans description',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      for (final libelle in ['Ma Bible', 'Mes cotisations', 'Mon journal', 'Messagerie']) {
        expect(find.text(libelle), findsOneWidget);
        expect(tester.widget<Text>(find.text(libelle)).maxLines, 1);
      }
      expect(find.text('Ouvrir →'), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Prochain culte : bouton Voir le détail', (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Prochain culte'), findsOneWidget);
      expect(find.text('Voir le détail'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sections secondaires en accordéons sous Mon église',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      // Fenêtre haute : toute la page est construite d'un coup, les
      // sections du bas sont cherchables sans défiler.
      tester.view.physicalSize = const Size(390, 4000);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('MON ÉGLISE'), findsOneWidget);
      expect(find.text('Mes camps'), findsOneWidget);
      expect(find.text('Mes attestations'), findsOneWidget);
      expect(find.text('Annonces de mon église'), findsOneWidget);
      // Repliées par défaut : les états vides restent cachés.
      expect(
        find.textContaining('Aucun camp pour le moment'),
        findsNothing,
      );
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
