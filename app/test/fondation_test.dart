import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/auth.dart';
import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/fidele.dart';
import 'package:esystem_church/widgets/short_drawer.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/app_bottom_bar.dart';
import 'package:esystem_church/widgets/common_widgets.dart';
import 'package:esystem_church/widgets/carte_membre_vedette.dart';
import 'package:esystem_church/widgets/screen_header.dart';
import 'package:esystem_church/widgets/soft_button.dart';
import 'package:esystem_church/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('Thème fondation', () {
    test('palette de l\'artefact tranchée', () {
      expect(AppTheme.fondPapier, const Color(0xFFF5F6FA));
      expect(AppTheme.bordure, const Color(0xFFD9DEE6));
      expect(AppTheme.bleuNuit, const Color(0xFF0B1F3A));
      expect(AppTheme.or, const Color(0xFFD4A72C));
      expect(AppTheme.orFonce, const Color(0xFF8A6A12));
      expect(AppTheme.orClair, const Color(0xFFF7F0DA));
      expect(AppTheme.rougeErreur, const Color(0xFFB3261E));
      expect(AppTheme.vertFonce, const Color(0xFF0C5B40));
      expect(AppTheme.bleuFonce, const Color(0xFF1B4F72));
    });

    test('contrastes des textes principaux au moins 4,5:1', () {
      double contraste(Color a, Color b) {
        final l1 = a.computeLuminance();
        final l2 = b.computeLuminance();
        final clair = l1 > l2 ? l1 : l2;
        final sombre = l1 > l2 ? l2 : l1;
        return (clair + 0.05) / (sombre + 0.05);
      }

      const fond = AppTheme.fondPapier;
      expect(contraste(AppTheme.bleuNuit, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.orFonce, fond), greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.rougeErreur, fond),
          greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.vertFonce, fond),
          greaterThanOrEqualTo(4.5));
      expect(contraste(Colors.white, AppTheme.bleuNuit),
          greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.bleuNuit, AppTheme.or),
          greaterThanOrEqualTo(4.5));
      expect(contraste(AppTheme.bleuNuit, AppTheme.orClair),
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

    testWidgets('StatCard : libellé long sur une ligne, sans coupure',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              childAspectRatio: 1.9,
              children: const [
                StatCard(
                  label: 'Offrandes confirmées',
                  value: '0 FCFA',
                  icon: Icons.trending_up,
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('OFFRANDES CONFIRMÉES'), findsOneWidget);
      expect(find.text('0 FCFA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tiroir désengorgé : 10 entrées, une par fonction',
        (tester) async {
      // Fenêtre haute pour que tout le tiroir soit construit.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(),
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(
              drawer: TiroirCourt(onAller: (_) {}),
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Ouvrir'));
      await tester.pump();
      // Les 10 entrées de la simulation (celles sans condition de
      // rôle sont visibles ici ; Suivi pastoral, Rendez-vous et
      // Mon abonnement demandent un rôle).
      for (final label in [
        'Cultes et Présences',
        'Prières',
        'Serviteurs',
        'Rapports d’annexe',
        'Mes annexes et Réseau',
        'Modules de l’église',
        'Réglages',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Les anciennes entrées ont déménagé dans leur écran parent.
      for (final label in [
        'Cultes en direct',
        'Présences',
        'Budget & caisse',
        'Prières & messages',
        'Enfants & jeunesse',
        'Médias & bibliothèque',
        'Biens de l’église',
        'Rapports',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('Modules'), findsNothing);
    });
  });
}
