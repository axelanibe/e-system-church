import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/screens/cultes_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Cultes : heure murale saisie par l'admin, stockée telle quelle en
/// UTC côté serveur (TIMESTAMPTZ, migration 001, même chemin que les
/// activités à venir). Données EXEMPLE uniquement, jamais de données
/// réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

/// Culte tel que le serveur le renvoie : la date-heure arrive avec le
/// suffixe Z (TIMESTAMPTZ lue en UTC). L'heure saisie, 14:00 heure
/// murale de l'église, doit s'afficher 14:00, pas 09:00 en heure
/// de l'Est (UTC−5).
const _culteServeurUtc = Culte(
  id: 'test-culte-serveur-utc',
  titre: 'Culte du dimanche EXEMPLE',
  dateHeure: '2026-11-25T14:00:00.000Z',
  lieu: 'Lieu EXEMPLE',
  orateur: 'Orateur EXEMPLE',
);

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
  // Pompes manuelles, pas pumpAndSettle : le compte à rebours de
  // Prochain culte tourne sur un minuteur périodique. La pompe de 3 s
  // laisse aussi finir le chargement différé des non lus de la
  // messagerie (latence de 120 ms), sinon un minuteur reste en
  // attente à la fin du test.
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

  group('Accueil fidèle : carte Prochain culte', () {
    testWidgets('heure renvoyée en UTC affichée telle quelle, sans décalage',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteServeurUtc]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Prochain culte'), findsOneWidget);
      expect(find.text('Culte du dimanche EXEMPLE'), findsOneWidget);
      expect(find.textContaining('25/11/2026 14:00'), findsOneWidget);
      expect(find.textContaining('25/11/2026 09:00'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Écran admin : liste des cultes', () {
    testWidgets('heure renvoyée en UTC affichée telle quelle, sans décalage',
        (tester) async {
      final api = await _connecter(
        tester,
        identifiant: DemoAccounts.adminEmail,
      );
      api.definirCultes([_culteServeurUtc]);
      await _pomper(tester, const CultesScreen(), api);
      expect(find.text('Cultes'), findsWidgets);
      expect(find.text('Culte du dimanche EXEMPLE'), findsOneWidget);
      expect(find.textContaining('25/11/2026 14:00'), findsOneWidget);
      expect(find.textContaining('25/11/2026 09:00'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });
}
