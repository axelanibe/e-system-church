import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/messagerie.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/screens/home_screen.dart';
import 'package:esystem_church/screens/messagerie_conversation_screen.dart';
import 'package:esystem_church/screens/messagerie_liste_screen.dart';
import 'package:esystem_church/screens/modules_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/app_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

/// Design couleurs messagerie (16 nov. 2026, référence Projection) :
/// héros fidèle en dégradé violet, carte « Mes annexes » à bordure
/// or, identité propre de la messagerie, entrée visible admin (5e
/// onglet) et fidèle (tuile des actions rapides), badge de non lus
/// des deux côtés. Données EXEMPLE uniquement, jamais réelles.
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

Future<(AppState, FauxApiService)> _pomper(
  WidgetTester tester,
  Widget ecran,
) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  final etat = _EtatFaux(api);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: etat),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(home: ecran),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  return (etat, api);
}

/// Pompe HomeScreen sur un téléphone (390 x 580), comme la bascule.
Future<void> _pomperAccueil(WidgetTester tester) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  tester.view.physicalSize = const Size(390, 580);
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
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  // L'accueil n'attend plus le chargement des lectures de messagerie
  // (carte Messagerie retirée, 21 nov. 2026) : la pastille de l'onglet
  // charge seule, avec un délai de 2 s. On avance l'horloge factice
  // pour que ce chargement se termine, sinon un minuteur reste en
  // attente en fin de test.
  await tester.pump(const Duration(seconds: 3));
  // L'accueil déborde dans l'environnement de test (police de test
  // plus large que la vraie) : on purge ces débordements antérieurs,
  // la vérification finale garde les erreurs de l'interaction.
  while (tester.takeException() != null) {}
}

/// Libellé d'onglet dans la barre du bas.
Finder _onglet(String libelle) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(libelle),
    );

/// Fait défiler la grille Modules jusqu'à faire apparaître [cible].
Future<void> _defilerJusqua(WidgetTester tester, Finder cible) async {
  for (var i = 0; i < 10; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(cible, findsWidgets);
}

/// Sème une conversation directe avec un message, avant d'afficher
/// l'écran (il ne charge qu'une fois, à l'ouverture).
Future<(FauxApiService, ConversationMessagerie)> _semerConversation(
  WidgetTester tester,
) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  late ConversationMessagerie conversation;
  await tester.runAsync(() async {
    conversation = await api.creerConversationMessagerie(
      type: 'directe',
      participantMemberIds: ['demo-m-002'],
    );
    await api.envoyerMessageConversation(
      conversation.id,
      content: 'Shalom, bienvenue !',
    );
  });
  return (api, conversation);
}

/// Pastille or à bordure blanche (badge de non lus, tuile fidèle).
Finder _pastilleOr() => find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      if (decoration is! BoxDecoration) return false;
      if (decoration.color != PaletteMembre.or) return false;
      final border = decoration.border;
      return border is Border && border.top.color == Colors.white;
    });

/// Liseré or 3 px sous la barre de la messagerie.
Finder _lisereOr() => find.byWidgetPredicate(
      (w) => w is Container && w.color == AppTheme.or,
    );

/// Pompe l'accueil fidèle sur un téléphone (390 x 580), dans un
/// Scaffold : FideleHomeContenu est un contenu sans Scaffold ni
/// barre, la coquille fidèle fournit l'écran. Purge les débordements
/// de la police de test, plus large que la vraie, avant les
/// vérifications.
Future<(AppState, FauxApiService)> _pomperFidele(
  WidgetTester tester, {
  FauxApiService? api,
}) async {
  api ??= FauxApiService();
  await tester.runAsync(
    () => api!.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  tester.view.physicalSize = const Size(390, 580);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final etat = _EtatFaux(api);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: etat),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: FideleHomeScreen()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  while (tester.takeException() != null) {}
  return (etat, api);
}

