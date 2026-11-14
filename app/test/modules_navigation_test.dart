import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/screens/modules_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Phase finale : chaque carte Modules ouvre sa vraie fonctionnalité
/// (ou l'explique quand elle n'a pas de cible), et revient en arrière.
/// Aucun appel réseau : le faux service sert des listes vides.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get canReadFinances => true;

  @override
  bool get canManageFinances => true;

  @override
  bool get isAdmin => true;
}

/// Pompe ModulesScreen sur un téléphone (390 x 580) et rend l'état
/// et les onglets demandés par les cartes d'onglet.
Future<({AppState etat, List<int> onglets})> _pomper(
  WidgetTester tester,
) async {
  final api = FauxApiService();
  await tester.runAsync(() => api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      ));
  tester.view.physicalSize = const Size(390, 580);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final etat = _EtatFaux(api);
  final onglets = <int>[];
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: etat),
        ChangeNotifierProvider<PreferencesLocales>.value(
            value: PreferencesLocales()),
      ],
      child: MaterialApp(
        home: ModulesScreen(onAller: onglets.add),
      ),
    ),
  );
  await tester.pump();
  return (etat: etat, onglets: onglets);
}

/// Fait défiler la liste jusqu'à faire apparaître [cible].
Future<void> _defilerJusqua(WidgetTester tester, Finder cible) async {
  for (var i = 0; i < 10; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(cible, findsWidgets);
}

void main() {
  testWidgets('Modules : les 13 cartes s’affichent', (tester) async {
    await _pomper(tester);
    for (final titre in [
      'Accueil admin',
      'Espace membre',
      'Membres et familles',
      'Cultes en direct',
      'Radar pastoral',
      'Finances',
      'Bible et école',
      'Gouvernance',
      'Réglages et confiance',
      'Paiements automatiques',
      'US restantes et dette',
      'Qualité et bascule',
      'Connexion',
    ]) {
      await _defilerJusqua(tester, find.text(titre));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gouvernance : la carte ouvre le hub et revient',
      (tester) async {
    await _pomper(tester);
    await _defilerJusqua(tester, find.text('Gouvernance'));
    await tester.ensureVisible(find.text('Gouvernance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gouvernance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Gouvernance'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Modules de l’église'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Accueil admin : la carte appelle onAller(0)',
      (tester) async {
    final res = await _pomper(tester);
    await tester.tap(find.text('Accueil admin'));
    await tester.pump();
    expect(res.onglets, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Membres et familles : la carte appelle onAller(1)',
      (tester) async {
    final res = await _pomper(tester);
    await _defilerJusqua(tester, find.text('Membres et familles'));
    await tester.ensureVisible(find.text('Membres et familles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membres et familles'));
    await tester.pump();
    expect(res.onglets, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bible et école : message sans navigation', (tester) async {
    await _pomper(tester);
    await _defilerJusqua(tester, find.text('Bible et école'));
    await tester.ensureVisible(find.text('Bible et école'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bible et école'));
    await tester.pump();
    expect(
      find.text(
        'Bible et école biblique : tranche T9 en cours, '
        'pas encore en ligne.',
      ),
      findsOneWidget,
    );
    expect(find.text('Modules de l’église'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Espace membre : la carte entre dans l’aperçu fidèle',
      (tester) async {
    final res = await _pomper(tester);
    expect(res.etat.apercuFidele, isFalse);
    await tester.tap(find.text('Espace membre'));
    await tester.pump();
    expect(res.etat.apercuFidele, isTrue);
    expect(tester.takeException(), isNull);
  });
}
