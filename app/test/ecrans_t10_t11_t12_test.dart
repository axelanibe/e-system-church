import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/screens/action_sociale_screen.dart';
import 'package:esystem_church/screens/alertes_mere_screen.dart';
import 'package:esystem_church/screens/audit_screen.dart';
import 'package:esystem_church/screens/carte_portefeuille_screen.dart';
import 'package:esystem_church/screens/confiance_screen.dart';
import 'package:esystem_church/screens/consultations_screen.dart';
import 'package:esystem_church/screens/deux_fa_screen.dart';
import 'package:esystem_church/screens/documents_screen.dart';
import 'package:esystem_church/screens/dons_nature_screen.dart';
import 'package:esystem_church/screens/evenements_vie_screen.dart';
import 'package:esystem_church/screens/file_hors_ligne_screen.dart';
import 'package:esystem_church/screens/gouvernance_screen.dart';
import 'package:esystem_church/screens/langue_donnees_screen.dart';
import 'package:esystem_church/screens/listes_configurables_screen.dart';
import 'package:esystem_church/screens/mandats_screen.dart';
import 'package:esystem_church/screens/notifications_screen.dart';
import 'package:esystem_church/screens/patrimoine_screen.dart';
import 'package:esystem_church/screens/promesses_screen.dart';
import 'package:esystem_church/screens/reunions_conseil_screen.dart';
import 'package:esystem_church/screens/sauvegarde_screen.dart';
import 'package:esystem_church/screens/transparence_screen.dart';
import 'package:esystem_church/screens/visiteurs_screen.dart';
import 'package:esystem_church/screens/whatsapp_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Tests d'écran T13 pour les composants nouveaux des tranches T10
/// (gouvernance), T11 (confiance) et T12 (US restantes) : chaque écran
/// s'ouvre, montre son titre et son état vide, ne déborde pas sur un
/// téléphone (390 x 580) et revient en arrière. Aucun appel réseau,
/// aucune donnée inventée : le faux service sert des listes vides et
/// deux cartes EXEMPLE (transparence, portefeuille).
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

/// Ouvre [ecran] depuis un accueil factice, attend son chargement et
/// vérifie qu'aucune exception n'est remontée (débordement compris).
Future<void> _ouvrir(WidgetTester tester, Widget ecran) async {
  final api = FauxApiService();
  await tester.runAsync(() => api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      ));
  tester.view.physicalSize = const Size(390, 580);
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
      // Les fournisseurs sont au-dessus de MaterialApp, comme dans main.dart :
      // une route poussée ne voit pas les fournisseurs placés dans `home`.
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ecran),
                ),
                child: const Text('Ouvrir l’écran'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Ouvrir l’écran'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
}

