import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/screens/carte_fidele_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/screens/fidele_shell.dart';
import 'package:esystem_church/screens/rendez_vous_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/en_tete_clair.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Corrections de l'espace fidèle d'après la projection (18 nov. 2026) :
/// bouton « Je serai présent » toujours visible sur Prochain culte,
/// page Carte sans titre avec la note de la projection, page
/// rendez-vous avec le nom du pasteur et « Retour au menu ».
/// La tuile Messagerie des accès rapides n'est pas touchée ici.
/// Données EXEMPLE uniquement, jamais de données réelles.
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

  group('Prochain culte : bouton Je serai présent', () {
    testWidgets('sans culte planifié : bouton visible mais désactivé',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Prochain culte'), findsOneWidget);
      expect(find.text('Je serai présent'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Je serai présent'),
      );
      expect(bouton.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets('avec un culte à venir : bouton actif, appui confirme',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Culte EXEMPLE'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Je serai présent'),
      );
      expect(bouton.onPressed, isNotNull);
      await tester.ensureVisible(find.text('Je serai présent'));
      await tester.tap(find.text('Je serai présent'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Présence confirmée'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Page Carte : visuel seul avec la note', () {
    testWidgets('note de la projection sous le visuel, pas de titre',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const CarteFideleScreen(), api);
      expect(
        find.text(
          'La carte affiche le visuel seul : photo, nom, matricule, '
          'établissement et QR. Les modifications se font depuis le '
          'profil.',
        ),
        findsOneWidget,
      );
      expect(find.text('Carte'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('coquille fidèle : pas d’en-tête sur l’onglet Carte',
        (tester) async {
      final api = await _connecter(tester);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: const MaterialApp(
            home: FideleShell(ongletInitial: 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EnTeteClair), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('coquille fidèle : en-tête présent sur l’onglet Accueil',
        (tester) async {
      final api = await _connecter(tester);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: const MaterialApp(
            home: FideleShell(ongletInitial: 0),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EnTeteClair), findsOneWidget);
      expect(find.text('Accueil'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Prendre rendez-vous : pasteur et retour au menu', () {
    testWidgets('nom du pasteur affiché, lien Retour au menu, retour '
        'fonctionne', (tester) async {
      final api = await _connecter(tester);
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
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RendezVousScreen(),
                      ),
                    ),
                    child: const Text('Ouvrir l’écran'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir l’écran'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Prendre rendez-vous'), findsOneWidget);
      expect(find.text('Retour au menu'), findsOneWidget);
      expect(find.text('Pasteur de mon église'), findsOneWidget);
      expect(find.text('Pasteur Emmanuel Aka'), findsOneWidget);
      expect(
        find.text(
          'Le rendez-vous se fait avec le pasteur de votre église.',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Retour au menu'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ouvrir l’écran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
