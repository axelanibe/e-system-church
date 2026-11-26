import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/screens/assistant_fidele_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/screens/fidele_shell.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Tiroir hamburger, messagerie façon Messenger, onglet Clavardage
/// et assistant automatisé de l’espace membre. Données EXEMPLE
/// uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

const _culteAvenir = Culte(
  id: 'test-culte-avenir',
  titre: 'Culte EXEMPLE',
  dateHeure: '2027-01-04T09:00',
  lieu: 'Temple EXEMPLE',
  orateur: 'Pasteur EXEMPLE',
);

Future<FauxApiService> _connecter(WidgetTester tester) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
        identifiant: DemoAccounts.membreEmail, password: 'demo1234'),
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
        ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(home: ecran),
    ),
  );
  // Pompes manuelles, pas pumpAndSettle : le compte à rebours tourne
  // sur un minuteur périodique.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Démonte l’écran pompé : annule le minuteur périodique du compte
/// à rebours, sinon le test échoue (« Timer is still pending »).
Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

Future<void> _ouvrirTiroir(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _dansTiroir(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

void main() {
  setUp(() => MessagerieLectureService.instance.reinitialiserPourTests());

  group('Barre du bas : 4 onglets, Clavardage, pas de Plus', () {
    testWidgets('Accueil, Bible, Carte, Clavardage ; ni Plus ni Messages',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 0), api);
      for (final libelle in ['Accueil', 'Bible', 'Carte', 'Clavardage']) {
        expect(find.text(libelle), findsWidgets);
      }
      expect(find.text('Plus'), findsNothing);
      expect(find.text('Messages'), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l’onglet Clavardage ouvre le fil privé vers l’église',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 3), api);
      expect(find.text('Secrétariat / Église'), findsOneWidget);
      expect(find.text('Groupes & Ministères'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Tiroir hamburger', () {
    testWidgets('en-tête identité réelle et 10 entrées, dans l’ordre',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 0), api);
      await _ouvrirTiroir(tester);
      expect(find.byType(Drawer), findsOneWidget);
      expect(_dansTiroir(find.text('Awa Koné')), findsOneWidget);
      expect(_dansTiroir(find.text('GD-001')), findsOneWidget);
      expect(
        _dansTiroir(find.text('Grâce Divine — Plateau')),
        findsOneWidget,
      );
      const entrees = [
        'Prendre rendez-vous',
        'Mes camps',
        'Mes attestations',
        'Témoignages',
        'Prière du jour',
        'Sujet de prière privé',
        'Transparence financière',
        'Paramètres',
        'À propos',
        'Se déconnecter',
      ];
      for (final entree in entrees) {
        expect(_dansTiroir(find.text(entree)), findsOneWidget);
      }
      // Pas de doublon avec les accès rapides, pas d’entrées qui
      // n’existent pas dans l’espace membre.
      expect(_dansTiroir(find.text('Mon journal')), findsNothing);
      expect(_dansTiroir(find.text('Mes cotisations')), findsNothing);
      expect(_dansTiroir(find.text('Méditation')), findsNothing);
      expect(_dansTiroir(find.text('Bureau')), findsNothing);
      expect(_dansTiroir(find.text('Établissements')), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la recherche filtre les entrées', (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 0), api);
      await _ouvrirTiroir(tester);
      final champ = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Rechercher dans le menu…',
      );
      expect(champ, findsOneWidget);
      await tester.enterText(champ, 'camp');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_dansTiroir(find.text('Mes camps')), findsOneWidget);
      expect(_dansTiroir(find.text('Témoignages')), findsNothing);
      expect(_dansTiroir(find.text('Paramètres')), findsNothing);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mes camps s’ouvre depuis le tiroir', (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 0), api);
      await _ouvrirTiroir(tester);
      await tester.tap(_dansTiroir(find.text('Mes camps')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Aucun camp pour le moment'), findsWidgets);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Messagerie façon Messenger', () {
    testWidgets('bouton en haut à droite de l’accueil, ouvre la liste',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.byTooltip('Messagerie'), findsOneWidget);
      // Plus de tuile Messagerie dans les accès rapides.
      expect(find.text('Messagerie'), findsNothing);
      await tester.tap(find.byTooltip('Messagerie'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Rechercher une conversation…'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Assistant automatisé', () {
    testWidgets('bouton flottant doré sur l’accueil, mention automatique',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      api.definirActivites([]);
      await _pomper(tester, const FideleShell(ongletInitial: 0), api);
      expect(find.byTooltip('Assistant e-System'), findsOneWidget);
      await tester.tap(find.byTooltip('Assistant e-System'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Assistant e-System'), findsWidgets);
      expect(find.text('Réponses automatiques'), findsOneWidget);
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prochain culte réel, carte, question inconnue',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteAvenir]);
      await _pomper(
        tester,
        const AssistantFideleScreen(),
        api,
      );
      expect(find.text('Réponses automatiques'), findsOneWidget);
      await tester.tap(find.text('Quel est le prochain culte ?'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Culte EXEMPLE'), findsOneWidget);
      expect(find.textContaining('Temple EXEMPLE'), findsOneWidget);
      await tester.tap(find.text('Comment avoir ma carte de membre ?'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('s’affiche librement'), findsOneWidget);
      expect(find.textContaining('sans paiement'), findsOneWidget);
      final champ = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Écrire une question…',
      );
      await tester.enterText(champ, 'Quel temps fera-t-il demain ?');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          'Je ne sais pas répondre, écrivez à votre église dans '
          'Clavardage.',
        ),
        findsOneWidget,
      );
      await _demonter(tester);
      expect(tester.takeException(), isNull);
    });

    test('réponses prédéfinies pures : sans culte, sans invention', () {
      expect(
        reponseAssistant('quel est le prochain culte ?'),
        'Aucun culte à venir pour le moment.',
      );
      expect(
        reponseAssistant('quel est le prochain culte ?',
            prochainCulte: _culteAvenir),
        contains('Culte EXEMPLE'),
      );
      expect(
        reponseAssistant('parlez-moi des impôts'),
        'Je ne sais pas répondre, écrivez à votre église dans '
        'Clavardage.',
      );
    });
  });
}