/// Fait défiler la liste par étapes jusqu'à faire apparaître [cible].
/// La liste est paresseuse : les entrées sous le pli ne sont pas
/// construites tant qu'on n'y a pas défilé. On défile à la main plutôt
/// que scrollUntilVisible, qui exige un unique widget et échoue sur les
/// libellés présents deux fois.
Future<void> _defilerJusqua(WidgetTester tester, Finder cible) async {
  for (var i = 0; i < 10; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(cible, findsWidgets);
}

/// Vérifie le titre, les [attendus] et le retour en arrière. Le titre
/// peut apparaître aussi dans le corps (section) : on le cherche au moins
/// une fois, pas exactement une fois.
Future<void> _testerEcran(
  WidgetTester tester,
  Widget ecran, {
  required String titre,
  List<String> attendus = const [],
  List<String> contenus = const [],
}) async {
  await _ouvrir(tester, ecran);
  expect(find.text(titre), findsWidgets);
  for (final attendu in attendus) {
    await _defilerJusqua(tester, find.text(attendu));
  }
  for (final contenu in contenus) {
    await _defilerJusqua(tester, find.textContaining(contenu));
  }
  expect(find.byType(BackButton), findsOneWidget);
  await tester.tap(find.byType(BackButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Ouvrir l’écran'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  group('T10 gouvernance', () {
    testWidgets('Gouvernance : les 8 entrées du hub', (tester) async {
      await _testerEcran(
        tester,
        const GouvernanceScreen(),
        titre: 'Gouvernance',
        attendus: [
          'Mandats',
          'Réunions et décisions',
          'Documents',
          'Action sociale',
          'Patrimoine',
        ],
      );
    });

    testWidgets('Mandats et nominations : état vide, deux onglets',
        (tester) async {
      await _testerEcran(
        tester,
        const MandatsScreen(),
        titre: 'Mandats et nominations',
        attendus: ['Mandats en cours', 'Nominations', 'Aucun mandat en cours.'],
      );
    });

    testWidgets('Conseil et procès-verbaux : état vide, trois onglets',
        (tester) async {
      await _testerEcran(
        tester,
        const ReunionsConseilScreen(),
        titre: 'Conseil et procès-verbaux',
        attendus: [
          'Réunions',
          'Décisions',
          'Procès-verbaux',
          'Aucune réunion du conseil pour l’instant.',
        ],
      );
    });

    testWidgets('Documents : état vide', (tester) async {
      await _testerEcran(
        tester,
        const DocumentsScreen(),
        titre: 'Documents',
        attendus: ['Aucun document classé pour l’instant.'],
      );
    });

    testWidgets('Action sociale : état vide, deux onglets', (tester) async {
      await _testerEcran(
        tester,
        const ActionSocialeScreen(),
        titre: 'Action sociale',
        attendus: ['Bénéficiaires', 'Aides', 'Aucun bénéficiaire pour l’instant.'],
      );
    });

    testWidgets('Patrimoine : état vide, deux onglets', (tester) async {
      await _testerEcran(
        tester,
        const PatrimoineScreen(),
        titre: 'Patrimoine',
        attendus: ['Biens', 'Maintenance', 'Aucun bien du patrimoine pour l’instant.'],
      );
    });
  });

  group('T11 confiance', () {
    testWidgets('Confiance : les 5 entrées du hub', (tester) async {
      await _testerEcran(
        tester,
        const ConfianceScreen(),
        titre: 'Confiance',
        attendus: [
          'Sauvegardes',
          'File hors ligne',
          'Double authentification',
          'Journal d’audit',
          'Notifications',
        ],
      );
    });

    testWidgets('Sauvegardes : état vide', (tester) async {
      await _testerEcran(
        tester,
        const SauvegardeScreen(),
        titre: 'Sauvegardes',
        attendus: ['Aucune sauvegarde pour le moment.'],
      );
    });

    testWidgets('File hors ligne : état vide', (tester) async {
      await _testerEcran(
        tester,
        const FileHorsLigneScreen(),
        titre: 'File hors ligne',
        attendus: ['Aucune action en attente sur le serveur.'],
      );
    });

    testWidgets('Double authentification : activation proposée',
        (tester) async {
      await _testerEcran(
        tester,
        const DeuxFaScreen(),
        titre: 'Double authentification',
        attendus: ['Activer la double authentification'],
      );
    });

    testWidgets('Journal d’audit : lignes EXEMPLE affichées', (tester) async {
      await _testerEcran(
        tester,
        const AuditScreen(),
        titre: 'Journal d’audit',
        attendus: ['Aucune lecture sensible journalisée.'],
        contenus: ['Admin Grâce Divine'],
      );
    });

    testWidgets('Notifications : état vide', (tester) async {
      await _testerEcran(
        tester,
        const NotificationsScreen(),
        titre: 'Notifications',
        attendus: ['Aucune notification.'],
      );
    });
  });

  group('T12 US restantes', () {
    testWidgets('Promesses de don : état vide', (tester) async {
      await _testerEcran(
        tester,
        const PromessesScreen(),
        titre: 'Promesses de don',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Dons en nature : état vide', (tester) async {
      await _testerEcran(
        tester,
        const DonsNatureScreen(),
        titre: 'Dons en nature',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Visiteurs : état vide', (tester) async {
      await _testerEcran(
        tester,
        const VisiteursScreen(),
        titre: 'Visiteurs',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Événements de vie : état vide', (tester) async {
      await _testerEcran(
        tester,
        const EvenementsVieScreen(),
        titre: 'Événements de vie',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Transparence financière : totaux à zéro', (tester) async {
      await _testerEcran(
        tester,
        const TransparenceScreen(),
        titre: 'Transparence financière',
        contenus: ['Église EXEMPLE'],
      );
    });

    testWidgets('Carte dans le portefeuille : carte EXEMPLE', (tester) async {
      await _testerEcran(
        tester,
        const CartePortefeuilleScreen(),
        titre: 'Carte dans le portefeuille',
        attendus: ['Membre EXEMPLE', 'M-EX-0001', 'Église EXEMPLE'],
      );
    });

    testWidgets('WhatsApp : état vide', (tester) async {
      await _testerEcran(
        tester,
        const WhatsappScreen(),
        titre: 'WhatsApp',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Alertes du réseau : état vide', (tester) async {
      await _testerEcran(
        tester,
        const AlertesMereScreen(),
        titre: 'Alertes du réseau',
        attendus: ['Aucune alerte ouverte.'],
      );
    });

    testWidgets('Listes configurables : état vide', (tester) async {
      await _testerEcran(
        tester,
        const ListesConfigurablesScreen(),
        titre: 'Listes configurables',
        attendus: ['Rien pour le moment.'],
      );
    });

    testWidgets('Consultations sensibles : état vide', (tester) async {
      await _testerEcran(
        tester,
        const ConsultationsScreen(),
        titre: 'Consultations sensibles',
        attendus: ['Aucune consultation.'],
      );
    });

    testWidgets('Langue et données : choix affichés', (tester) async {
      await _testerEcran(
        tester,
        const LangueDonneesScreen(),
        titre: 'Langue et données',
        attendus: ['Français', 'Anglais', 'Mode économique'],
      );
    });
  });
}
