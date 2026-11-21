import 'package:esystem_church/models/messagerie.dart';
import 'package:esystem_church/screens/mes_sanctions_screen.dart';
import 'package:esystem_church/screens/messagerie_conversation_screen.dart';
import 'package:esystem_church/screens/messagerie_moderation_screen.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/preferences_locales.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

Future<FauxApiService> _connecter(WidgetTester tester) async {
  final api = FauxApiService();
  await tester.runAsync(
    () => api.login(
      identifiant: DemoAccounts.adminEmail,
      password: DemoAccounts.password,
    ),
  );
  return api;
}

Future<void> _pomper(
  WidgetTester tester,
  Widget ecran,
  FauxApiService api,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
        ChangeNotifierProvider<PreferencesLocales>.value(
          value: PreferencesLocales(),
        ),
      ],
      child: MaterialApp(home: ecran),
    ),
  );
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('Modèles messagerie T-Msg-4', () {
    test('MessageMessagerie.fromJson lit edited_at et deleted_at', () {
      final modifie = MessageMessagerie.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 's1',
        'content': 'Corrigé',
        'type': 'text',
        'created_at': '2026-11-21T10:00:00.000Z',
        'edited_at': '2026-11-21T10:05:00.000Z',
      });
      expect(modifie.estModifie, isTrue);
      expect(modifie.supprime, isFalse);
      final supprime = MessageMessagerie.fromJson({
        'id': 'm2',
        'conversation_id': 'c1',
        'sender_id': 's1',
        'content': 'Message supprimé',
        'type': 'text',
        'created_at': '2026-11-21T10:00:00.000Z',
        'deleted_at': '2026-11-21T10:06:00.000Z',
      });
      expect(supprime.supprime, isTrue);
      expect(supprime.estModifie, isFalse);
      final copie = supprime.copyWith(content: 'Autre');
      expect(copie.content, 'Autre');
      expect(copie.supprime, isTrue);
    });

    test('libelleMotifSignalement couvre les 7 motifs du schéma 034', () {
      expect(libelleMotifSignalement('harassment'), 'Harcèlement');
      expect(libelleMotifSignalement('hate_speech'), 'Propos haineux');
      expect(libelleMotifSignalement('threat'), 'Menace');
      expect(
        libelleMotifSignalement('misinformation'),
        'Informations trompeuses',
      );
      expect(libelleMotifSignalement('spam'), 'Spam');
      expect(libelleMotifSignalement('child_safety'), 'Sécurité d’un enfant');
      expect(libelleMotifSignalement('other'), 'Autre');
      expect(motifsSignalement.length, 7);
    });

    test('phrase de visibilité : référent, mère, local', () {
      expect(
        phraseVisibiliteSignalement('local', 'child_safety'),
        contains('référent protection de l’enfance'),
      );
      expect(
        phraseVisibiliteSignalement('mother', 'child_safety'),
        contains('référent protection de l’enfance'),
      );
      expect(
        phraseVisibiliteSignalement('mother', 'spam'),
        contains('L’église mère verra votre nom'),
      );
      expect(
        phraseVisibiliteSignalement('local', 'spam'),
        contains('Les modérateurs de votre église verront votre nom'),
      );
      for (final motif in motifsSignalement) {
        expect(
          phraseVisibiliteSignalement('local', motif),
          contains('ne verra jamais votre nom'),
        );
      }
    });

    test('libellés statuts, actions et durées', () {
      expect(libelleStatutSignalement('pending'), 'En attente');
      expect(libelleStatutSignalement('in_review'), 'En cours');
      expect(libelleStatutSignalement('resolved'), 'Résolu');
      expect(libelleStatutSignalement('dismissed'), 'Rejeté');
      expect(libelleStatutSignalement('escalated'), 'Transmis');
      expect(libelleStatutSignalement('appealed'), 'Contesté');
      expect(libelleActionModeration('rejeter'), 'Rejeter');
      expect(libelleActionModeration('avertir'), 'Avertir');
      expect(libelleActionModeration('sourdine'), 'Mettre en sourdine');
      expect(libelleActionModeration('suspendre'), 'Suspendre la messagerie');
      expect(libelleDureeModeration(24), '24 heures');
      expect(libelleDureeModeration(168), '7 jours');
      expect(libelleDureeModeration(720), '30 jours');
    });

    test('peutContester et joursRestantsRecours : 15 jours', () {
      final sanction = DateTime(2026, 11, 21, 10);
      expect(
        peutContester(sanction, DateTime(2026, 11, 30)),
        isTrue,
      );
      expect(
        peutContester(sanction, DateTime(2026, 12, 6, 10, 0, 1)),
        isFalse,
      );
      expect(joursRestantsRecours(sanction, DateTime(2026, 11, 30)), 6);
      expect(joursRestantsRecours(sanction, DateTime(2026, 12, 10)), 0);
      expect(delaiRecoursJours, 15);
      expect(delaiReponseRecoursJours, 30);
    });

    test('Signalement.fromJson lit la preuve figée', () {
      final signalement = Signalement.fromJson({
        'id': 'r1',
        'target_type': 'message',
        'target_id': 'm1',
        'reason': 'harassment',
        'description': 'Propos déplacés.',
        'evidence_snapshot': {
          'content': 'Message à signaler.',
          'sender_nom': 'Autre Fidèle',
          'created_at': '2026-11-21T10:00:00.000Z',
        },
        'routed_to': 'local',
        'status': 'pending',
        'created_at': '2026-11-21T10:01:00.000Z',
        'reporter_nom': 'Admin',
      });
      expect(signalement.motif, 'harassment');
      expect(signalement.evidenceContenu, 'Message à signaler.');
      expect(signalement.evidenceAuteur, 'Autre Fidèle');
      expect(signalement.rapporteurNom, 'Admin');
      expect(signalement.escalade, isFalse);
    });

    test('SanctionMessagerie.fromJson lit le délai de recours', () {
      final sanction = SanctionMessagerie.fromJson({
        'action_id': 'a1',
        'report_id': 'r1',
        'action': 'avertir',
        'notes': 'Avertissement.',
        'created_at': '2026-11-21T10:00:00.000Z',
        'contester_avant': '2026-12-06T10:00:00.000Z',
        'contestable': true,
        'appel_en_cours': false,
      });
      expect(sanction.action, 'avertir');
      expect(sanction.contestable, isTrue);
    });
  });

  group('Flux signalement / modération (faux service)', () {
    test('signaler, modérer, contester, traiter le recours', () async {
      final api = FauxApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
        password: DemoAccounts.password,
      );
      final conversation = await api.creerConversationMessagerie(
        type: 'directe',
        participantMemberIds: ['demo-m-002'],
      );
      final message = await api.envoyerMessageConversation(
        conversation.id,
        content: 'Message à signaler.',
      );

      // Modifier / supprimer (doucement).
      final modifie = await api.modifierMessageConversation(
        conversation.id,
        message.id,
        content: 'Message corrigé.',
      );
      expect(modifie.content, 'Message corrigé.');
      expect(modifie.estModifie, isTrue);
      final supprime = await api.supprimerMessageConversation(
        conversation.id,
        message.id,
      );
      expect(supprime.content, 'Message supprimé');
      expect(supprime.supprime, isTrue);
      final messages = await api.getMessagesConversation(conversation.id);
      expect(messages.length, 1);
      expect(messages.first.content, 'Message supprimé');

      // Signaler un deuxième message.
      final deuxieme = await api.envoyerMessageConversation(
        conversation.id,
        content: 'Message à modérer.',
      );
      final signalement = await api.signalerContenu(
        targetType: 'message',
        targetId: deuxieme.id,
        motif: 'harassment',
        description: 'Propos déplacés.',
      );
      expect(signalement.statut, 'pending');
      expect(signalement.routedTo, 'local');
      expect(signalement.evidenceContenu, 'Message à modérer.');

      // Sécurité d'un enfant : routage forcé vers le référent.
      final enfant = await api.signalerContenu(
        targetType: 'message',
        targetId: deuxieme.id,
        motif: 'child_safety',
        destinataire: 'mother',
      );
      expect(enfant.routedTo, 'child_safety_referent');

      // Note motivée exigée.
      await expectLater(
        api.traiterSignalement(
          signalement.id,
          action: 'avertir',
          notes: '   ',
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.traiterSignalement(
          signalement.id,
          action: 'sourdine',
          notes: 'Note.',
        ),
        throwsA(isA<ApiException>()),
      );

      // Avertir, puis mes sanctions et le recours.
      await api.traiterSignalement(
        signalement.id,
        action: 'avertir',
        notes: 'Avertissement.',
      );
      final apres = await api.getSignalement(signalement.id);
      expect(apres.statut, 'resolved');
      final sanctions = await api.getMesSanctions();
      expect(sanctions.length, 1);
      expect(sanctions.first.action, 'avertir');
      expect(sanctions.first.contestable, isTrue);
      final recours = await api.contesterSanction(
        signalement.id,
        motif: 'Je conteste.',
      );
      expect(recours.statut, 'pending');
      expect(recours.repondreAvant, isNotNull);
      final signaleAppeal = await api.getSignalement(signalement.id);
      expect(signaleAppeal.statut, 'appealed');
      final recoursListe = await api.getRecoursSignalement(signalement.id);
      expect(recoursListe.length, 1);
      await expectLater(
        api.contesterSanction(signalement.id),
        throwsA(isA<ApiException>()),
      );
      final traite = await api.traiterRecours(
        recours.id,
        statut: 'dismissed',
      );
      expect(traite.statut, 'dismissed');
      final apresRecours = await api.getSignalement(signalement.id);
      expect(apresRecours.statut, 'resolved');

      // Escalade vers l'église mère.
      final escalade = await api.escaladerSignalement(
        enfant.id,
        destination: 'mother',
      );
      expect(escalade.statut, 'escalated');
      expect(escalade.routedTo, 'mother');
    });
  });

  group('Écrans T-Msg-4', () {
    testWidgets('Modération : état vide, puis un signalement',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(
        tester,
        const MessagerieModerationScreen(),
        api,
      );
      expect(
        find.text('Aucun signalement dans cette file.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Modération : dossier, action avec note motivée',
        (tester) async {
      final api = await _connecter(tester);
      late String signalementId;
      await tester.runAsync(() async {
        final conversation = await api.creerConversationMessagerie(
          type: 'directe',
          participantMemberIds: ['demo-m-002'],
        );
        final message = await api.envoyerMessageConversation(
          conversation.id,
          content: 'Message à modérer.',
        );
        final signalement = await api.signalerContenu(
          targetType: 'message',
          targetId: message.id,
          motif: 'harassment',
          description: 'Propos déplacés.',
        );
        signalementId = signalement.id;
      });
      await _pomper(
        tester,
        const MessagerieModerationScreen(),
        api,
      );
      expect(find.text('Harcèlement'), findsOneWidget);
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Message à modérer.'), findsOneWidget);
      await tester.tap(find.text('Message à modérer.'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Contenu figé au moment du signalement'),
        findsOneWidget,
      );
      expect(find.text('Appliquer la décision'), findsOneWidget);
      // Sans note, le bouton est désactivé.
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Appliquer la décision'),
      );
      expect(bouton.onPressed, isNull);
      await tester.enterText(
        find.byType(TextField).last,
        'Avertissement.',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Appliquer la décision'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Décision enregistrée.'), findsOneWidget);
      // Vérification directe : le faux service avance en temps réel
      // dans runAsync, pas à l'horloge factice du test.
      final apres = await tester.runAsync(
        () => api.getSignalement(signalementId),
      );
      expect(apres?.statut, 'resolved');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mes sanctions : état vide, puis contester',
        (tester) async {
      final api = await _connecter(tester);
      await _pomper(tester, const MesSanctionsScreen(), api);
      expect(
        find.text('Aucune sanction ne vous concerne.'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        final conversation = await api.creerConversationMessagerie(
          type: 'directe',
          participantMemberIds: ['demo-m-002'],
        );
        final message = await api.envoyerMessageConversation(
          conversation.id,
          content: 'Message sanctionné.',
        );
        final signalement = await api.signalerContenu(
          targetType: 'message',
          targetId: message.id,
          motif: 'spam',
        );
        await api.traiterSignalement(
          signalement.id,
          action: 'avertir',
          notes: 'Spam.',
        );
      });
      // Deuxième pompe avec une clé différente : sans elle, l'arbre
      // réutilise l'état du premier écran (liste vide) et ne
      // recharge pas.
      await _pomper(
        tester,
        const MesSanctionsScreen(key: ValueKey('apres-semis')),
        api,
      );
      expect(find.text('Avertir'), findsOneWidget);
      expect(find.text('Contester'), findsOneWidget);
      await tester.tap(find.text('Contester'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Envoyer le recours'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Recours envoyé.'), findsOneWidget);
      final sanctions = await tester.runAsync(
            () => api.getMesSanctions(),
          ) ??
          [];
      expect(sanctions.first.appelEnCours, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Conversation : Signaler ouvre la feuille, appui long propose '
        'Modifier / Supprimer', (tester) async {
      final api = await _connecter(tester);
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
            ChangeNotifierProvider<AppState>.value(value: _EtatFaux(api)),
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
      // Bouton Signaler : la feuille s'ouvre avec le motif et la
      // phrase de visibilité.
      await tester.tap(find.byTooltip('Signaler'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Motif *'), findsOneWidget);
      expect(
        find.textContaining('ne verra jamais votre nom'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Envoyer le signalement'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Envoyer le signalement'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Signalement envoyé. Merci.'), findsOneWidget);
      // Le SnackBar recouvre le bas de l'écran : on le laisse expirer
      // avant d'envoyer un message et de faire un appui long.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
      // Envoi d'un de mes messages, puis appui long.
      await tester.enterText(find.byType(TextField), 'Message à moi');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Message à moi'), findsOneWidget);
      await tester.longPress(find.text('Message à moi'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.text('Signaler'), findsWidgets);
      // Modifier : le texte change et « (modifié) » apparaît.
      await tester.tap(find.text('Modifier'));
      await tester.pump(const Duration(milliseconds: 300));
      final champDialogue = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(champDialogue, 'Message à moi, corrigé');
      await tester.tap(find.text('Enregistrer'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Message à moi, corrigé'), findsOneWidget);
      expect(find.textContaining('(modifié)'), findsOneWidget);
      // Supprimer : le contenu devient « Message supprimé ».
      await tester.longPress(find.text('Message à moi, corrigé'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Supprimer'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Supprimer').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Message supprimé'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
