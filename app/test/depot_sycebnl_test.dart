import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/depot_sycebnl.dart';
import 'package:esystem_church/models/identite.dart';
import 'package:esystem_church/models/sycebnl.dart';
import 'package:esystem_church/screens/depot_sycebnl_screen.dart';
import 'package:esystem_church/screens/identite_institutionnelle_screen.dart';
import 'package:esystem_church/screens/registres_sycebnl_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Dépôt SYCEBNL (V1, migration 043) : états étendus, registres,
/// seuil et échéance, suivi du dépôt, champ NCC.
/// Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;
}

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
  await tester.pumpAndSettle();
}

void main() {
  group('EtatsSycebnl étendus', () {
    test('bilan équilibré et flux cohérents avec les registres', () {
      // Mêmes chiffres que le test serveur : produits 60 000 000,
      // charges 3 000 000, ouverture 1 000 000 ; immobilisation nette
      // 750 000, créance 100 000, dette 500 000 ; achat 1 000 000 et
      // dette 500 000 dans l'exercice.
      final etats = EtatsSycebnl.depuisDonnees(
        annee: 2026,
        produits: 60000000,
        charges: 3000000,
        ouverture: 1000000,
        actifImmobilise: 750000,
        actifCirculant: 100000,
        dettes: 500000,
        fluxInvestissement: -1000000,
        fluxFinancement: 500000,
        notesRedigees: 1,
      );
      expect(etats.resultatExercice, 57000000);
      expect(etats.tresorerieCloture, 58000000);
      expect(etats.fondsPropres, 58350000);
      expect(etats.totalActif, 58850000);
      expect(etats.totalPassif, 58850000);
      expect(etats.totalActif, etats.totalPassif);
      expect(etats.fluxOperationnelles, 57500000);
      expect(etats.variationTresorerie, 57000000);
      expect(etats.variationTresorerie, etats.resultatExercice);
      expect(etats.notesRedigees, 1);
    });

    test('sans registre, le comportement de la P6 est conservé', () {
      final etats = EtatsSycebnl.depuisDonnees(
        annee: 2026,
        produits: 60000000,
        charges: 3000000,
        ouverture: 1000000,
      );
      expect(etats.fondsPropres, etats.tresorerieCloture);
      expect(etats.fluxInvestissement, 0);
      expect(etats.fluxFinancement, 0);
      expect(etats.fluxOperationnelles, etats.resultatExercice);
      expect(etats.variationTresorerie, etats.resultatExercice);
      expect(etats.totalActif, etats.totalPassif);
    });
  });

  group('Modèles des registres et du dépôt', () {
    test('valeur nette et libellés de statut', () {
      const immo = Immobilisation(
        id: 'i1',
        libelle: 'Temple EXEMPLE',
        dateAcquisition: '2026-03-10',
        valeurAcquisition: 1000000,
        amortissementCumule: 250000,
      );
      expect(immo.valeurNette, 750000);
      expect(
        const Dette(
          id: 'd1',
          libelle: 'Emprunt EXEMPLE',
          montant: 500000,
          echeance: null,
          statut: 'en_cours',
        ).statutLibelle,
        'En cours',
      );
      expect(
        const Creance(
          id: 'c1',
          libelle: 'Loyer EXEMPLE',
          montant: 100000,
          echeance: null,
          statut: 'soldee',
        ).statutLibelle,
        'Soldée',
      );
      expect(
        const SuiviDepotSycebnl(
          exercice: 2026,
          statut: 'depose',
          dateDepot: '2027-05-20',
          reference: 'REC-EXEMPLE',
        ).statutLibelle,
        'Déposé',
      );
    });

    test('échéance du dépôt : 30 mai de l’année suivante', () {
      const depot = DepotSycebnl(
        annee: 2026,
        ressources: 62000000,
        seuil: 50000000,
        requis: true,
        echeance: '2027-05-30',
        suivi: null,
      );
      expect(depot.echeanceAffichee, '30/05/2027');
      expect(depot.requis, isTrue);
    });
  });

  group('Écran Registres SYCEBNL', () {
    testWidgets('liste une immobilisation et l’onglet Dettes vide',
        (tester) async {
      final api = await _connecter(tester);
      await tester.runAsync(
        () => api.createImmobilisation(
          libelle: 'Temple EXEMPLE',
          dateAcquisition: '2026-03-10',
          valeurAcquisition: 1000000,
          amortissementCumule: 250000,
        ),
      );
      await _pomper(tester, const RegistresSycebnlScreen(), api);
      expect(find.text('Temple EXEMPLE'), findsOneWidget);
      expect(find.textContaining('750 000 FCFA'), findsWidgets);
      await tester.tap(find.text('Dettes'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune dette enregistrée'), findsOneWidget);
      await tester.ensureVisible(find.text('Notes annexes'));
      await tester.tap(find.text('Notes annexes'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune note annexe rédigée'), findsOneWidget);
    });

    testWidgets('le bouton ouvre le dialogue de création',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const RegistresSycebnlScreen(), api);
      expect(find.text('Aucune immobilisation enregistrée'), findsOneWidget);
      await tester.tap(find.text('Nouvelle immobilisation'));
      await tester.pumpAndSettle();
      expect(find.text('Libellé *'), findsOneWidget);
      expect(find.text('Date d’acquisition *'), findsOneWidget);
    });
  });

  group('Écran Dépôt SYCEBNL', () {
    testWidgets('sous le seuil : aucun dépôt imposé, NCC non renseigné',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const DepotSycebnlScreen(), api);
      expect(
        find.text(
          'Aucun dépôt fiscal SYCEBNL n’est imposé pour cet exercice : vos ressources sont en dessous du seuil.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('12 000 000 FCFA'), findsWidgets);
      expect(find.textContaining('NCC non renseigné'), findsOneWidget);
      expect(
        find.textContaining(
          'Le dépôt se fait par l’église sur e-impots.gouv.ci',
        ),
        findsOneWidget,
      );
    });

    testWidgets('au-dessus du seuil : dépôt requis et échéance affichée',
        (tester) async {
      final api = await _connecter(tester);
      final annee = DateTime.now().year;
      api.definirDepotSycebnl(
        DepotSycebnl(
          annee: annee,
          ressources: 62000000,
          seuil: 50000000,
          requis: true,
          echeance: '${annee + 1}-05-30',
          suivi: null,
        ),
      );
      await _pomper(tester, const DepotSycebnlScreen(), api);
      expect(find.text('Dépôt requis : vos ressources atteignent le seuil.'),
          findsOneWidget);
      expect(find.textContaining('62 000 000 FCFA'), findsWidgets);
      expect(find.textContaining('À déposer avant le 30/05/'), findsOneWidget);
    });

    testWidgets('le suivi passe à Prêt et se relit', (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const DepotSycebnlScreen(), api);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.text('À préparer'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prêt').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enregistrer le suivi'));
      await tester.tap(find.text('Enregistrer le suivi'));
      await tester.pumpAndSettle();
      expect(find.text('Prêt'), findsWidgets);
      final relu = await tester.runAsync(
        () => api.getDepotSycebnl(annee: DateTime.now().year),
      );
      expect(relu?.suivi?.statut, 'pret');
    });

    testWidgets('déposé sans date : refus avec explication',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const DepotSycebnlScreen(), api);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.text('À préparer'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déposé').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enregistrer le suivi'));
      await tester.tap(find.text('Enregistrer le suivi'));
      await tester.pump();
      expect(
        find.text(
          'Indiquez la date du dépôt pour marquer l’exercice comme déposé.',
        ),
        findsOneWidget,
      );
      final relu = await tester.runAsync(
        () => api.getDepotSycebnl(annee: DateTime.now().year),
      );
      expect(relu?.suivi, isNull);
    });
  });

  group('Champ NCC dans l’identité', () {
    testWidgets('le champ NCC apparaît et sa valeur se relit',
        (tester) async {
      final api = await _connecter(tester);
      api.definirIdentite(
        const IdentiteInstitutionnelle(
          egliseId: DemoIds.plateau,
          egliseCode: 'ESC-0411',
          egliseNom: 'Église Grâce Divine',
          nomOfficiel: 'Église Grâce Divine',
          ncc: 'NCC-EXEMPLE-123',
        ),
      );
      await _pomper(
        tester,
        const IdentiteInstitutionnelleScreen(),
        api,
      );
      expect(
        find.text('Numéro de compte contribuable (NCC)'),
        findsOneWidget,
      );
      expect(find.text('NCC-EXEMPLE-123'), findsOneWidget);
    });
  });
}
