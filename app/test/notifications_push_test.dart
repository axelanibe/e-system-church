import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';
import 'package:esystem_church/firebase_options.dart';
import 'package:esystem_church/main.dart';
import 'package:esystem_church/screens/fidele_shell.dart';
import 'package:esystem_church/screens/messages_admin_screen.dart';
import 'package:esystem_church/screens/messages_fidele_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/http_api_service.dart';
import 'package:esystem_church/services/notifications_push_service.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Notifications push FCM (tranche push FCM) : analyse des données
/// reçues, enregistrement du jeton (appel HTTP), ouverture de la
/// conversation, et comportement sans configuration Firebase.
/// Aucun appel réseau réel : serveur HTTP local ou faux service.
class _EtatFaux extends AppState {
  _EtatFaux(this._api, {required this.membre});

  final ApiService _api;
  final bool membre;

  @override
  ApiService get api => _api;

  @override
  bool get initialized => true;

  @override
  bool get isLoggedIn => true;

  @override
  bool get isPlateforme => false;

  @override
  bool get isMembre => membre;

  @override
  String? get role => membre ? 'membre' : 'admin_eglise';
}

void main() {
  group('PushMessageRecue', () {
    test('lit conversationId', () {
      const message = PushMessageRecue(conversationId: 'conv-1');
      expect(message.conversationId, 'conv-1');
      final depuisDonnees =
          PushMessageRecue.depuisDonnees({'conversationId': 'conv-2'});
      expect(depuisDonnees.conversationId, 'conv-2');
    });

    test('accepte conversation_id', () {
      final message =
          PushMessageRecue.depuisDonnees({'conversation_id': 'conv-3'});
      expect(message.conversationId, 'conv-3');
    });

    test('sans identifiant, null : ouverture sur les messages', () {
      final message = PushMessageRecue.depuisDonnees({'autre': 'x'});
      expect(message.conversationId, isNull);
      final vide = PushMessageRecue.depuisDonnees({});
      expect(vide.conversationId, isNull);
      final videChaine =
          PushMessageRecue.depuisDonnees({'conversationId': ''});
      expect(videChaine.conversationId, isNull);
    });

    test('garde le titre et le corps de la notification', () {
      final message = PushMessageRecue.depuisDonnees(
        {'conversationId': 'conv-4'},
        titre: 'Nouveau message',
        corps: 'Bonjour',
      );
      expect(message.titre, 'Nouveau message');
      expect(message.corps, 'Bonjour');
    });
  });

  group('Configuration Firebase web', () {
    test('options du projet e-system-church', () {
      const options = DefaultFirebaseOptions.web;
      expect(options.projectId, 'e-system-church');
      expect(options.messagingSenderId, '487372952475');
      expect(options.appId, '1:487372952475:web:3ddcf8fe363362dc4e873e');
      expect(options.authDomain, 'e-system-church.firebaseapp.com');
      expect(options.storageBucket, 'e-system-church.firebasestorage.app');
    });
  });

  group('Service sans configuration Firebase', () {
    test('désactivé, sans planter', () async {
      final api = FauxApiService();
      final service = await NotificationsPushService.initialiser(api);
      expect(service.actif, isFalse);
      expect(service.prendreMessageInitial(), isNull);
      await service.desactiver();
      await service.dispose();
    });
  });

  group('Enregistrement du jeton', () {
    test('faux service : enregistre puis retire', () async {
      final api = FauxApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      await api.enregistrerJetonPush(
          jeton: 'jeton-test', plateforme: 'android');
      expect(api.jetonsPushEnregistres, ['jeton-test']);
      await api.retirerJetonPush(jeton: 'jeton-test');
      expect(api.jetonsPushRetires, ['jeton-test']);
    });

    testWidgets('HTTP : POST puis DELETE /messagerie/jetons',
        (tester) async {
      final requetes = <http.Request>[];
      final client = MockClient((requete) async {
        requetes.add(requete);
        return http.Response('{}', 200);
      });
      final api = HttpApiService(
        baseUrl: 'https://exemple.test',
        token: 'jwt-test',
        client: client,
      );
      await api.enregistrerJetonPush(
          jeton: 'jeton-fcm', plateforme: 'android');
      await api.retirerJetonPush(jeton: 'jeton-fcm');
      expect(requetes, hasLength(2));
      expect(requetes[0].method, 'POST');
      expect(requetes[0].url.path, '/messagerie/jetons');
      expect(requetes[0].headers['authorization'], 'Bearer jwt-test');
      expect(
        jsonDecode(requetes[0].body),
        {'jeton': 'jeton-fcm', 'plateforme': 'android'},
      );
      expect(requetes[1].method, 'DELETE');
      expect(requetes[1].url.path, '/messagerie/jetons');
      expect(requetes[1].headers['authorization'], 'Bearer jwt-test');
      expect(jsonDecode(requetes[1].body), {'jeton': 'jeton-fcm'});
    });
  });

  group('Ouverture de la conversation', () {
    test('écran selon le rôle', () {
      expect(
        ecranMessagesPourRole('membre'),
        isA<FideleShell>(),
      );
      expect(
        (ecranMessagesPourRole('membre') as FideleShell).ongletInitial,
        3,
      );
      expect(
        ecranMessagesPourRole('admin_eglise'),
        isA<MessagesAdminScreen>(),
      );
      expect(
        ecranMessagesPourRole(null),
        isA<MessagesAdminScreen>(),
      );
    });
  });

  Future<NotificationsPushService> pomperPont(
    WidgetTester tester, {
    required bool membre,
  }) async {
    final api = FauxApiService();
    await tester.runAsync(() => api.login(
          identifiant: membre
              ? DemoAccounts.membreEmail
              : DemoAccounts.adminEmail,
          password: DemoAccounts.password,
        ));
    final service = NotificationsPushService.pourTest(api);
    final etat = _EtatFaux(api, membre: membre);
    final cle = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: etat),
        ],
        child: PontNotificationsPush(
          cleNavigateur: cle,
          creerService: (_) async => service,
          child: MaterialApp(
            navigatorKey: cle,
            home: const Scaffold(body: Text('Accueil')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('toucher : ouvre le fil du fidèle', (tester) async {
    final service = await pomperPont(tester, membre: true);
    service.simulerMessageAToucher(
      const PushMessageRecue(conversationId: 'conv-9'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FideleShell), findsOneWidget);
    expect(find.byType(MessagesFideleScreen), findsOneWidget);
    await service.dispose();
  });

  testWidgets('toucher : ouvre les messages de l’administration',
      (tester) async {
    final service = await pomperPont(tester, membre: false);
    service.simulerMessageAToucher(
      const PushMessageRecue(conversationId: 'conv-9'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MessagesAdminScreen), findsOneWidget);
    await service.dispose();
  });

  testWidgets('avant-plan : bannière avec Ouvrir', (tester) async {
    final service = await pomperPont(tester, membre: true);
    service.simulerMessageRecu(
      const PushMessageRecue(
        conversationId: 'conv-9',
        titre: 'Nouveau message',
        corps: 'Bonjour',
      ),
    );
    // Première pompe : livraison du message ; les suivantes font
    // avancer l'animation d'entrée de la bannière jusqu'à l'écran.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nouveau message'), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(FideleShell), findsOneWidget);
    expect(find.byType(MessagesFideleScreen), findsOneWidget);
    await service.dispose();
  });
}
