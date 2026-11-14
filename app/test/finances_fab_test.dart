import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/screens/finances_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// État minimal pour pomper l'écran réel : l'API démo connectée en admin,
/// les droits finances ouverts. Aucun appel réseau, aucune donnée inventée.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get canReadFinances => true;

  @override
  bool get canManageFinances => true;
}

const _pastilles = [
  'Tous types',
  'Dîmes',
  'Offrandes',
  'Dons',
  'Dépenses',
  'Cotisations',
  'Tous statuts',
  'En attente',
  'Confirmées',
  'Annulées',
];

void main() {
  testWidgets(
      'Finances, Contributions : le bouton Ajouter ne masque aucune pastille',
      (tester) async {
    final api = FauxApiService();
    // Temps réel : dans testWidgets l'horloge est fictive, le délai de
    // 120 ms du mock ne se déclencherait jamais sans pompage.
    await tester.runAsync(() => api.login(
          identifiant: DemoAccounts.adminEmail,
          password: DemoAccounts.password,
        ));

    // Corps de l'écran Finances sur le téléphone d'Axel (390 de large,
    // ~580 de haut utile : l'écran est hébergé sous l'en-tête clair de
    // HomeScreen, au-dessus de la barre de navigation. La barre de
    // périmètre, élément de prototype, n'y est plus.)
    tester.view.physicalSize = const Size(390, 580);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AppState>.value(
        value: _EtatFaux(api),
        child: const FinancesScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Contributions'), findsWidgets);
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    const cadre = Rect.fromLTWH(0, 0, 390, 580);

    List<String> masquees() {
      final bouton = tester.getRect(fab);
      final cachees = <String>[];
      for (final libelle in _pastilles) {
        // Sous le pli, la ListView ne construit pas encore la pastille :
        // non visible donc non masquée.
        if (find.text(libelle).evaluate().isEmpty) continue;
        final pastille = tester.getRect(find.text(libelle));
        if (pastille.overlaps(cadre) && pastille.overlaps(bouton)) {
          cachees.add(libelle);
        }
      }
      return cachees;
    }

    void mesurer(String position) {
      final bouton = tester.getRect(fab);
      final lignes = <String>[];
      for (final libelle in _pastilles) {
        if (find.text(libelle).evaluate().isEmpty) {
          lignes.add('$libelle:absent');
          continue;
        }
        final pastille = tester.getRect(find.text(libelle));
        lignes.add(
            '$libelle:${pastille.top.toStringAsFixed(0)}-${pastille.bottom.toStringAsFixed(0)}');
      }
      // ignore: avoid_print
      print('$position bouton=${bouton.top.toStringAsFixed(0)}-'
          '${bouton.bottom.toStringAsFixed(0)} ${lignes.join(' ')} '
          'masquees=${masquees()}');
    }

    // Départ : les pastilles sont en tête de liste, visibles, et aucune
    // n'est sous le bouton.
    mesurer('depart');
    expect(find.text('Confirmées'), findsOneWidget);
    expect(masquees(), isEmpty);

    // Descente par paliers jusqu'au bout de la liste : à chaque arrêt,
    // aucune pastille visible ne doit être sous le bouton.
    final liste = find.byType(ListView);
    for (var i = 0; i < 10; i++) {
      await tester.drag(liste, const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 300));
      mesurer('palier${i + 1}');
      expect(masquees(), isEmpty,
          reason: 'pastille masquée au palier ${i + 1}');
    }

    // Retour en haut : les pastilles sont de nouveau visibles, intactes.
    await tester.drag(liste, const Offset(0, 800));
    await tester.pump(const Duration(milliseconds: 300));
    mesurer('retour');
    expect(find.text('Confirmées'), findsOneWidget);
    expect(masquees(), isEmpty);

    // En bas de liste, les pastilles sont entièrement au-dessus du bouton :
    // la marge basse de la liste les laisse défiler au-dessus de lui.
    final bouton = tester.getRect(fab);
    for (final libelle in _pastilles) {
      if (find.text(libelle).evaluate().isEmpty) continue;
      final pastille = tester.getRect(find.text(libelle));
      expect(pastille.bottom, lessThanOrEqualTo(bouton.top),
          reason: '$libelle doit être au-dessus du bouton en bas de liste');
    }
    expect(masquees(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
