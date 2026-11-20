import 'package:esystem_church/models/activites.dart';
import 'package:esystem_church/models/announcement.dart';
import 'package:esystem_church/models/ecole_biblique.dart';
import 'package:esystem_church/models/medias.dart';
import 'package:esystem_church/screens/messagerie_liste_screen.dart';
import 'package:esystem_church/screens/recherche_globale_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/services/recherche_globale.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/utils/format.dart';
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

Future<(AppState, FauxApiService)> _pomper(
  WidgetTester tester,
  Widget ecran,
) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password
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
  return (etat, api);
}

void main() {
  group('normaliserRecherche', () {
    test('minuscules et accents repliés', () {
      expect(normaliserRecherche('Église'), 'eglise');
      expect(normaliserRecherche('Cœur de grâce'), 'coeur de grace');
      expect(normaliserRecherche('Ça va ?'), 'ca va ?');
    });
  });

  group('rechercherContenus', () {
    final annonces = [
      const Announcement(
        id: 'a1',
        title: 'Culte d’action de grâce',
        body: 'Apportez un plat à partager.',
        broadcast: false,
      ),
    ];
    final activites = [
      const Activite(
        id: 'act1',
        titre: 'Sortie jeunesse',
        description: 'Une sortie pour les jeunes.',
        dateHeure: '2027-01-16T09:00',
        lieu: 'Parc',
        responsable: 'Marie',
        statut: 'publié',
      ),
    ];
    final cours = [
      const CoursEcole(
        id: 'c1',
        titre: 'Fondements de la foi',
        description: 'Dieu, Jésus-Christ, et la prière.',
        niveau: 'debutant',
      ),
    ];
    final livres = [
      const Livre(
        id: 'l1',
        titre: 'Le chrétien et la prière',
        auteur: 'Pasteur Emmanuel Aka',
        categorie: 'Prière',
        exemplaires: 2,
      ),
    ];

    ResultatsRecherche chercher(String requete) => rechercherContenus(
          requete: requete,
          annonces: annonces,
          activites: activites,
          cours: cours,
          livres: livres,
        );

    test('requête vide : rien', () {
      expect(chercher('').estVide, isTrue);
      expect(chercher('   ').estVide, isTrue);
    });

    test('un mot, insensible aux accents', () {
      final resultats = chercher('grace');
      expect(resultats.annonces.length, 1);
      expect(resultats.total, 1);
    });

    test('plusieurs mots : tous doivent correspondre', () {
      expect(chercher('jeunesse sortie').activites.length, 1);
      expect(chercher('jeunesse culte').estVide, isTrue);
    });

    test('un mot présent dans deux sources', () {
      final resultats = chercher('priere');
      expect(resultats.cours.length, 1);
      expect(resultats.livres.length, 1);
      expect(resultats.annonces, isEmpty);
      expect(resultats.activites, isEmpty);
    });

    test('aucun résultat', () {
      expect(chercher('zzzz').estVide, isTrue);
    });
  });

  group('RechercheGlobaleScreen', () {
    testWidgets('recherche groupée par source, sans résultat', (
      tester,
    ) async {
      await _pomper(tester, const RechercheGlobaleScreen());
      // Aucune requête : l'aide s'affiche, aucun résultat.
      expect(find.textContaining('Tapez un mot pour chercher'), findsOneWidget);
      expect(find.text('ANNONCES'), findsNothing);
      // Une requête trouve le cours et le groupe Cours.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher dans l’application'),
        'psaumes',
      );
      await tester.pump();
      expect(find.text('Étude des Psaumes'), findsOneWidget);
      expect(find.text('COURS'), findsOneWidget);
      expect(find.text('ANNONCES'), findsNothing);
      // Une autre requête trouve l'activité.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher dans l’application'),
        'jeunesse',
      );
      await tester.pump();
      expect(find.text('Sortie jeunesse EXEMPLE'), findsOneWidget);
      expect(find.text('ACTIVITÉS'), findsOneWidget);
      // Sans résultat : le message le dit.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher dans l’application'),
        'zzzz',
      );
      await tester.pump();
      expect(find.text('Aucun résultat pour « zzzz ».') , findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MessagerieListeScreen, recherche', () {
    testWidgets('le champ filtre les conversations par titre', (
      tester,
    ) async {
      final api = FauxApiService();
      await tester.runAsync(
        () => api.login(
          identifiant: DemoAccounts.adminEmail,
          password: DemoAccounts.password
        ),
      );
      final membres = (await tester.runAsync(
        () => api.getMembers(limit: 100),
      ))!
          .membres;
      await tester.runAsync(
        () => api.creerConversationMessagerie(
          type: 'groupe_eglise',
          title: 'Chorale',
          participantMemberIds: [membres.first.id],
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
          child: const MaterialApp(home: MessagerieListeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Chorale'), findsOneWidget);
      // La recherche ne garde que le groupe Chorale.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher une conversation…'),
        'chorale',
      );
      await tester.pump();
      expect(find.text('Chorale'), findsOneWidget);
      // Sans correspondance : le message le dit.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher une conversation…'),
        'zzzz',
      );
      await tester.pump();
      expect(
        find.text('Aucune conversation trouvée pour « zzzz ».'),
        findsOneWidget,
      );
      expect(find.text('Chorale'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
