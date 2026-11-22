import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/widgets/champ_membre_choisir_creer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// « Choisir dans la base ou créer » (Tranche Formulaires P0) :
/// sélection dans la base via le sélecteur avec recherche, création
/// sur place (mini-formulaire nom / téléphone / e-mail) qui devient
/// la sélection, remplissage d'un nom libre pour les responsables
/// en texte libre (activité, événement spécial).
void main() {
  const membres = [
    Member(
      id: 'm1',
      matricule: 'M-KA-010190-01',
      fullName: 'Koné Aminata',
      status: 'actif',
    ),
    Member(
      id: 'm2',
      matricule: 'M-DB-150585-01',
      fullName: 'Diabaté Bintou',
      status: 'actif',
    ),
  ];

  Future<Member> creerFaux({
    required String fullName,
    String? phone,
    String? email,
  }) async =>
      Member(
        id: 'm-nouveau',
        matricule: 'M-NO-010100-01',
        fullName: fullName,
        phone: phone,
        email: email,
        status: 'actif',
      );

  Future<void> ouvrirSelecteur(WidgetTester tester) async {
    await tester.tap(find.text('Choisir un membre…'));
    await tester.pump();
  }

  group('ChampMembreChoisirCreer', () {
    Future<void> pomper(
      WidgetTester tester, {
      ValueChanged<String?>? onChanged,
      List<Member> liste = membres,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampMembreChoisirCreer(
                membres: liste,
                valeur: null,
                onChanged: onChanged ?? (_) {},
                onCreerMembre: creerFaux,
                label: 'Responsable',
                aide: 'Choisissez un membre ou créez-le.',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('choisir dans la base : sélection par recherche',
        (tester) async {
      String? choix;
      await pomper(tester, onChanged: (v) => choix = v);
      await ouvrirSelecteur(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Rechercher un membre…'), 'bint');
      await tester.pump();
      expect(find.text('Diabaté Bintou'), findsOneWidget);
      expect(find.text('Koné Aminata'), findsNothing);
      await tester.tap(find.text('Diabaté Bintou'));
      await tester.pump();
      expect(choix, 'm2');
      expect(find.text('Diabaté Bintou'), findsOneWidget);
    });

    testWidgets('créer sur place : le membre créé devient la sélection',
        (tester) async {
      String? choix;
      Member? cree;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampMembreChoisirCreer(
                membres: membres,
                valeur: null,
                onChanged: (v) => choix = v,
                onCreerMembre: creerFaux,
                onMembreCree: (m) => cree = m,
                label: 'Responsable',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Créer un membre'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nom complet *'), 'N’Guessan Yao');
      await tester.enterText(
          find.widgetWithText(TextField, 'Téléphone *'), '07 07 07 07 07');
      await tester.tap(find.text('Créer et sélectionner'));
      await tester.pump();
      await tester.pump();
      expect(cree?.fullName, 'N’Guessan Yao');
      expect(choix, 'm-nouveau');
      expect(find.text('N’Guessan Yao'), findsOneWidget);
    });

    testWidgets('création : nom trop court et téléphone invalide refusés',
        (tester) async {
      var appels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampMembreChoisirCreer(
                membres: membres,
                valeur: null,
                onChanged: (_) {},
                onCreerMembre: ({required fullName, phone, email}) async {
                  appels++;
                  return creerFaux(
                      fullName: fullName, phone: phone, email: email);
                },
                label: 'Responsable',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Créer un membre'));
      await tester.pump();
      await tester.tap(find.text('Créer et sélectionner'));
      await tester.pump();
      expect(find.text('Entrez un nom complet (2 lettres au minimum).'),
          findsOneWidget);
      expect(appels, 0);

      await tester.enterText(
          find.widgetWithText(TextField, 'Nom complet *'), 'N’Guessan Yao');
      await tester.enterText(
          find.widgetWithText(TextField, 'Téléphone *'), '123');
      await tester.tap(find.text('Créer et sélectionner'));
      await tester.pump();
      expect(
          find.text('Entrez un numéro de téléphone à 10 chiffres '
              '(ex. 07 07 07 07 07).'),
          findsOneWidget);
      expect(appels, 0);
    });
  });

  group('ChampResponsableNomLibre', () {
    testWidgets('choisir dans la base remplit le champ du nom',
        (tester) async {
      String? nom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampResponsableNomLibre(
                membres: membres,
                valeurInitiale: null,
                onChanged: (v) => nom = v,
                onCreerMembre: creerFaux,
                label: 'Responsable',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Rechercher un membre…'));
      await tester.pump();
      await tester.tap(find.text('Koné Aminata'));
      await tester.pump();
      expect(nom, 'Koné Aminata');
    });

    testWidgets('créer sur place remplit le champ du nom', (tester) async {
      String? nom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampResponsableNomLibre(
                membres: membres,
                valeurInitiale: null,
                onChanged: (v) => nom = v,
                onCreerMembre: creerFaux,
                label: 'Responsable',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Créer'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nom complet *'), 'N’Guessan Yao');
      await tester.enterText(
          find.widgetWithText(TextField, 'Téléphone *'), '07 07 07 07 07');
      await tester.tap(find.text('Créer et sélectionner'));
      await tester.pump();
      await tester.pump();
      expect(nom, 'N’Guessan Yao');
    });

    testWidgets('un nom libre historique reste saisissable', (tester) async {
      String? nom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChampResponsableNomLibre(
                membres: membres,
                valeurInitiale: 'Pasteur invité',
                onChanged: (v) => nom = v,
                onCreerMembre: creerFaux,
                label: 'Responsable',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Pasteur invité'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Ex. Koné Aminata'),
          'Ancien Yao');
      await tester.pump();
      expect(nom, 'Ancien Yao');
    });
  });
}
