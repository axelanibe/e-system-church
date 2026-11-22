import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/temoignage.dart';
import 'package:esystem_church/screens/creation_temoignage_screen.dart';
import 'package:esystem_church/screens/lecteur_temoignage_screen.dart';
import 'package:esystem_church/screens/temoignages_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Témoignages (lot 3c, migration 041) : modèle, page (fil approuvé,
/// mes témoignages avec statut, file de modération), compositeur et
/// lecteur texte. Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

const _approuve = Temoignage(
  id: 'test-tem-approuve',
  auteurNom: 'Marie EXEMPLE',
  texte: 'Le Seigneur m’a relevé EXEMPLE.',
  typeMedia: 'texte',
  statut: 'approuve',
  creeLe: null,
);

const _enAttente = Temoignage(
  id: 'test-tem-attente',
  auteurNom: 'Jean EXEMPLE',
  texte: 'Je témoigne de sa fidélité EXEMPLE.',
  typeMedia: 'texte',
  statut: 'en_attente',
  creeLe: null,
);

const _rejete = Temoignage(
  id: 'test-tem-rejete',
  auteurNom: 'Paul EXEMPLE',
  texte: 'Témoignage refusé EXEMPLE.',
  typeMedia: 'texte',
  statut: 'rejete',
  creeLe: null,
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
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
}

void main() {
  group('Modèle Temoignage', () {
    test('fromJson lit les champs du serveur', () {
      final t = Temoignage.fromJson({
        'id': 't1',
        'auteur_nom': 'Marie EXEMPLE',
        'url_media': '/temoignages/t1/media',
        'texte': 'Merci Seigneur EXEMPLE.',
        'type_media': 'photo',
        'statut': 'approuve',
        'cree_le': '2026-11-22T10:00:00.000Z',
      });
      expect(t.id, 't1');
      expect(t.auteurNom, 'Marie EXEMPLE');
      expect(t.urlMedia, '/temoignages/t1/media');
      expect(t.estPhoto, isTrue);
      expect(t.approuve, isTrue);
      expect(t.enAttente, isFalse);
      expect(t.rejete, isFalse);
      expect(t.creeLe, isNotNull);
    });

    test('fromJson : valeurs par défaut (texte, en attente)', () {
      final t = Temoignage.fromJson({'id': 't2'});
      expect(t.typeMedia, 'texte');
      expect(t.estTexte, isTrue);
      expect(t.statut, 'en_attente');
      expect(t.enAttente, isTrue);
      expect(t.auteurNom, isEmpty);
      expect(t.urlMedia, isNull);
    });

    test('libelleStatutTemoignage couvre les trois statuts', () {
      expect(libelleStatutTemoignage('en_attente'), 'En attente');
      expect(libelleStatutTemoignage('approuve'), 'Approuvé');
      expect(libelleStatutTemoignage('rejete'), 'Rejeté');
      expect(libelleStatutTemoignage('inconnu'), 'En attente');
    });

    test('TemoignagesPageData.fromJson sépare les trois listes', () {
      final data = TemoignagesPageData.fromJson({
        'temoignages': [
          {'id': 'a', 'statut': 'approuve'},
        ],
        'mes_temoignages': [
          {'id': 'a', 'statut': 'approuve'},
          {'id': 'b', 'statut': 'en_attente'},
        ],
        'moderation': [
          {'id': 'b', 'statut': 'en_attente'},
        ],
      });
      expect(data.fil.length, 1);
      expect(data.miens.length, 2);
      expect(data.moderation.length, 1);
    });

    test('limites du compositeur (modèle CP)', () {
      expect(tailleMaxPhotoTemoignage, 5 * 1024 * 1024);
      expect(tailleMaxVideoTemoignage, 25 * 1024 * 1024);
      expect(tailleMaxAudioTemoignage, 10 * 1024 * 1024);
      expect(dureeMaxVideoTemoignage, const Duration(seconds: 60));
      expect(dureeMaxAudioTemoignage, const Duration(minutes: 5));
      expect(longueurMaxTexteTemoignage, 2000);
    });
  });

  group('Page Témoignages', () {
    testWidgets('aucun témoignage : état vide et bouton de publication',
        (tester) async {
      final api = await _connecter(tester);
      api.definirTemoignages([]);
      await _pomper(tester, const TemoignagesScreen(), api);
      expect(find.text('Publier un témoignage'), findsOneWidget);
      expect(
        find.text('Aucun témoignage approuvé pour le moment.'),
        findsOneWidget,
      );
      expect(find.text('Mes témoignages'), findsNothing);
      expect(find.textContaining('À modérer'), findsNothing);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets(
        'fil approuvé, mes témoignages avec statut, file de modération',
        (tester) async {
      final api = await _connecter(tester);
      api.definirTemoignages([_approuve, _enAttente, _rejete]);
      await _pomper(tester, const TemoignagesScreen(), api);
      // Fil : l'approuvé seulement.
      expect(find.text('Le Seigneur m’a relevé EXEMPLE.'), findsWidgets);
      // Mes témoignages : les trois, avec leur statut.
      expect(find.text('Mes témoignages'), findsOneWidget);
      expect(find.text('Approuvé'), findsOneWidget);
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Rejeté'), findsOneWidget);
      // Modération : l'en attente seulement.
      expect(find.text('À modérer (1)'), findsOneWidget);
      expect(find.text('Approuver'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });

    testWidgets('approuver retire le témoignage de la modération',
        (tester) async {
      final api = await _connecter(tester);
      api.definirTemoignages([_enAttente]);
      await _pomper(tester, const TemoignagesScreen(), api);
      expect(find.text('À modérer (1)'), findsOneWidget);
      await tester.tap(find.text('Approuver'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('À modérer'), findsNothing);
      expect(find.text('Mes témoignages'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Compositeur', () {
    testWidgets('Publier désactivé sans texte ni média, actif avec texte',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const CreationTemoignageScreen(), api);
      final bouton = find.widgetWithText(FilledButton, 'Publier');
      expect(bouton, findsOneWidget);
      expect(tester.widget<FilledButton>(bouton).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField),
        'Témoignage EXEMPLE.',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(bouton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });

  group('Lecteur', () {
    testWidgets('texte lu sur place, fond noir', (tester) async {
      final api = await _connecter(tester);
      await _pomper(
        tester,
        const LecteurTemoignageScreen(temoignage: _approuve, urlMedia: ''),
        api,
      );
      expect(find.text('Le Seigneur m’a relevé EXEMPLE.'), findsOneWidget);
      expect(find.text('Marie EXEMPLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _demonter(tester);
    });
  });
}
