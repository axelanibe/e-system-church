import 'package:esystem_church/models/chaine_priere.dart';
import 'package:esystem_church/screens/chaine_priere_screen.dart';
import 'package:esystem_church/screens/prieres_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

/// Chaîne de prière (lot 3d, migration 042) : 24 créneaux d'une heure,
/// compteur d'heures couvertes, prise et libération d'un créneau,
/// jours passés en lecture seule, 3e onglet de l'écran Prières.
/// Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

String _jourIso(DateTime jour) =>
    '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';

Future<FauxApiService> _connecter(
  WidgetTester tester, {
  String identifiant = DemoAccounts.membreEmail,
}) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(identifiant: identifiant, password: 'demo1234'),
  );
  // Hauteur 3400 : les 24 créneaux tiennent dans la fenêtre, le
  // ListView paresseux les construit tous — sinon les lignes hors
  // écran n'existent pas pour les finders (7 lignes sur 1200 px,
  // 21 sur 2600 px). Ne pas faire défiler la liste dans ces tests :
  // l'en-tête (compteur) sortirait du cache et serait démonté.
  tester.view.physicalSize = const Size(390, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return api;
}

Future<void> _pomper(
  WidgetTester tester,
  Widget ecran,
  FauxApiService api,
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
      child: MaterialApp(home: Scaffold(body: ecran)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('Modèle : 24 créneaux, compteur, moments', () {
    test('réponse vide : 24 créneaux libres, 0 couverte', () {
      final jour = ChainePriereJour.fromJson({
        'jour': '2026-11-22',
        'aujourd_hui': '2026-11-22',
        'heures_couvertes': 0,
        'mon_member_id': 'demo-m-001',
        'creneaux': [],
      });
      expect(jour.creneaux.length, nbCreneauxPriere);
      expect(jour.heuresCouvertes, 0);
      expect(jour.monCreneau, isNull);
      expect(jour.estPasse, isFalse);
      expect(jour.estAujourdHui, isTrue);
      expect(jour.creneaux.every((c) => c.estLibre), isTrue);
      expect(jour.creneaux.first.heure, 0);
      expect(jour.creneaux.last.heure, 23);
    });

    test('réponse avec 3 créneaux : compteur, prénoms, mon créneau', () {
      final jour = ChainePriereJour.fromJson({
        'jour': '2026-11-22',
        'aujourd_hui': '2026-11-22',
        'heures_couvertes': 3,
        'mon_member_id': 'demo-m-001',
        'creneaux': [
          {'heure': 2, 'member_id': 'demo-m-007', 'prenom': 'Kofi'},
          {'heure': 8, 'member_id': 'demo-m-001', 'prenom': 'Awa'},
          {'heure': 20, 'member_id': 'demo-m-012', 'prenom': 'Yao'},
        ],
      });
      expect(jour.heuresCouvertes, 3);
      expect(heuresCouvertesPriere(jour.creneaux), 3);
      expect(jour.monCreneau?.heure, 8);
      expect(jour.creneaux[2].prenom, 'Kofi');
      expect(jour.creneaux[2].estMien('demo-m-001'), isFalse);
      expect(jour.creneaux[8].estMien('demo-m-001'), isTrue);
      expect(jour.creneaux[20].prenom, 'Yao');
    });

    test('libellés et moments', () {
      expect(libelleCreneauPriere(8), '8 h – 9 h');
      expect(libelleCreneauPriere(23), '23 h – 0 h');
      expect(momentChaine(2), MomentChaine.nuit);
      expect(momentChaine(8), MomentChaine.matin);
      expect(momentChaine(14), MomentChaine.apresMidi);
      expect(momentChaine(20), MomentChaine.soir);
      expect(libelleMomentChaine(MomentChaine.nuit), 'Nuit • 0 h – 6 h');
      expect(libelleDateChaine(DateTime(2026, 11, 22)),
          'dimanche 22 nov. 2026');
      expect(libelleRelatifChaine(
          DateTime(2026, 11, 22), DateTime(2026, 11, 22)), 'Aujourd’hui');
      expect(libelleRelatifChaine(
          DateTime(2026, 11, 23), DateTime(2026, 11, 22)), 'Demain');
      expect(estJourPasseChaine('2026-11-21', '2026-11-22'), isTrue);
      expect(estJourPasseChaine('2026-11-22', '2026-11-22'), isFalse);
      expect(estJourPasseChaine('2026-11-23', '2026-11-22'), isFalse);
    });

    test('filtre par moment', () {
      final creneaux = creneauxPriereDepuisReponse({
        'creneaux': [
          {'heure': 2, 'member_id': 'demo-m-007', 'prenom': 'Kofi'},
          {'heure': 8, 'member_id': 'demo-m-001', 'prenom': 'Awa'},
          {'heure': 20, 'member_id': 'demo-m-012', 'prenom': 'Yao'},
        ],
      });
      expect(creneauxFiltresChaine(creneaux, null).length, 24);
      final matin = creneauxFiltresChaine(creneaux, MomentChaine.matin);
      expect(matin.map((c) => c.heure), [6, 7, 8, 9, 10, 11]);
      expect(initialesDepuisPrenom('Kofi'), 'KO');
      expect(initialesDepuisPrenom(''), '');
    });
  });

  group('Écran : compteur, états, prise et libération', () {
    testWidgets('chaîne vide : compteur 0 / 24 et état vide explicite',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const ChainePriereScreen(), api);
      expect(find.text('0 / 24 heures couvertes'), findsOneWidget);
      expect(
          find.text('Aucune heure couverte pour ce jour.'), findsOneWidget);
      expect(find.text('Aujourd’hui'), findsOneWidget);
      expect(find.text('Libre'), findsNWidgets(24));
      expect(find.text('Prendre'), findsNWidgets(24));
      expect(tester.takeException(), isNull);
    });

    testWidgets('3 créneaux pris : compteur, prénoms, votre créneau',
        (tester) async {
      final api = await _connecter(tester);
      api.definirChainePriere([
        CreneauPriere(heure: 2, memberId: 'demo-m-007', prenom: 'Kofi'),
        CreneauPriere(heure: 8, memberId: 'demo-m-001', prenom: 'Awa'),
        CreneauPriere(heure: 20, memberId: 'demo-m-012', prenom: 'Yao'),
      ]);
      await _pomper(tester, const ChainePriereScreen(), api);
      expect(find.text('3 / 24 heures couvertes'), findsOneWidget);
      expect(find.text('Aucune heure couverte pour ce jour.'), findsNothing);
      expect(find.text('Couvert par Kofi'), findsOneWidget);
      expect(find.text('Couvert par Yao'), findsOneWidget);
      expect(find.text('Votre créneau'), findsOneWidget);
      expect(find.text('Couvert'), findsNWidgets(2));
      expect(find.text('Libérer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filtre Matin : seuls les créneaux du matin',
        (tester) async {
      final api = await _connecter(tester);
      api.definirChainePriere([
        CreneauPriere(heure: 2, memberId: 'demo-m-007', prenom: 'Kofi'),
        CreneauPriere(heure: 8, memberId: 'demo-m-001', prenom: 'Awa'),
        CreneauPriere(heure: 20, memberId: 'demo-m-012', prenom: 'Yao'),
      ]);
      await _pomper(tester, const ChainePriereScreen(), api);
      await tester.tap(find.text('Matin'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('8 h – 9 h'), findsOneWidget);
      expect(find.text('2 h – 3 h'), findsNothing);
      expect(find.text('20 h – 21 h'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prendre un créneau : confirmation puis compteur à 1',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const ChainePriereScreen(), api);
      await tester.tap(find.byKey(const Key('prendre-8')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Prendre ce créneau ?'), findsOneWidget);
      await tester.tap(find.text('Prendre').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1 / 24 heures couvertes'), findsOneWidget);
      expect(find.text('Votre créneau'), findsOneWidget);
      expect(find.text('Créneau pris. Merci !'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('libérer son créneau : confirmation puis compteur à 2',
        (tester) async {
      final api = await _connecter(tester);
      api.definirChainePriere([
        CreneauPriere(heure: 2, memberId: 'demo-m-007', prenom: 'Kofi'),
        CreneauPriere(heure: 8, memberId: 'demo-m-001', prenom: 'Awa'),
        CreneauPriere(heure: 20, memberId: 'demo-m-012', prenom: 'Yao'),
      ]);
      await _pomper(tester, const ChainePriereScreen(), api);
      await tester.tap(find.byKey(const Key('liberer-8')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Libérer votre créneau ?'), findsOneWidget);
      await tester.tap(find.text('Libérer').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 / 24 heures couvertes'), findsOneWidget);
      expect(find.text('Votre créneau'), findsNothing);
      expect(find.text('Créneau libéré.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('jour passé : lecture seule, aucun bouton',
        (tester) async {
      final api = await _connecter(tester);
      final aujourdHui = DateTime.now();
      final hier = aujourdHui.subtract(const Duration(days: 1));
      api.definirChainePriere(
        [CreneauPriere(heure: 8, memberId: 'demo-m-007', prenom: 'Kofi')],
        jour: _jourIso(hier),
        aujourdHui: _jourIso(aujourdHui),
      );
      await _pomper(tester, ChainePriereScreen(jourInitial: hier), api);
      expect(find.text('Jour passé — lecture seule.'), findsOneWidget);
      expect(find.text('Couvert par Kofi'), findsOneWidget);
      expect(find.text('Prendre'), findsNothing);
      expect(find.text('Libérer'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Onglet Prières : chaîne de prière', () {
    testWidgets('3e onglet : la chaîne s’ouvre depuis l’écran Prières',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const PrieresScreen(), api);
      expect(find.text('Demandes de prière'), findsOneWidget);
      // La barre d'onglets défile : le 3e onglet est hors écran à
      // 390 px de large, il faut l'amener en vue avant le tap.
      await tester.ensureVisible(find.text('Chaîne de prière'));
      await tester.tap(find.text('Chaîne de prière'));
      // 3 pompes : animation du changement d'onglet (~300 ms) puis
      // chargement de la chaîne (latence de 120 ms).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('0 / 24 heures couvertes'), findsOneWidget);
      expect(find.text('Aucune heure couverte pour ce jour.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
