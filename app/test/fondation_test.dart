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
    test('palette Vision Sanctuary Modern tranchée', () {
      expect(AppTheme.fondAlabaster, const Color(0xFFF7F5F0));
      expect(AppTheme.ivoire, const Color(0xFFFCFBF8));
      expect(AppTheme.sable, const Color(0xFFEFECE4));
      expect(AppTheme.bordure, const Color(0xFFE6E2D8));
      expect(AppTheme.cypress, const Color(0xFF1E4D3B));
      expect(AppTheme.cypressFonce, const Color(0xFF143629));
      expect(AppTheme.terracotta, const Color(0xFFC86D51));
      expect(AppTheme.orAmbre, const Color(0xFFB8862D));
      expect(AppTheme.encre, const Color(0xFF1A1D20));
      expect(AppTheme.ardoise, const Color(0xFF525B65));
      expect(AppTheme.rougeErreur, const Color(0xFFB3261E));
      expect(AppTheme.cultes, const Color(0xFF6B4C7A));
      expect(AppTheme.presences, const Color(0xFF2B6CB0));
      expect(AppTheme.prieres, const Color(0xFFB8506A));
      expect(AppTheme.enfants, const Color(0xFFC07A1C));
      expect(AppTheme.medias, const Color(0xFF3F51B5));
    });

    test('contrastes des textes principaux au moins 4,5:1', () {
      double contraste(Color a, Color b) {
        final l1 = a.computeLuminance();
        final l2 = b.computeLuminance();
        final clair = l1 > l2 ? l1 : l2;
        final sombre = l1 > l2 ? l2 : l1;
        return (clair + 0.05) / (sombre + 0.05);
      }

      const fond = AppTheme.fondAlabaster;
      expect(contraste(AppTheme.encre, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.cypress, fond), greaterThanOrEqualTo(4.5));
      expect(
          contraste(AppTheme.cypressFonce, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.ardoise, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.rougeErreur, fond),
          greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.cultes, fond), greaterThanOrEqualTo(4.5));
      expect(
          contraste(AppTheme.presences, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.medias, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(Colors.white, AppTheme.cypress),
          greaterThanOrEqualTo(4.5));
      expect(contraste(Colors.white, AppTheme.cypressFonce),
          greaterThanOrEqualTo(4.5));
    });

    test('typographies : Inter, Plus Jakarta Sans, JetBrains Mono', () {
      final textes = AppTheme.theme.textTheme;
      expect(textes.bodyMedium?.fontFamily, contains('Inter'));
      expect(textes.headlineSmall?.fontFamily, contains('Jakarta'));
      expect(textes.titleLarge?.fontFamily, contains('Jakarta'));
      expect(textes.labelSmall?.fontFamily, contains('JetBrainsMono'));
      expect(AppTheme.styleCode.fontFamily, contains('JetBrainsMono'));
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
