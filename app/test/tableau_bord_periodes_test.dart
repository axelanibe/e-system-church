import 'package:esystem_church/models/abonnement.dart';
import 'package:esystem_church/screens/dashboard_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

void main() {
  group('Tableau de bord — périodes', () {
    test('fenêtres : aujourd’hui compare à hier', () {
      final ref = DateTime(2026, 11, 23);
      final f = fenetresPeriodeTableauBord(
          PeriodeTableauBord.aujourdHui, ref);
      expect(f.debut, DateTime(2026, 11, 23));
      expect(f.fin, DateTime(2026, 11, 23));
      expect(f.debutPrec, DateTime(2026, 11, 22));
      expect(f.finPrec, DateTime(2026, 11, 22));
    });

    test('fenêtres : 7 jours contre les 7 jours précédents', () {
      final ref = DateTime(2026, 11, 23);
      final f =
          fenetresPeriodeTableauBord(PeriodeTableauBord.septJours, ref);
      expect(f.debut, DateTime(2026, 11, 17));
      expect(f.fin, DateTime(2026, 11, 23));
      expect(f.debutPrec, DateTime(2026, 11, 10));
      expect(f.finPrec, DateTime(2026, 11, 16));
    });

    test('fenêtres : 30 jours contre les 30 jours précédents', () {
      final ref = DateTime(2026, 11, 23);
      final f = fenetresPeriodeTableauBord(
          PeriodeTableauBord.trenteJours, ref);
      expect(f.debut, DateTime(2026, 10, 25));
      expect(f.fin, DateTime(2026, 11, 23));
      expect(f.debutPrec, DateTime(2026, 9, 25));
      expect(f.finPrec, DateTime(2026, 10, 24));
    });

    test('libellés des pastilles', () {
      expect(libellePeriodeTableauBord(PeriodeTableauBord.aujourdHui),
          'Aujourd’hui');
      expect(libellePeriodeTableauBord(PeriodeTableauBord.septJours),
          '7 jours');
      expect(libellePeriodeTableauBord(PeriodeTableauBord.trenteJours),
          '30 jours');
    });
  });

  group('Tableau de bord — variations', () {
    test('hausse avec signe +', () {
      expect(texteVariation(5, 2), '+3');
    });

    test('baisse avec signe -', () {
      expect(texteVariation(2, 5), '-3');
    });

    test('égalité non nulle : +0', () {
      expect(texteVariation(3, 3), '+0');
    });

    test('rien des deux côtés : pas de variation affichée', () {
      expect(texteVariation(0, 0), isNull);
    });
  });

  group('Tableau de bord — signaux d’attention', () {
    test('aucune donnée : aucun signal, pas de carte', () {
      expect(
          signauxAttention(
            abonnement: null,
            demandesATraiter: 0,
            caisseMoisPrecedentNonCloturee: false,
            moisPrecedent: 'octobre 2026',
          ),
          isEmpty);
    });

    test('abonnement à plus de 30 jours : pas de signal', () {
      final abo = Abonnement(
        estAnnexe: false,
        statut: 'actif',
        plan: 'annuel',
        montantFcfa: 200000,
        dateExpiration:
            DateTime.now().add(const Duration(days: 45)),
        essaiJours: 30,
        lectureSeule: false,
      );
      expect(
          signauxAttention(
            abonnement: abo,
            demandesATraiter: 0,
            caisseMoisPrecedentNonCloturee: false,
            moisPrecedent: 'octobre 2026',
          ),
          isEmpty);
    });

    test('abonnement à 12 jours : signal avec le nombre de jours', () {
      final abo = Abonnement(
        estAnnexe: false,
        statut: 'actif',
        plan: 'annuel',
        montantFcfa: 200000,
        dateExpiration:
            DateTime.now().add(const Duration(days: 12)),
        essaiJours: 30,
        lectureSeule: false,
      );
      final signaux = signauxAttention(
        abonnement: abo,
        demandesATraiter: 0,
        caisseMoisPrecedentNonCloturee: false,
        moisPrecedent: 'octobre 2026',
      );
      expect(signaux, hasLength(1));
      expect(signaux.first, contains('12 jours restants'));
    });

    test('abonnement expiré : signal lecture seule', () {
      const abo = Abonnement(
        estAnnexe: false,
        statut: 'expire',
        plan: 'annuel',
        montantFcfa: 200000,
        essaiJours: 30,
        lectureSeule: true,
      );
      final signaux = signauxAttention(
        abonnement: abo,
        demandesATraiter: 0,
        caisseMoisPrecedentNonCloturee: false,
        moisPrecedent: 'octobre 2026',
      );
      expect(signaux, hasLength(1));
      expect(signaux.first, contains('lecture seule'));
    });

    test('demandes et caisse : un signal par fait', () {
      final signaux = signauxAttention(
        abonnement: null,
        demandesATraiter: 3,
        caisseMoisPrecedentNonCloturee: true,
        moisPrecedent: 'octobre 2026',
      );
      expect(signaux, hasLength(2));
      expect(signaux[0], contains('3 éléments à traiter'));
      expect(
          signaux[1], 'Caisse de octobre 2026 non clôturée.');
    });
  });

  group('Tableau de bord — écran', () {
    testWidgets('pastilles, changement de période et carte d’attention',
        (tester) async {
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
                value: _EtatFaux(api)),
            ChangeNotifierProvider<PreferencesLocales>.value(
                value: PreferencesLocales()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DashboardScreen(onAller: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pastilles et chiffres présents, sans débordement. Les libellés
      // des cartes et des sections sont affichés en capitales.
      expect(find.text('7 jours'), findsOneWidget);
      expect(find.text('30 jours'), findsOneWidget);
      expect(find.text('CHIFFRES DE MON ÉGLISE'), findsOneWidget);
      expect(find.text('MEMBRES'), findsOneWidget);
      // « Présences du jour » et « Visiteurs du jour » apparaissent
      // deux fois : mini-stat de la carte « Aujourd’hui » et carte
      // de chiffres.
      expect(find.text('PRÉSENCES DU JOUR'), findsNWidgets(2));
      expect(find.text('VISITEURS DU JOUR'), findsNWidgets(2));
      expect(find.text('NOUVEAUX MEMBRES'), findsOneWidget);
      // Données de démo : des prières en attente, donc la carte
      // d'attention s'affiche avec le nombre d'éléments à traiter.
      expect(find.text('À surveiller'), findsOneWidget);
      expect(find.text('• 3 éléments à traiter.'), findsOneWidget);
      // Données de démo datées (novembre 2026) : 0 partout sur la
      // période courante, donc aucune variation affichée, jamais
      // de faux chiffre.
      expect(find.textContaining(RegExp(r'^\+[0-9]+$')), findsNothing);
      expect(find.textContaining(RegExp(r'^-[0-9]+$')), findsNothing);

      // Passage à 7 jours : les libellés des cartes suivent. La
      // mini-stat de la carte « Aujourd’hui » garde « du jour ».
      await tester.tap(find.text('7 jours'));
      await tester.pumpAndSettle();
      expect(find.text('PRÉSENCES · 7 JOURS'), findsOneWidget);
      expect(find.text('VISITEURS · 7 JOURS'), findsOneWidget);
      expect(find.text('PRÉSENCES DU JOUR'), findsOneWidget);
      expect(find.text('VISITEURS DU JOUR'), findsOneWidget);
    });
  });
}

/// État admin factice, comme dans les tests d'écrans T10-T12.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get canReadFinances => true;

  @override
  bool get canManageFinances => true;

  @override
  bool get canManageMembers => true;

  @override
  bool get isAdmin => true;
}
