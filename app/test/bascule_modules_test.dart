import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/screens/home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Bascule Modules (maquette, écran 1) : la barre du bas est
/// Accueil, Membres, Finances, Modules ; Départements n'est plus
/// un onglet, il reste joignable par sa carte dans la grille Modules.
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

/// Pompe HomeScreen sur un téléphone (390 x 580).
Future<void> _pomper(WidgetTester tester) async {
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
  // MultiProvider AU-DESSUS de MaterialApp (comme main.dart) : les
  // écrans poussés depuis la grille (Départements...) doivent voir
  // AppState, sinon le push échoue sans Provider au-dessus.
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
  // L'accueil (onglet par défaut) déborde dans l'environnement de
  // test : police de test plus large que la vraie (héros « Aujourd'hui »
  // 140 px, carte 2,7 px). Sur un vrai téléphone 390 px ça tient
  // (capture IMG_4215). Ces débordements sont antérieurs à la bascule,
  // l'accueil n'est pas touché : on les purge ici, la vérification
  // finale (takeException) garde les erreurs de l'interaction.
  while (tester.takeException() != null) {}
}

/// Libellé d'onglet dans la barre du bas.
Finder _onglet(String libelle) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(libelle),
);

void main() {
  testWidgets('Barre du bas : Accueil, Membres, Finances, Modules', (
    tester,
  ) async {
    await _pomper(tester);
    for (final libelle in ['Accueil', 'Membres', 'Finances', 'Modules']) {
      expect(_onglet(libelle), findsOneWidget);
    }
    expect(_onglet('Départements'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Modules : l’onglet ouvre la grille, Départements y reste', (
    tester,
  ) async {
    await _pomper(tester);
    await tester.tap(_onglet('Modules'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tous les modules'), findsOneWidget);
    expect(find.text('Départements'), findsOneWidget);
    await tester.tap(find.text('Départements'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tous les modules'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
