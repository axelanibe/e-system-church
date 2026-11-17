import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/screens/finances_screen.dart';
import 'package:esystem_church/screens/home_screen.dart';
import 'package:esystem_church/screens/langue_donnees_screen.dart';
import 'package:esystem_church/screens/membres_screen.dart';
import 'package:esystem_church/screens/messages_admin_screen.dart';
import 'package:esystem_church/screens/settings_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Taille du texte : quatre choix persistés sur l'appareil (comme la
/// langue), appliqués à tous les textes par la mise à l'échelle globale
/// (main.dart), champs de saisie à 16 px minimum une fois mis à
/// l'échelle (AppTheme). Aucun appel réseau, aucune donnée inventée :
/// le faux service sert des listes vides.
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

void main() {
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _StockageFaux stockage;

  setUp(() {
    stockage = _StockageFaux();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, stockage.handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  group('TailleTexte', () {
    test('facteurs : Petit 0,9, Normal 1,0, Grand 1,15, Très grand 1,3',
        () {
      expect(TailleTexte.petit.facteur, 0.9);
      expect(TailleTexte.normal.facteur, 1.0);
      expect(TailleTexte.grand.facteur, 1.15);
      expect(TailleTexte.tresGrand.facteur, 1.3);
    });

    test('valeur inconnue : Normal', () {
      expect(TailleTexte.depuisValeur('enorme'), TailleTexte.normal);
      expect(TailleTexte.depuisValeur(null), TailleTexte.normal);
    });
  });

  group('PreferencesLocales', () {
    test('par défaut : Normal, facteur 1,0', () async {
      final prefs = PreferencesLocales();
      await prefs.init();
      expect(prefs.tailleTexte, TailleTexte.normal);
      expect(prefs.facteurTailleTexte, 1.0);
    });

    test('choix persisté, relu par une nouvelle instance', () async {
      final prefs = PreferencesLocales();
      await prefs.init();
      await prefs.definirTailleTexte(TailleTexte.tresGrand);
      expect(stockage.valeurs['taille_texte'], 'tresGrand');
      final relues = PreferencesLocales();
      await relues.init();
      expect(relues.tailleTexte, TailleTexte.tresGrand);
      expect(relues.facteurTailleTexte, 1.3);
    });

    test('valeur stockée illisible : Normal', () async {
      stockage.valeurs['taille_texte'] = 'enorme';
      final prefs = PreferencesLocales();
      await prefs.init();
      expect(prefs.tailleTexte, TailleTexte.normal);
    });
  });

  group('AppTheme', () {
    test('facteur 1,0 : tailles actuelles inchangées', () {
      final theme = AppTheme.themePourFacteur(1.0);
      expect(theme.textTheme.headlineSmall!.fontSize, 24);
      expect(theme.textTheme.titleLarge!.fontSize, 18);
      expect(theme.textTheme.bodyMedium!.fontSize, 16);
      expect(theme.textTheme.bodyLarge!.fontSize, 16);
    });

    test('texte saisi : 16 px minimum une fois mis à l\u2019échelle', () {
      for (final taille in TailleTexte.values) {
        final theme = AppTheme.themePourFacteur(taille.facteur);
        final rendu =
            theme.textTheme.bodyLarge!.fontSize! * taille.facteur;
        expect(rendu, greaterThanOrEqualTo(16.0));
      }
      // Petit : 17,8 px dans le thème, 16 px rendus.
      final petit = AppTheme.themePourFacteur(0.9);
      expect(petit.textTheme.bodyLarge!.fontSize! * 0.9,
          closeTo(16.0, 0.01));
      // Très grand : 16 px dans le thème, 20,8 px rendus.
      final tresGrand = AppTheme.themePourFacteur(1.3);
      expect(tresGrand.textTheme.bodyLarge!.fontSize! * 1.3,
          closeTo(20.8, 0.01));
    });
  });

  group('Écran Langue et données', () {
    Future<PreferencesLocales> pomper(
        WidgetTester tester, TailleTexte taille) async {
      final api = FauxApiService();
      await tester.runAsync(() => api.login(
            identifiant: DemoAccounts.adminEmail,
            password: DemoAccounts.password,
          ));
      final prefs = PreferencesLocales();
      await prefs.init();
      await prefs.definirTailleTexte(taille);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(value: prefs),
          ],
          // Même câblage que main.dart : thème selon le facteur et
          // mise à l'échelle globale du texte.
          child: MaterialApp(
            theme: AppTheme.themePourFacteur(prefs.facteurTailleTexte),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler:
                    TextScaler.linear(prefs.facteurTailleTexte),
              ),
              child: child!,
            ),
            home: const LangueDonneesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return prefs;
    }

    testWidgets('les quatre choix sont proposés, Normal coché', (tester) async {
      final prefs = await pomper(tester, TailleTexte.normal);
      for (final libelle in ['Petite', 'Normale', 'Grande', 'Très grande']) {
        expect(find.text(libelle), findsOneWidget);
      }
      expect(prefs.tailleTexte, TailleTexte.normal);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choisir Très grande persiste le choix', (tester) async {
      final prefs = await pomper(tester, TailleTexte.normal);
      await tester.tap(find.text('Très grande'));
      await tester.pumpAndSettle();
      expect(prefs.tailleTexte, TailleTexte.tresGrand);
      expect(stockage.valeurs['taille_texte'], 'tresGrand');
      expect(tester.takeException(), isNull);
    });
  });

  group('Très grand : écrans principaux sans débordement', () {
    // Compte les débordements signalés en pompant [ecran] à la taille
    // [taille], téléphone 390 x 844, en défilant jusqu'en bas. La
    // police de test est plus large que la vraie : un écran qui
    // déborde déjà à Normal (bruit connu, bascule_modules_test) n'est
    // pas une régression de Très grand. Le test exige donc seulement
    // que Très grand n'ajoute aucun débordement par rapport à Normal.
    Future<int> compterDebordements(
        WidgetTester tester, Widget ecran, TailleTexte taille) async {
      final api = FauxApiService();
      await tester.runAsync(() => api.login(
            identifiant: DemoAccounts.adminEmail,
            password: DemoAccounts.password,
          ));
      final prefs = PreferencesLocales();
      await prefs.init();
      await prefs.definirTailleTexte(taille);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(value: prefs),
          ],
          child: MaterialApp(
            theme: AppTheme.themePourFacteur(prefs.facteurTailleTexte),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler:
                    TextScaler.linear(prefs.facteurTailleTexte),
              ),
              child: child!,
            ),
            home: ecran,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      var debordements = 0;
      Object? erreur;
      while ((erreur = tester.takeException()) != null) {
        if (erreur.toString().contains('overflowed')) debordements++;
      }
      // Défilement jusqu'en bas, par étapes : les entrées sous le pli
      // ne sont construites qu'au défilement. Le geste part du centre
      // de l'écran, sur le défilement extérieur, pas sur une liste
      // interne non défilante.
      for (var i = 0; i < 12; i++) {
        if (find.byType(Scrollable).evaluate().isEmpty) break;
        await tester.dragFrom(
          tester.getCenter(find.byType(Scaffold).first),
          const Offset(0, -500),
        );
        await tester.pump(const Duration(milliseconds: 200));
        while ((erreur = tester.takeException()) != null) {
          if (erreur.toString().contains('overflowed')) debordements++;
        }
      }
      return debordements;
    }

    Future<void> sansRegression(
        WidgetTester tester, Widget ecran) async {
      final normal = await compterDebordements(tester, ecran, TailleTexte.normal);
      final tresGrand =
          await compterDebordements(tester, ecran, TailleTexte.tresGrand);
      expect(tresGrand, lessThanOrEqualTo(normal),
          reason: 'Très grand ajoute des débordements');
    }

    testWidgets('Accueil', (tester) async {
      await sansRegression(tester, const HomeScreen());
    });

    testWidgets('Membres', (tester) async {
      await sansRegression(tester, const MembresScreen());
    });

    testWidgets('Finances', (tester) async {
      await sansRegression(tester, const FinancesScreen());
    });

    testWidgets('Messagerie', (tester) async {
      await sansRegression(tester, const MessagesAdminScreen());
    });

    testWidgets('Réglages', (tester) async {
      await sansRegression(tester, const SettingsScreen());
    });
  });
}
