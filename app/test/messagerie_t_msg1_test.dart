import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/models/messagerie.dart';
import 'package:esystem_church/screens/messagerie_conversation_screen.dart';
import 'package:esystem_church/screens/messagerie_liste_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/messagerie_lecture_service.dart';
import 'package:esystem_church/services/messagerie_temps_reel.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'faux_api_service.dart';
import 'faux_donnees.dart';

/// État faux minimal : seule l'API est branchée sur le faux service.
class _EtatFaux extends AppState {
  _EtatFaux(this._api);

  final ApiService _api;

  @override
  ApiService get api => _api;

  @override
  bool get isAdmin => true;
}

Future<(AppState, FauxApiService)> _pomper(
  WidgetTester tester,
  Widget ecran,
) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  final etat = _EtatFaux(api);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: etat),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(home: ecran),
    ),
  );
  await tester.pump();
  // Le premier chargement des lectures locales attend jusqu'à 2 s
  // que le stockage réponde (il ne répond jamais en test).
  await tester.pump(const Duration(seconds: 3));
  return (etat, api);
}

void main() {
  group('Modèles messagerie', () {
    test('ConversationMessagerie.fromJson lit les champs du serveur', () {
      final conversation = ConversationMessagerie.fromJson({
        'id': 'c1',
        'type': 'groupe_eglise',
        'title': 'Annonces',
        'created_at': '2026-11-16T10:00:00.000Z',
        'last_message_at': '2026-11-16T11:30:00.000Z',
      });
      expect(conversation.id, 'c1');
      expect(conversation.type, 'groupe_eglise');
      expect(conversation.title, 'Annonces');
      expect(conversation.reponsesDesactivees, isFalse);
      expect(conversation.nonLus, 0);
      expect(conversation.estGroupe, isTrue);
      expect(
        conversation.lastMessageAt,
        DateTime.parse('2026-11-16T11:30:00.000Z'),
      );
    });

    test('reponses_desactivees est lu quand le serveur le renvoie', () {
      final conversation = ConversationMessagerie.fromJson({
        'id': 'c1',
        'type': 'groupe_eglise',
        'reponses_desactivees': true,
      });
      expect(conversation.reponsesDesactivees, isTrue);
    });

    test('libelleTypeConversation couvre les cinq types', () {
      expect(libelleTypeConversation('directe'), 'Directe');
      expect(libelleTypeConversation('groupe_departement'), 'Groupe');
      expect(libelleTypeConversation('groupe_eglise'), 'Canal d’église');
      expect(libelleTypeConversation('pastorale'), 'Pastorale');
      expect(libelleTypeConversation('moderation'), 'Modération');
    });

    test('MessageMessagerie.fromJson lit le message texte', () {
      final message = MessageMessagerie.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 's1',
        'content': 'Shalom !',
        'type': 'text',
        'created_at': '2026-11-16T11:30:00.000Z',
      });
      expect(message.content, 'Shalom !');
      expect(message.type, 'text');
      expect(message.conversationId, 'c1');
    });

    test('compterMessagesNonLus exclut les miens et les anciens', () {
      final messages = [
        MessageMessagerie(
          id: 'm1',
          conversationId: 'c1',
          senderId: 'autre',
          content: 'ancien',
          createdAt: DateTime.utc(2026, 11, 15, 10),
        ),
        MessageMessagerie(
          id: 'm2',
          conversationId: 'c1',
          senderId: 'moi',
          content: 'le mien',
          createdAt: DateTime.utc(2026, 11, 16, 10),
        ),
        MessageMessagerie(
          id: 'm3',
          conversationId: 'c1',
          senderId: 'autre',
          content: 'récent',
          createdAt: DateTime.utc(2026, 11, 16, 11),
        ),
      ];
      expect(
        compterMessagesNonLus(messages, 'moi', DateTime.utc(2026, 11, 16, 9)),
        1,
      );
      expect(compterMessagesNonLus(messages, 'moi', null), 2);
      expect(
        compterMessagesNonLus(
          messages,
          'moi',
          DateTime.utc(2026, 11, 16, 12),
        ),
        0,
      );
    });

    test('heureCourteConversation : heure aujourd’hui, jour sinon', () {
      final maintenant = DateTime.now();
      expect(
        heureCourteConversation(maintenant),
        '${maintenant.hour.toString().padLeft(2, '0')}:'
        '${maintenant.minute.toString().padLeft(2, '0')}',
      );
      expect(
        heureCourteConversation(DateTime(2026, 11, 12, 9, 5)),
        '12/11',
      );
      expect(heureCourteConversation(null), '');
    });

    test('trouverMonMembreId compare les e-mails sans casse', () {
      const membres = [
        Member(
          id: 'm1',
          matricule: 'ESC-M-0001',
          fullName: 'Koffi Yao',
          email: 'Koffi.Yao@demo.ci',
          status: 'actif',
        ),
      ];
      expect(trouverMonMembreId(membres, 'koffi.yao@demo.ci'), 'm1');
      expect(trouverMonMembreId(membres, 'autre@demo.ci'), isNull);
      expect(trouverMonMembreId(membres, null), isNull);
    });
  });

  group('MessagerieTempsReel', () {
    test('urlWebSocket : https devient wss, jeton en requête', () {
      final uri = MessagerieTempsReel.urlWebSocket(
        'https://e-system-church.onrender.com',
        'jeton-123',
      );
      expect(uri.scheme, 'wss');
      expect(uri.path, '/messagerie/ws');
      expect(uri.queryParameters['token'], 'jeton-123');
    });

    test('urlWebSocket : http devient ws, sans jeton sans requête', () {
      final uri = MessagerieTempsReel.urlWebSocket(
        'http://10.0.0.2:3000/api',
        null,
      );
      expect(uri.scheme, 'ws');
      expect(uri.path, '/api/messagerie/ws');
      expect(uri.queryParameters, isEmpty);
    });

    test('delaiReconnexion : exponentiel, plafonné à 30 s', () {
      expect(MessagerieTempsReel.delaiReconnexion(1).inSeconds, 1);
      expect(MessagerieTempsReel.delaiReconnexion(2).inSeconds, 2);
      expect(MessagerieTempsReel.delaiReconnexion(3).inSeconds, 4);
      expect(MessagerieTempsReel.delaiReconnexion(5).inSeconds, 16);
      expect(MessagerieTempsReel.delaiReconnexion(6).inSeconds, 30);
      expect(MessagerieTempsReel.delaiReconnexion(10).inSeconds, 30);
    });

    test('decoderMessage : enveloppe, message nu, bruit ignoré', () {
      final enveloppe = MessagerieTempsReel.decoderMessage(
        jsonEncode({
          'type': 'message',
          'message': {
            'id': 'm1',
            'conversation_id': 'c1',
            'sender_id': 's1',
            'content': 'Shalom',
            'type': 'text',
            'created_at': '2026-11-16T11:30:00.000Z',
          },
        }),
      );
      expect(enveloppe?.content, 'Shalom');
      final nu = MessagerieTempsReel.decoderMessage(
        jsonEncode({
          'id': 'm2',
          'conversation_id': 'c1',
          'sender_id': 's1',
          'content': 'Paix',
          'type': 'text',
          'created_at': '2026-11-16T11:31:00.000Z',
        }),
      );
      expect(nu?.content, 'Paix');
      expect(
        MessagerieTempsReel.decoderMessage(
          jsonEncode({'type': 'presence', 'user': 's1'}),
        ),
        isNull,
      );
      expect(MessagerieTempsReel.decoderMessage('pas du json'), isNull);
      expect(MessagerieTempsReel.decoderMessage(42), isNull);
    });

    test('reconnexion : une coupure relance la connexion', () async {
      final canaux = <_CanalFaux>[];
      final service = MessagerieTempsReel(
        baseUrl: 'https://faux.local',
        jeton: () => 'faux-jeton',
        fabriqueCanal: (uri) {
          final canal = _CanalFaux();
          canaux.add(canal);
          return canal;
        },
      );
      final recus = <MessageMessagerie>[];
      service.messages.listen(recus.add);
      final etats = <bool>[];
      service.connecte.listen(etats.add);
      service.abonner('c1');
      service.connecter();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.estConnecte, isTrue);
      expect(etats, [true]);
      // L'abonnement part à la connexion.
      expect(
        canaux.single.envoyes.single,
        jsonEncode({'type': 'subscribe', 'conversation_id': 'c1'}),
      );
      // Un message reçu arrive sur le flux.
      canaux.single.recevoir(
        jsonEncode({
          'id': 'm1',
          'conversation_id': 'c1',
          'sender_id': 's1',
          'content': 'Shalom',
          'type': 'text',
          'created_at': '2026-11-16T11:30:00.000Z',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(recus.map((m) => m.content), ['Shalom']);
      // Coupure : l'état passe à faux, puis la reconnexion relance
      // une connexion (délai de 1 s) avec réabonnement.
      canaux.single.couper();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.estConnecte, isFalse);
      expect(etats.last, isFalse);
      await Future<void>.delayed(const Duration(seconds: 1, milliseconds: 200));
      expect(canaux.length, 2);
      expect(canaux[1].envoyes.single, contains('subscribe'));
      await service.deconnecter();
    });
  });

  group('MessagerieLectureService', () {
    test('compterConversationsNonLues : dernier message après lecture', () {
      final service = MessagerieLectureService.pourTests();
      service.reinitialiserPourTests();
      final conversations = [
        ConversationMessagerie(
          id: 'c1',
          type: 'directe',
          lastMessageAt: DateTime.utc(2026, 11, 16, 11),
        ),
        ConversationMessagerie(
          id: 'c2',
          type: 'directe',
          lastMessageAt: DateTime.utc(2026, 11, 16, 10),
        ),
        const ConversationMessagerie(id: 'c3', type: 'directe'),
      ];
      expect(service.compterConversationsNonLues(conversations), 2);
    });
  });

  group('Écrans messagerie', () {
    testWidgets('Liste : état vide chaleureux et filtres', (tester) async {
      await _pomper(tester, const MessagerieListeScreen());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('Aucune conversation pour l’instant.'),
        findsOneWidget,
      );
      for (final filtre in ['Toutes', 'Directes', 'Groupes', 'Pastorale']) {
        expect(find.text(filtre), findsOneWidget);
      }
      expect(find.text('Nouvelle conversation'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Liste : une conversation s’affiche avec son aperçu',
        (tester) async {
      // On sème la conversation avant d'afficher la liste (elle ne
      // charge qu'une fois, à l'ouverture).
      final api = FauxApiService();
      await tester.runAsync(
        () => api.login(
          identifiant: DemoAccounts.adminEmail,
          password: DemoAccounts.password,
        ),
      );
      await tester.runAsync(() async {
        final conversation = await api.creerConversationMessagerie(
          type: 'directe',
          participantMemberIds: ['demo-m-002'],
        );
        await api.envoyerMessageConversation(
          conversation.id,
          content: 'Shalom, bienvenue !',
        );
      });
      final etat = _EtatFaux(api);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: etat),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: const MaterialApp(home: MessagerieListeScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Conversation directe'), findsOneWidget);
      expect(find.text('Shalom, bienvenue !'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Conversation : messages, saisie et Signaler inerte',
        (tester) async {
      final api = FauxApiService();
      await tester.runAsync(
        () => api.login(
          identifiant: DemoAccounts.adminEmail,
          password: DemoAccounts.password,
        ),
      );
      late ConversationMessagerie conversation;
      await tester.runAsync(() async {
        conversation = await api.creerConversationMessagerie(
          type: 'directe',
          participantMemberIds: ['demo-m-002'],
        );
        await api.envoyerMessageConversation(
          conversation.id,
          content: 'Premier message',
        );
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(
              value: _EtatFaux(api),
            ),
            ChangeNotifierProvider<PreferencesLocales>.value(
              value: PreferencesLocales(),
            ),
          ],
          child: MaterialApp(
            home: MessagerieConversationScreen(
              conversation: conversation,
              titre: 'Conversation directe',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Premier message'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Signaler'), findsOneWidget);
      // Le champ de saisie est à 16 px minimum (pas de zoom iPhone).
      final champ = tester.widget<TextField>(find.byType(TextField));
      expect(champ.style?.fontSize, 16);
      // Signaler est inerte en T-Msg-1.
      await tester.tap(find.byTooltip('Signaler'));
      await tester.pump();
      expect(find.text('Bientôt disponible'), findsOneWidget);
      // Envoi d'un message par HTTP.
      await tester.enterText(find.byType(TextField), 'Réponse');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Réponse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Canal WebSocket faux : le test pousse des trames entrantes et lit
/// les trames sortantes (abonnements).
class _CanalFaux extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _entrant = StreamController<String>();
  final _sortant = StreamController<String>();
  final List<String> envoyes = [];

  _CanalFaux() {
    _sortant.stream.listen(envoyes.add);
  }

  void recevoir(String trame) => _entrant.add(trame);

  void couper() => _entrant.close();

  @override
  Stream<dynamic> get stream => _entrant.stream;

  @override
  WebSocketSink get sink => _PuitsFaux(_sortant);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

class _PuitsFaux implements WebSocketSink {
  final StreamController<String> _controleur;

  _PuitsFaux(this._controleur);

  @override
  void add(dynamic data) => _controleur.add(data as String);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _controleur.close();
  }

  @override
  Future<void> get done => _controleur.done;
}
