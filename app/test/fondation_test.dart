import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/auth.dart';
import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/fidele.dart';
import 'package:esystem_church/widgets/app_bottom_bar.dart';
import 'package:esystem_church/widgets/carte_membre_vedette.dart';
import 'package:esystem_church/widgets/screen_header.dart';
import 'package:esystem_church/widgets/soft_button.dart';
import 'package:esystem_church/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Thème fondation', () {
    test('palette soft tranchée', () {
      expect(AppTheme.fondPapier, const Color(0xFFFAF7F1));
      expect(AppTheme.saugeFonce, const Color(0xFF3F5A50));
      expect(AppTheme.sauge, const Color(0xFF6A8E7F));
      expect(AppTheme.saugeClair, const Color(0xFFE4EDE8));
      expect(AppTheme.orDoux, const Color(0xFFC9A24B));
      expect(AppTheme.ardoise, const Color(0xFF2E3440));
      expect(AppTheme.grisDoux, const Color(0xFF6B7280));
      expect(AppTheme.rougeErreur, const Color(0xFFB3261E));
      expect(AppTheme.bleuDoux, const Color(0xFF52708A));
    });

    test('typographie : titres 24 gras, sous-titres 18, corps 16, aide 14',
        () {
      final textes = AppTheme.theme.textTheme;
      expect(textes.headlineSmall?.fontSize, 24);
      expect(textes.headlineSmall?.fontWeight, FontWeight.bold);
      expect(textes.titleLarge?.fontSize, 18);
      expect(textes.bodyMedium?.fontSize, 16);
      expect(textes.bodySmall?.fontSize, 14);
    });

    test('champs 56 px, boutons 48 px', () {
      expect(AppTheme.theme.inputDecorationTheme.constraints?.minHeight,
          56);
      final style =
          AppTheme.theme.filledButtonTheme.style;
      expect(
          style?.minimumSize?.resolve({})?.height, 48);
    });
  });

  group('Widgets partagés', () {
    testWidgets('SoftCard affiche son contenu', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SoftCard(child: Text('Bonjour'))),
      ));
      expect(find.text('Bonjour'), findsOneWidget);
    });

    testWidgets('BoutonAvecAide montre le bouton et son explication',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BoutonAvecAide(
            label: 'Voir ma carte',
            aide: 'Votre carte, à montrer à l’entrée.',
            onPressed: () {},
          ),
        ),
      ));
      expect(find.text('Voir ma carte'), findsOneWidget);
      expect(find.text('Votre carte, à montrer à l’entrée.'),
          findsOneWidget);
    });

    testWidgets('EnteteEcran montre titre et sous-titre', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EnteteEcran(
            titre: 'Accueil',
            sousTitre: 'Voici votre église en un coup d’œil.',
          ),
        ),
      ));
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Voici votre église en un coup d’œil.'),
          findsOneWidget);
    });

    testWidgets('BarreDuBas : 5 libellés maximum', (tester) async {
      const cinq = [
        NavigationDestination(
            icon: Icon(Icons.home_outlined), label: 'Accueil'),
        NavigationDestination(
            icon: Icon(Icons.account_tree_outlined), label: 'Réseau'),
        NavigationDestination(
            icon: Icon(Icons.people_outlined), label: 'Membres'),
        NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Finances'),
        NavigationDestination(
            icon: Icon(Icons.grid_view_outlined), label: 'Modules'),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BarreDuBas(
            destinations: cinq,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ));
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Modules'), findsOneWidget);
    });

    test('BarreDuBas refuse un 6e libellé', () {
      const six = [
        NavigationDestination(
            icon: Icon(Icons.home_outlined), label: 'Accueil'),
        NavigationDestination(
            icon: Icon(Icons.account_tree_outlined), label: 'Réseau'),
        NavigationDestination(
            icon: Icon(Icons.people_outlined), label: 'Membres'),
        NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Finances'),
        NavigationDestination(
            icon: Icon(Icons.campaign_outlined), label: 'Annonces'),
        NavigationDestination(
            icon: Icon(Icons.grid_view_outlined), label: 'Modules'),
      ];
      expect(
        () => BarreDuBas(
          destinations: six,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
        throwsAssertionError,
      );
    });

    testWidgets('CarteMembreVedette : nom, matricule et église',
        (tester) async {
      const profil = FideleProfil(
        user: AppUser(
            id: 'u1', fullName: 'Marie Kouassi', email: 'm@exemple.ci'),
        church: Church(
            id: 'e1', code: 'ESC-TEST', name: 'Église Test',
            status: 'active'),
        role: 'membre',
        matricule: 'ESC-M-0001',
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CarteMembreVedette(
              profil: profil, onVoirCarte: () {}),
        ),
      ));
      expect(find.text('Marie Kouassi'), findsOneWidget);
      expect(find.text('Matricule : ESC-M-0001'), findsOneWidget);
      expect(find.text('Église Test'), findsOneWidget);
      expect(find.text('Voir ma carte de membre'), findsOneWidget);
    });
  });
}
