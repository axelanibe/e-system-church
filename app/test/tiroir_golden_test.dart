import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/short_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// R1 — garde-fou visuel 360 px (plan de refonte §1.1, lot R1).
/// Tiroir désengorgé à 360 px de large : le tiroir réel, ouvert,
/// compte admin de démo. La référence dorée vit dans
/// `test/goldens/tiroir_360.png` ; la régénérer avec
/// `flutter test --update-goldens` après une retouche visuelle voulue,
/// jamais pour faire passer une régression.
/// Aucun code prod touché par ce lot.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

void main() {
  testWidgets('Tiroir 360 px : rendu de référence, sans débordement',
      (tester) async {
    final api = FauxApiService();
    await tester.runAsync(() => api.login(
          identifiant: DemoAccounts.adminEmail,
          password: DemoAccounts.password,
        ));

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
          ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales()),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            drawer: TiroirCourt(onAller: (_) {}),
            body: const Center(child: Text('Accueil')),
          ),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    // Checklist 360 px du rapport UX : toutes les entrées sont là, y
    // compris la dernière (« À propos »), cas de troncature D10 ;
    // aucune exception (débordement compris) n'est remontée. La
    // ListView du tiroir est paresseuse : on défile jusqu'à la
    // dernière entrée pour la construire ; la référence dorée montre
    // donc le bas du tiroir, là où se joue D10.
    await tester.scrollUntilVisible(
        find.text('À propos de e-System Church'), 200);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('À propos de e-System Church'), findsOneWidget);
    expect(find.text('Réglages'), findsWidgets);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(TiroirCourt),
      matchesGoldenFile('goldens/tiroir_360.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
