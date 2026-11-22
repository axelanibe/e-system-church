import 'package:esystem_church/screens/annexes_screen.dart';
import 'package:esystem_church/screens/register_fidele_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/utils/validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

/// Tranche 4 (21 nov. 2026) : report des tranches Doublons (#151) et
/// Formulaires P0 (#152) sur l'interface tutelle puis l'espace
/// membres / carte.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

void main() {
  group('Doublon annexes (PR #151, report tutelle)', () {
    testWidgets(
      'État vide : une seule entrée vers les rattachements',
      (tester) async {
        final api = FauxApiService();
        await tester.runAsync(
          () => api.login(
            identifiant: DemoAccounts.adminEmail,
            password: DemoAccounts.password,
          ),
        );
        // Écran haut : l'état vide des annexes est sous l'arbre du
        // réseau, il faut que la ListView le construise.
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
            child: const MaterialApp(home: AnnexesScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        // La liste est vide (FauxApiService.getAnnexes renvoie []) :
        // le message d'état vide s'affiche…
        expect(find.text('Aucune annexe rattachée.'), findsOneWidget);
        // …mais plus le bouton d'état vide vers les rattachements :
        // la carte « Gérer les annexes » contient déjà cette entrée.
        expect(
          find.text('Voir les demandes de rattachement'),
          findsNothing,
        );
        expect(find.text('Demandes de rattachement'), findsOneWidget);
      },
    );
  });

  group('Formulaire fidèle (report espace membres)', () {
    testWidgets(
      'Rejoindre mon église : mention (*) et aide sur le code',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: RegisterFideleScreen()),
        );
        expect(find.text('(*) Champs obligatoires'), findsOneWidget);
        expect(
          find.text('Ex. ESC-F-1234 — code reçu de votre église'),
          findsOneWidget,
        );
      },
    );
  });

  group('Validations partagées (PR #152)', () {
    test('Téléphone CI : 10 chiffres, espaces et +225 acceptés', () {
      expect(validerTelephoneCI('07 07 07 07 07'), isNull);
      expect(validerTelephoneCI('+225 07 07 07 07 07'), isNull);
      expect(validerTelephoneCI('0707070707'), isNull);
      expect(validerTelephoneCI('07 07'), isNotNull);
      expect(validerTelephoneCI(''), 'Entrez un numéro de téléphone.');
      expect(validerTelephoneCI('', obligatoire: false), isNull);
    });

    test('E-mail simple : vide accepté, forme a@b.c exigée', () {
      expect(validerEmailSimple(''), isNull);
      expect(validerEmailSimple('prenom@mail.com'), isNull);
      expect(validerEmailSimple('pas-un-email'), isNotNull);
      expect(validerEmailSimple('a@b'), isNotNull);
    });
  });
}
