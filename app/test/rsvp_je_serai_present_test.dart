import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/activites.dart';
import 'package:esystem_church/models/cultes.dart';
import 'package:esystem_church/models/rsvp.dart';
import 'package:esystem_church/screens/activites_screen.dart';
import 'package:esystem_church/screens/presences_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Vues admin des confirmations « Je serai présent » (lot 3b,
/// migration 040) : section Confirmations de l'écran Présences
/// (par culte) et dialogue Confirmations de l'écran Activités.
/// Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

const _culteRsvp = Culte(
  id: 'test-culte-rsvp',
  titre: 'Culte RSVP EXEMPLE',
  dateHeure: '2027-01-04T09:00',
  lieu: 'Temple EXEMPLE',
);

const _activiteRsvp = Activite(
  id: 'test-act-rsvp',
  titre: 'Sortie RSVP EXEMPLE',
  dateHeure: '2027-01-16T09:00',
  lieu: 'Parc EXEMPLE',
  statut: 'publié',
);

const _confirmes = RsvpListe(
  total: 2,
  confirmes: [
    RsvpConfirmation(
      memberId: 'test-membre-a',
      membreNom: 'Membre RSVP A',
      membreMatricule: 'M-RSVP-A01',
      createdAt: null,
    ),
    RsvpConfirmation(
      memberId: 'test-membre-b',
      membreNom: 'Membre RSVP B',
      membreMatricule: 'M-RSVP-B01',
      createdAt: null,
    ),
  ],
);

Future<FauxApiService> _connecter(
  WidgetTester tester, {
  String identifiant = DemoAccounts.adminEmail,
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
  FauxApiService api,
) async {
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
      child: MaterialApp(home: Scaffold(body: ecran)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => MessagerieLectureService.instance.reinitialiserPourTests());

  group('Écran Présences : section Confirmations par culte', () {
    testWidgets('culte choisi : compteur et noms des confirmés',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteRsvp]);
      api.definirRsvpCulte(_culteRsvp.id, _confirmes);
      await _pomper(tester, const PresencesScreen(), api);
      expect(find.text('Présences'), findsOneWidget);
      // Sans culte choisi, pas de section Confirmations.
      expect(
        find.text('Confirmations « Je serai présent »'),
        findsNothing,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.textContaining('Culte RSVP EXEMPLE'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Confirmations « Je serai présent »'),
        findsOneWidget,
      );
      expect(find.text('2 membres confirmés'), findsOneWidget);
      await tester.tap(find.text('Confirmations « Je serai présent »'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Membre RSVP A'), findsOneWidget);
      expect(find.text('M-RSVP-A01'), findsOneWidget);
      expect(find.text('Membre RSVP B'), findsOneWidget);
      expect(find.text('M-RSVP-B01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('culte sans confirmation : état vide explicite',
        (tester) async {
      final api = await _connecter(tester);
      api.definirCultes([_culteRsvp]);
      await _pomper(tester, const PresencesScreen(), api);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.textContaining('Culte RSVP EXEMPLE'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Aucune confirmation pour ce culte'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Écran Activités : dialogue Confirmations', () {
    testWidgets('bouton Confirmations : compteur et noms des confirmés',
        (tester) async {
      final api = await _connecter(tester);
      api.definirActivites([_activiteRsvp]);
      api.definirRsvpActivite(_activiteRsvp.id, _confirmes);
      await _pomper(tester, const ActivitesScreen(), api);
      expect(find.text('Sortie RSVP EXEMPLE'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Confirmations « Je serai présent »'),
      );
      await tester.tap(find.text('Confirmations « Je serai présent »'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Confirmations — Sortie RSVP EXEMPLE'),
        findsOneWidget,
      );
      expect(find.text('2 membres confirmés :'), findsOneWidget);
      expect(find.text('Membre RSVP A'), findsOneWidget);
      expect(find.text('M-RSVP-A01'), findsOneWidget);
      expect(find.text('Membre RSVP B'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pump(const Duration(milliseconds: 500));
      // La sortie du dialogue prend plus de 500 ms en temps simulé.
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Confirmations — Sortie RSVP EXEMPLE'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('activité sans confirmation : état vide explicite',
        (tester) async {
      final api = await _connecter(tester);
      api.definirActivites([_activiteRsvp]);
      await _pomper(tester, const ActivitesScreen(), api);
      await tester.ensureVisible(
        find.text('Confirmations « Je serai présent »'),
      );
      await tester.tap(find.text('Confirmations « Je serai présent »'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Aucune confirmation pour le moment.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
