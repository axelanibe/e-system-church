import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/screens/cartes_membres_screen.dart';
import 'package:esystem_church/screens/impression_cartes_screen.dart';
import 'package:esystem_church/screens/member_detail_screen.dart';
import 'package:esystem_church/screens/modules_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Tests de la tranche « carte modèle CP + espace cartes impression » :
/// la carte suit le modèle CONNEXION PROPHÉTIQUE (nom blanc 20 px,
/// matricule en or avec « Matricule : », établissement, QR 180 dans
/// un encadré blanc), l'espace cartes liste les cartes (admin
/// seulement) et la vue d'impression les montre seules. Chaque écran
/// s'ouvre, ne déborde pas sur un téléphone (390 x 580) et revient
/// en arrière. Aucun appel réseau : le faux service sert deux
/// membres (Awa Koné GD-001, Koffi Yao GD-002).
class _EtatFaux extends AppState {
  _EtatFaux(this._api, {this.admin = true});

  final ApiService _api;
  final bool admin;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => admin;
}

Future<void> _ouvrir(WidgetTester tester, Widget ecran,
    {bool admin = true}) async {
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
        ChangeNotifierProvider<AppState>.value(
            value: _EtatFaux(api, admin: admin)),
        ChangeNotifierProvider<PreferencesLocales>.value(
            value: PreferencesLocales()),
      ],
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

const _membre = Member(
  id: 'demo-m-001',
  matricule: 'GD-001',
  fullName: 'Awa Koné',
  status: 'actif',
  createdAt: null,
);

void main() {
  group('Carte modèle CP', () {
    testWidgets('nom, matricule en or avec préfixe, QR, sans répétition',
        (tester) async {
      await _ouvrir(
        tester,
        const MemberDetailScreen(
          member: _membre,
          lectureSeule: true,
          carteSeule: true,
        ),
      );
      expect(find.text('CARTE DE MEMBRE'), findsOneWidget);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('Matricule : GD-001'), findsOneWidget);
      // Le matricule nu ne se répète plus sous le QR (modèle CP).
      expect(find.text('GD-001'), findsNothing);
      expect(find.text('e-System Church'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Espace cartes', () {
    testWidgets('admin : liste les cartes, tout imprimer, retour',
        (tester) async {
      await _ouvrir(tester, const CartesMembresScreen());
      expect(find.text('Cartes des membres'), findsOneWidget);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('Koffi Yao'), findsOneWidget);
      expect(find.text('Matricule : GD-001'), findsOneWidget);
      expect(find.text('Tout imprimer'), findsOneWidget);
      expect(find.byIcon(Icons.print_outlined), findsWidgets);
      await tester.pageBack();
      await tester.pump();
      expect(find.text('Ouvrir l’écran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('non admin : message réservé, pas de liste',
        (tester) async {
      await _ouvrir(tester, const CartesMembresScreen(), admin: false);
      expect(find.text('Réservé à l’administrateur de l’église.'),
          findsOneWidget);
      expect(find.text('Awa Koné'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Modules : entrée Cartes de membre', (tester) async {
      await _ouvrir(tester, const ModulesScreen());
      expect(find.text('Cartes de membre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Impression des cartes', () {
    testWidgets('vue d’impression : carte seule, bouton Imprimer',
        (tester) async {
      await _ouvrir(
        tester,
        const ImpressionCartesScreen(membres: [_membre]),
      );
      expect(find.text('Imprimer une carte'), findsOneWidget);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('Matricule : GD-001'), findsOneWidget);
      expect(find.text('Imprimer'), findsOneWidget);
      expect(
        find.textContaining('Graphiques d’arrière-plan'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pump();
      expect(find.text('Ouvrir l’écran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
