import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/models/identite.dart';
import 'package:esystem_church/screens/identite_institutionnelle_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

const _mere = IdentiteInstitutionnelle(
  egliseId: DemoIds.plateau,
  egliseCode: 'ESC-0411',
  egliseNom: 'Église Grâce Divine',
  statut: 'brouillon',
  nomOfficiel: 'Église Grâce Divine',
  sigle: 'EGD',
  adresse: 'Cocody, Abidjan',
  ville: 'Abidjan',
  pays: 'Côte d’Ivoire',
  telephone: '+225 07 47 00 01',
  email: 'contact@gracedivine.ci',
  devise: 'FCFA',
  fuseauHoraire: 'Africa/Abidjan',
  couleurPrincipale: '#2A0059',
  description: 'Église mère du réseau Grâce Divine.',
);

const _annexe = IdentiteInstitutionnelle(
  egliseId: DemoIds.yopougon,
  egliseCode: 'ESC-0420',
  egliseNom: 'Grâce Divine Yopougon',
  estAnnexe: true,
  mere: EgliseMereIdentite(
    id: DemoIds.plateau,
    code: 'ESC-0411',
    nom: 'Église Grâce Divine',
  ),
  heritee: true,
  statut: 'publié',
  statutMere: 'publié',
  nomOfficiel: 'Église Grâce Divine',
  sigle: 'EGD',
  ville: 'Abidjan',
  pays: 'Côte d’Ivoire',
  devise: 'FCFA',
  fuseauHoraire: 'Africa/Abidjan',
  couleurPrincipale: '#2A0059',
);

Future<FauxApiService> _pomper(
    WidgetTester tester, IdentiteInstitutionnelle identite) async {
  final api = FauxApiService();
  await tester.runAsync(() => api.login(
        identifiant: DemoAccounts.adminEmail,
        password: 'demo1234',
      ));
  api.definirIdentite(identite);
  tester.view.physicalSize = const Size(390, 1800);
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
      child: const MaterialApp(
        home: IdentiteInstitutionnelleScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return api;
}

void main() {
  test('modèle : fromJson lit le contrat, mere et JSONB compris', () {
    final identite = IdentiteInstitutionnelle.fromJson({
      'eglise_id': 'e1',
      'eglise_code': 'ESC-0420',
      'eglise_nom': 'Annexe',
      'est_annexe': true,
      'mere': {'id': 'm1', 'code': 'ESC-0411', 'nom': 'Mère'},
      'heritee': true,
      'statut': 'publié',
      'statut_mere': 'publié',
      'nom_officiel': 'Église Mère',
      'couleurs': {'secondaire': '#3D0073'},
      'infos_legales': {'forme': 'Association'},
      'parametres_documents': {'langue': 'fr'},
      'horaires_cultes': [
        {'jour': 'Dimanche', 'heure': '09:00'},
      ],
      'adresse_locale': 'Yopougon',
      'email_local': null,
    });
    expect(identite.estAnnexe, isTrue);
    expect(identite.heritee, isTrue);
    expect(identite.mere?.nom, 'Mère');
    expect(identite.couleurs?['secondaire'], '#3D0073');
    expect(identite.infosLegales?['forme'], 'Association');
    expect(identite.horairesCultes?.length, 1);
    expect(identite.adresseLocale, 'Yopougon');
    expect(identite.emailLocal, isNull);
    expect(identite.toJson()['nom_officiel'], 'Église Mère');
  });

  testWidgets('mère en écriture : champs modifiables, Enregistrer '
      'appelle patchIdentite', (tester) async {
    final api = await _pomper(tester, _mere);
    expect(find.text('Informations de l’église'), findsOneWidget);
    expect(find.text('Logo et identité visuelle'), findsOneWidget);
    expect(
        find.text('Seule l’identité publiée est diffusée aux branches.'),
        findsOneWidget);
    expect(
        find.text('Non publiée : vos branches voient encore leurs '
            'valeurs actuelles.'),
        findsOneWidget);
    expect(find.text('Identité héritée'), findsNothing);
    final champNom =
        tester.widget<TextField>(find.byKey(const Key('champ_nom_officiel')));
    expect(champNom.enabled, isTrue);
    await tester.enterText(find.byKey(const Key('champ_nom_officiel')),
        'Église Grâce Divine Renouvelée');
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(api.dernierPatchIdentite?['nom_officiel'],
        'Église Grâce Divine Renouvelée');
    expect(api.dernierPatchIdentite?.containsKey('statut'), isFalse);
  });

  testWidgets('annexe en lecture seule : bandeau héritée, champs '
      'désactivés, pas de bouton Enregistrer', (tester) async {
    await _pomper(tester, _annexe);
    expect(
        find.text('Identité héritée de votre église mère '
            'Église Grâce Divine'),
        findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Changer le logo (PNG/JPG, max 2 Mo)'), findsNothing);
    expect(
        find.text('Non publiée : vos branches voient encore leurs '
            'valeurs actuelles.'),
        findsNothing);
    final champNom =
        tester.widget<TextField>(find.byKey(const Key('champ_nom_officiel')));
    expect(champNom.enabled, isFalse);
    expect(champNom.controller?.text, 'Église Grâce Divine');
    final champVille =
        tester.widget<TextField>(find.byKey(const Key('champ_ville')));
    expect(champVille.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
