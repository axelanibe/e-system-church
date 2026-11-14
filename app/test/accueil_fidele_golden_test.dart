import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// R1 — garde-fou visuel 360 px (plan de refonte §1.1, lot R1).
/// Accueil fidèle à 360 px de large : l'écran réel, compte fidèle de
/// démo, données du faux service uniquement. La référence dorée vit
/// dans `test/goldens/accueil_fidele_360.png` ; la régénérer avec
/// `flutter test --update-goldens` après une retouche visuelle voulue,
/// jamais pour faire passer une régression.
/// Un seul correctif prod, trouvé par ce lot : la rangée
/// « PROCHAIN CULTE » débordait de 42 px à 360 px — libellé en
/// Expanded + ellipse (`fidele_home_screen.dart`), sans changement
/// visuel aux largeurs où elle tenait.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

void main() {
  testWidgets('Accueil fidèle 360 px : rendu de référence, sans débordement',
      (tester) async {
    final api = FauxApiService();
    await tester.runAsync(() => api.login(
          identifiant: DemoAccounts.membreEmail,
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
          home: const Scaffold(body: FideleHomeScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Checklist 360 px du rapport UX : les sections clés sont là,
    // aucune exception (débordement compris) n'est remontée.
    // La ListView est paresseuse : on défile jusqu'à chaque section
    // pour la construire, puis on revient en haut pour la référence
    // dorée.
    Future<void> defilerJusqua(Finder cible) async {
      for (var i = 0; i < 12; i++) {
        if (cible.evaluate().isNotEmpty) return;
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(cible, findsWidgets);
    }

    // SectionTitle met les titres en majuscules : on cherche le
    // texte affiché, pas le titre source.
    await defilerJusqua(find.text('MES ACCÈS'));
    expect(find.text('MES ACCÈS'), findsWidgets);
    await defilerJusqua(find.text('MON PARCOURS'));
    expect(find.text('MON PARCOURS'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(FideleHomeScreen),
      matchesGoldenFile('goldens/accueil_fidele_360.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
