import 'package:esystem_church/widgets/selecteur_recherche.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sélecteur avec recherche (Tranche Formulaires P0) : champ fermé,
/// panneau superposé avec barre de recherche séparée, filtrage par
/// sous-chaîne insensible à la casse, sélection, effacement.
void main() {
  const options = [
    OptionSelecteur(valeur: 'abouasso', libelle: 'ABOUASSO'),
    OptionSelecteur(valeur: 'bouake', libelle: 'BOUAKE'),
    OptionSelecteur(valeur: 'dabou', libelle: 'DABOU'),
    OptionSelecteur(valeur: 'tabou', libelle: 'TABOU'),
    OptionSelecteur(valeur: 'yopougon', libelle: 'YOPOUGON'),
  ];

  Future<void> pomper(
    WidgetTester tester, {
    String? valeur,
    ValueChanged<String?>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelecteurRecherche<String>(
            options: options,
            valeur: valeur,
            onChanged: onChanged ?? (_) {},
            label: 'Juridiction',
            placeholder: 'Sélectionnez la juridiction',
          ),
        ),
      ),
    );
  }

  Future<void> ouvrirPanneau(WidgetTester tester) async {
    await tester.tap(find.text('Sélectionnez la juridiction'));
    await tester.pump();
  }

  testWidgets('au repos : champ fermé, choix affiché après sélection',
      (tester) async {
    await pomper(tester);
    expect(find.text('Sélectionnez la juridiction'), findsOneWidget);
    expect(find.text('BOUAKE'), findsNothing);

    await ouvrirPanneau(tester);
    expect(find.widgetWithText(TextField, 'Rechercher…'), findsOneWidget);
    await tester.tap(find.text('BOUAKE'));
    await tester.pump();

    // Le panneau est fermé, le choix s'affiche dans le champ.
    expect(find.widgetWithText(TextField, 'Rechercher…'), findsNothing);
    expect(find.text('BOUAKE'), findsOneWidget);
  });

  testWidgets('filtrage par sous-chaîne insensible à la casse',
      (tester) async {
    await pomper(tester);
    await ouvrirPanneau(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher…'), 'bou');
    await tester.pump();

    // « bou » retrouve BOUAKE, DABOU, TABOU et ABOUASSO (sous-chaîne),
    // pas YOPOUGON.
    expect(find.text('BOUAKE'), findsOneWidget);
    expect(find.text('DABOU'), findsOneWidget);
    expect(find.text('TABOU'), findsOneWidget);
    expect(find.text('ABOUASSO'), findsOneWidget);
    expect(find.text('YOPOUGON'), findsNothing);
  });

  testWidgets('recherche sans résultat : message précis', (tester) async {
    await pomper(tester);
    await ouvrirPanneau(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher…'), 'zzz');
    await tester.pump();
    expect(find.text('Aucun résultat pour cette recherche.'), findsOneWidget);
  });

  testWidgets('croix et « Effacer la sélection » remettent le champ à vide',
      (tester) async {
    String? choix;
    await pomper(tester, onChanged: (v) => choix = v);
    await ouvrirPanneau(tester);
    await tester.tap(find.text('TABOU'));
    await tester.pump();
    expect(choix, 'tabou');
    expect(find.text('Effacer la sélection'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(choix, isNull);
    expect(find.text('Sélectionnez la juridiction'), findsOneWidget);
    expect(find.text('Effacer la sélection'), findsNothing);
  });

  testWidgets('liste vide : message, pas de panneau de choix',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelecteurRecherche<String>(
            options: const [],
            valeur: null,
            onChanged: (_) {},
            label: 'Membre',
            texteVide: 'Aucun membre — créez-en un.',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sélectionnez'));
    await tester.pump();
    expect(find.text('Aucun membre — créez-en un.'), findsOneWidget);
  });
}
