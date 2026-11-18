import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/activites.dart';
import 'package:esystem_church/screens/activites_screen.dart';
import 'package:esystem_church/screens/fidele_home_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Activités à venir (V1, migration 039) : section fidèle sur l'accueil
/// (publiées à venir seulement, brouillons jamais visibles) et écran
/// admin (créer, modifier, publier et dépublier, supprimer).
/// Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

const _activitePubliee = Activite(
  id: 'test-act-publiee',
  titre: 'Sortie jeunesse EXEMPLE',
  description: 'Une sortie pour les jeunes de l’église.',
  dateHeure: '2027-01-16T09:00',
  lieu: 'Parc EXEMPLE',
  responsable: 'Responsable EXEMPLE',
  statut: 'publié',
);

const _activiteBrouillon = Activite(
  id: 'test-act-brouillon',
  titre: 'Formation EXEMPLE',
  dateHeure: '2027-01-23T18:30',
  lieu: 'Salle EXEMPLE',
  responsable: 'Formatrice EXEMPLE',
  statut: 'brouillon',
);

/// Activité telle que le serveur la renvoie : la date-heure arrive
/// avec le suffixe Z (TIMESTAMPTZ lue en UTC). L'heure saisie, 14:00
/// heure murale de l'église, doit s'afficher 14:00, pas 09:00 en heure
/// de l'Est (UTC−5).
const _activiteServeurUtc = Activite(
  id: 'test-act-serveur-utc',
  titre: 'Visite EXEMPLE',
  dateHeure: '2026-11-25T14:00:00.000Z',
  lieu: 'Lieu EXEMPLE',
  responsable: 'Responsable EXEMPLE',
  statut: 'publié',
);

Future<FauxApiService> _connecter(
  WidgetTester tester, {
  String identifiant = DemoAccounts.membreEmail,
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
  // Pompes manuelles, pas pumpAndSettle : le compte à rebours de
  // Prochain culte tourne sur un minuteur périodique. La pompe de 3 s
  // laisse aussi finir le chargement différé des non lus de la
  // messagerie (latence de 120 ms), sinon un minuteur reste en
  // attente à la fin du test.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Démonte l'écran pompé : annule le minuteur périodique du compte
/// à rebours, sinon le test échoue (« Timer is still pending »).
Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

void main() {
  setUp(() => MessagerieLectureService.instance.reinitialiserPourTests());

  group('Accueil fidèle : section Activités à venir', () {
    testWidgets('activité publiée affichée, brouillon caché',
        (tester) async {
      final api = await _connecter(tester);
      api.definirActivites([_activitePubliee, _activiteBrouillon]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('ACTIVITÉS À VENIR'), findsOneWidget);
      expect(find.text('Sortie jeunesse EXEMPLE'), findsOneWidget);
      // Le lieu s'affiche dans la même ligne que la date : on cherche
      // la ligne complète plutôt que le lieu seul.
      expect(
        find.textContaining('Parc EXEMPLE'),
        findsOneWidget,
      );
      expect(find.text('Formation EXEMPLE'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets('aucune activité publiée : état vide', (tester) async {
      final api = await _connecter(tester);
      api.definirActivites([_activiteBrouillon]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('ACTIVITÉS À VENIR'), findsOneWidget);
      expect(find.text('Aucune activité à venir'), findsOneWidget);
      expect(find.text('Sortie jeunesse EXEMPLE'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets('heure renvoyée en UTC affichée telle quelle, sans décalage',
        (tester) async {
      final api = await _connecter(tester);
      api.definirActivites([_activiteServeurUtc]);
      await _pomper(tester, const FideleHomeScreen(), api);
      expect(find.text('Visite EXEMPLE'), findsOneWidget);
      expect(find.textContaining('25/11/2026 14:00'), findsOneWidget);
      expect(find.textContaining('25/11/2026 09:00'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Écran admin : liste, publication, suppression', () {
    testWidgets('liste avec pastilles Publié et Brouillon', (tester) async {
      final api = await _connecter(
        tester,
        identifiant: DemoAccounts.adminEmail,
      );
      api.definirActivites([_activitePubliee, _activiteBrouillon]);
      await _pomper(tester, const ActivitesScreen(), api);
      expect(find.text('Activités'), findsOneWidget);
      expect(find.text('Sortie jeunesse EXEMPLE'), findsOneWidget);
      expect(find.text('Formation EXEMPLE'), findsOneWidget);
      expect(find.text('Publié'), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      expect(find.text('Nouvelle activité'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('publier un brouillon : pastille devient Publié',
        (tester) async {
      final api = await _connecter(
        tester,
        identifiant: DemoAccounts.adminEmail,
      );
      api.definirActivites([_activitePubliee, _activiteBrouillon]);
      await _pomper(tester, const ActivitesScreen(), api);
      expect(find.text('Brouillon'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Publier'));
      await tester.tap(find.byTooltip('Publier'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Brouillon'), findsNothing);
      expect(find.text('Publié'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('liste vide : état vide avec bouton de création',
        (tester) async {
      final api = await _connecter(
        tester,
        identifiant: DemoAccounts.adminEmail,
      );
      api.definirActivites([]);
      await _pomper(tester, const ActivitesScreen(), api);
      expect(find.text('Aucune activité planifiée'), findsOneWidget);
      expect(find.text('Nouvelle activité'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('liste admin : heure renvoyée en UTC affichée telle quelle',
        (tester) async {
      final api = await _connecter(
        tester,
        identifiant: DemoAccounts.adminEmail,
      );
      api.definirActivites([_activiteServeurUtc]);
      await _pomper(tester, const ActivitesScreen(), api);
      expect(find.text('Visite EXEMPLE'), findsOneWidget);
      expect(find.textContaining('25/11/2026 14:00'), findsOneWidget);
      expect(find.textContaining('25/11/2026 09:00'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