void main() {
  setUp(() => MessagerieLectureService.instance.reinitialiserPourTests());

  group('Barre du bas avec badge', () {
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        label: 'Accueil',
      ),
      NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        label: 'Messagerie',
      ),
    ];

    testWidgets('Le badge affiche le nombre de non lus', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BarreDuBas(
              destinations: destinations,
              badges: const <int?>[null, 3],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sans badge, aucune pastille', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BarreDuBas(
              destinations: destinations,
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Badge), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Entrée visible admin', () {
    testWidgets('Onglet Messagerie : il ouvre la liste', (tester) async {
      await _pomperAccueil(tester);
      await tester.tap(_onglet('Messagerie'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aucun message non lu'), findsOneWidget);
      for (final filtre in ['Toutes', 'Directes', 'Groupes', 'Pastorale']) {
        expect(find.text(filtre), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Grille Modules : plus de carte Messagerie', (tester) async {
      await _pomperAccueil(tester);
      await tester.tap(_onglet('Modules'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _defilerJusqua(tester, find.text('Mes annexes'));
      expect(
        find.descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.text('Messagerie'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Carte Mes annexes, bordure or', () {
    testWidgets('La carte porte la bordure or de la Projection',
        (tester) async {
      await _pomper(tester, const ModulesScreen());
      await _defilerJusqua(tester, find.text('Mes annexes'));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Card &&
              w.shape is RoundedRectangleBorder &&
              (w.shape as RoundedRectangleBorder).side.color ==
                  AppTheme.or,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Identité messagerie, liste', () {
    testWidgets('Bandeau dégradé et filtres, sans conversation',
        (tester) async {
      await _pomper(tester, const MessagerieListeScreen());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aucun message non lu'), findsOneWidget);
      expect(find.text('Nouvelle conversation'), findsWidgets);
      final chip = tester.widget<ChoiceChip>(
        find.byType(ChoiceChip).first,
      );
      expect(chip.selected, isTrue);
      expect(chip.selectedColor, AppTheme.violetProfond);
      expect(_lisereOr(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Conversation : avatar dégradé et pastille de type',
        (tester) async {
      final (api, _) = await _semerConversation(tester);
      final etat = _EtatFaux(api);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: etat),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: const MaterialApp(home: MessagerieListeScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('conversation non lue'), findsOneWidget);
      expect(find.text('Directe'), findsOneWidget);
      expect(find.text('Shalom, bienvenue !'), findsOneWidget);
      // Avatar : dégradé violet profond vers violet vif.
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final decoration = w.decoration;
          if (decoration is! BoxDecoration) return false;
          final gradient = decoration.gradient;
          return gradient is LinearGradient &&
              gradient.colors.contains(AppTheme.violetVif);
        }),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Identité messagerie, conversation', () {
    testWidgets('Liseré or et horodatage or foncé', (tester) async {
      final (api, conversation) = await _semerConversation(tester);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: MaterialApp(
            home: MessagerieConversationScreen(
              conversation: conversation,
              titre: 'Conversation directe',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Shalom, bienvenue !'), findsOneWidget);
      expect(_lisereOr(), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.style?.color == AppTheme.orFonce,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Accueil fidèle', () {
    testWidgets('Héros en dégradé violet royal, textes blancs',
        (tester) async {
      await _pomperFidele(tester);
      expect(find.textContaining('Bonjour'), findsOneWidget);
      // La salutation porte la devise en or, le héros porte le nom
      // en blanc sur le dégradé violet royal. La connexion de ce
      // test est admin, donc sans matricule : on ne l'attend pas ici.
      expect(find.text('Tu es un don de Dieu'), findsWidgets);
      expect(find.text('Admin Grâce Divine'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final decoration = w.decoration;
          if (decoration is! BoxDecoration) return false;
          final gradient = decoration.gradient;
          return gradient is LinearGradient &&
              gradient.colors.contains(PaletteMembre.violetRoyal) &&
              gradient.colors.contains(PaletteMembre.accent);
        }),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tuile Messagerie, sans doublon P1', (tester) async {
      await _pomperFidele(tester);
      expect(find.text('Messagerie'), findsOneWidget);
      expect(find.text('Message à mon église'), findsNothing);
      expect(_pastilleOr(), findsNothing);
      // La tuile ouvre la nouvelle messagerie.
      await tester.ensureVisible(find.text('Messagerie'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Messagerie'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aucun message non lu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tuile Messagerie : pastille de non lus', (tester) async {
      final (api, _) = await _semerConversation(tester);
      await _pomperFidele(tester, api: api);
      expect(find.text('Messagerie'), findsOneWidget);
      expect(_pastilleOr(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
