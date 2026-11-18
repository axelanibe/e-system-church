import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/screens/cultes_direct_screen.dart';
import 'package:esystem_church/screens/cultes_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Cultes en direct : l'écran d'accueil du module ne rechargeait la
/// liste des cultes qu'à son démarrage. Après la création d'un culte
/// dans l'écran Cultes (ouvert par « Planifier un culte »), le retour
/// gardait « Aucun culte planifié pour l'instant. » alors que l'onglet
/// Cultes listait déjà le culte. Le retour recharge désormais la
/// liste. Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

const _culteCree = Culte(
  id: 'test-culte-cree',
  titre: 'Culte du dimanche EXEMPLE',
  dateHeure: '2026-11-22T14:00',
  lieu: 'Lieu EXEMPLE',
  orateur: 'Orateur EXEMPLE',
);

Future<FauxApiService> _connecter(
  WidgetTester tester, {
  String identifiant = DemoAccounts.adminEmail,
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
  // Pompes manuelles, pas pumpAndSettle : le chargement fait
  // plusieurs appels au faux API (120 ms chacun).
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Démonte l'écran pompé.
Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

void main() {
  group('Cultes en direct : rafraîchissement au retour de l’écran Cultes',
      () {
    testWidgets('culte créé pendant l’absence : visible au retour',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([]);
      await _pomper(tester, const CultesDirectScreen(), api);
      expect(find.text('Aucun culte planifié pour l’instant.'),
          findsOneWidget);
      expect(find.text('Planifier un culte'), findsOneWidget);

      // Ouverture de l'écran Cultes, puis création du culte pendant
      // que l'écran Cultes en direct est en arrière-plan : le
      // dialogue de création n'est pas conduit ici (champs de date
      // et d'heure en lecture seule avec sélecteurs), c'est le
      // rechargement au retour qui est figé.
      await tester.tap(find.text('Planifier un culte'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CultesScreen), findsOneWidget);
      api.definirCultes([_culteCree]);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Aucun culte planifié pour l’instant.'),
          findsNothing);
      expect(find.text('Culte du dimanche EXEMPLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets('culte créé puis supprimé avant le retour : état vide',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([]);
      await _pomper(tester, const CultesDirectScreen(), api);
      expect(find.text('Aucun culte planifié pour l’instant.'),
          findsOneWidget);

      await tester.tap(find.text('Planifier un culte'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CultesScreen), findsOneWidget);
      api.definirCultes([_culteCree]);
      api.definirCultes([]);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Aucun culte planifié pour l’instant.'),
          findsOneWidget);
      expect(find.text('Culte du dimanche EXEMPLE'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });
}
