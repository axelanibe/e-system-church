import 'faux_api_service.dart';
import 'package:esystem_church/models/abonnement.dart';
import 'package:esystem_church/screens/abonnement_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Jours restants sur « Mon abonnement » : affichés dans la carte
/// « Mon plan » quand une date permet le calcul, absents sinon.
/// Données EXEMPLE uniquement, jamais de données réelles.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

/// Faux service qui sert l'abonnement donné, sans appel réseau.
class _ApiAbonnement extends FauxApiService {
  _ApiAbonnement(this._abonnement);

  final Abonnement _abonnement;

  @override
  Future<Abonnement> getMonAbonnement() async => _abonnement;
}

void main() {
  Future<void> pomper(WidgetTester tester, Abonnement abonnement) async {
    // Thème par défaut, pas celui de l'application : avec AppTheme,
    // le minimumSize infini des FilledButton fait planter le harnais
    // sur la ligne du code promo (préexistant, identique sur l'écran
    // d'origine, hors périmètre). Les textes affichés sont les mêmes.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(
            value: _EtatFaux(_ApiAbonnement(abonnement)),
          ),
        ],
        child: const MaterialApp(
          home: AbonnementScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Jours restants affichés', () {
    testWidgets('essai commencé il y a 10 jours : 20 restants',
        (tester) async {
      // dateDebut = aujourd'hui - 10 jours : passé en jour relatif
      // via le paramètre jour (-10).
      final jour = DateTime.now();
      final debut = DateTime(jour.year, jour.month, jour.day)
          .subtract(const Duration(days: 10));
      await pomper(
        tester,
        Abonnement(
          estAnnexe: false,
          statut: 'essai',
          plan: 'annuel',
          montantFcfa: 200000,
          dateDebut: debut,
          essaiJours: 30,
          lectureSeule: false,
        ),
      );
      expect(find.text('Jours restants : 20'), findsOneWidget);
      expect(find.text('Essai gratuit'), findsOneWidget);
      expect(find.text('30 jours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expiration dans 45 jours : 45', (tester) async {
      final jour = DateTime.now();
      final expiration = DateTime(jour.year, jour.month, jour.day)
          .add(const Duration(days: 45));
      await pomper(
        tester,
        Abonnement(
          estAnnexe: false,
          statut: 'actif',
          plan: 'annuel',
          montantFcfa: 200000,
          dateExpiration: expiration,
          essaiJours: 30,
          lectureSeule: false,
        ),
      );
      expect(find.text('Jours restants : 45'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grâce, expiration passée de 5 jours : 25 restants',
        (tester) async {
      final jour = DateTime.now();
      final expiration = DateTime(jour.year, jour.month, jour.day)
          .subtract(const Duration(days: 5));
      await pomper(
        tester,
        Abonnement(
          estAnnexe: false,
          statut: 'grace',
          plan: 'annuel',
          montantFcfa: 200000,
          dateExpiration: expiration,
          essaiJours: 30,
          lectureSeule: false,
        ),
      );
      expect(find.text('Jours restants : 25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aucune date : aucune ligne Jours restants',
        (tester) async {
      await pomper(
        tester,
        const Abonnement(
          estAnnexe: false,
          statut: 'actif',
          plan: 'annuel',
          montantFcfa: 200000,
          essaiJours: 30,
          lectureSeule: false,
        ),
      );
      expect(find.textContaining('Jours restants'), findsNothing);
      expect(find.text('Date d’expiration : À compléter'), findsOneWidget);
      expect(find.text('30 jours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
