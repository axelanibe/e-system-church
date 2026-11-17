// Le serveur refuse limit > 100 sur GET /membres (400 « Paramètres de
// recherche invalides. »). Ces tests prouvent qu'aucun écran n'envoie
// une limite au-delà du plafond, et que les parcours concernés restent
// fonctionnels : liste Messagerie, « Nouvelle conversation », nouveau culte.

import 'dart:async';

import 'package:esystem_church/screens/cultes_screen.dart';
import 'package:esystem_church/screens/messagerie_liste_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

/// État faux minimal : seule l'API est branchée sur le faux service.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

Future<FauxApiService> _pomper(
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
  // Le premier chargement des lectures locales attend jusqu'à 2 s
  // que le stockage réponde (il ne répond jamais en test).
  await tester.pump(const Duration(seconds: 3));
  return api;
}

/// Plafond serveur : GET /membres refuse limit > 100.
void _verifierLimites(FauxApiService api) {
  expect(api.limitesGetMembers, isNotEmpty);
  for (final limite in api.limitesGetMembers) {
    expect(limite, lessThanOrEqualTo(100));
  }
}

void main() {
  group('Limite membres (plafond serveur 100)', () {
    testWidgets('Messagerie : chargement et Nouvelle conversation',
        (tester) async {
      final api = await _pomper(tester, const MessagerieListeScreen());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      _verifierLimites(api);
      // La liste s'affiche sans bannière d'erreur.
      expect(
        find.textContaining('Aucune conversation pour l’instant.'),
        findsOneWidget,
      );
      // « Nouvelle conversation » ouvre le choix des membres.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Choisissez un membre de votre église.'),
        findsOneWidget,
      );
      expect(find.text('Koffi Yao'), findsOneWidget);
      _verifierLimites(api);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Nouveau culte : le dialogue s’ouvre avec les membres',
        (tester) async {
      late BuildContext contexte;
      final api = await _pomper(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) {
              contexte = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Sans attendre : ouvrirNouveauCulte attend la fermeture du
      // dialogue, qui n'arrive qu'après l'ouverture.
      unawaited(ouvrirNouveauCulte(contexte));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Nouveau culte'), findsOneWidget);
      expect(find.text('Conducteur *'), findsOneWidget);
      _verifierLimites(api);
      expect(tester.takeException(), isNull);
    });
  });
}
