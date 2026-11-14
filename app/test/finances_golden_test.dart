import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/screens/finances_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// R1 — garde-fou visuel 360 px (plan de refonte §1.1, lot R1).
/// Finances à 360 px de large : l'écran réel, compte admin de démo,
/// données du faux service uniquement. La référence dorée vit dans
/// `test/goldens/finances_360.png` ; la régénérer avec
/// `flutter test --update-goldens` après une retouche visuelle voulue,
/// jamais pour faire passer une régression.
/// Aucun code prod touché par ce lot.
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

void main() {
  testWidgets('Finances 360 px : rendu de référence, sans débordement',
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
          home: const FinancesScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Checklist 360 px du rapport UX : l'onglet Contributions est là,
    // le bouton d'ajout ne masque rien en tête de liste, aucune
    // exception (débordement compris) n'est remontée.
    expect(find.text('Contributions'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(FinancesScreen),
      matchesGoldenFile('goldens/finances_360.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
