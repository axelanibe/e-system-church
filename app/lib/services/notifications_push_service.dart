import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import '../firebase_options.dart';

/// Gestionnaire d'arrière-plan FCM : doit être une fonction de niveau
/// supérieur. Il ne fait que réveiller Firebase ; l'ouverture de la
/// conversation a lieu au toucher, via `onMessageOpenedApp` ou
/// `getInitialMessage`. Sans configuration Firebase, l'initialisation
/// échoue et le gestionnaire ne fait rien.
@pragma('vm:entry-point')
Future<void> gestionnaireNotificationsArrierePlan(
    RemoteMessage message) async {
  try {
    await NotificationsPushService.initialiserFirebase();
  } catch (e) {
    debugPrint('[Push] Arrière-plan sans configuration Firebase : $e');
    return;
  }
  debugPrint('[Push] Message reçu en arrière-plan : ${message.messageId}');
}

/// Message push reçu, réduit aux champs utilisés par l'application.
/// L'identifiant de conversation vient des données (`conversationId`
/// ou `conversation_id`) ; sans lui, l'ouverture tombe sur l'écran
/// des messages. Le titre et le corps viennent de la notification,
/// quand le serveur en joint une.
class PushMessageRecue {
  const PushMessageRecue({this.conversationId, this.titre, this.corps});

  factory PushMessageRecue.depuisMessage(RemoteMessage message) =>
      PushMessageRecue.depuisDonnees(
        message.data,
        titre: message.notification?.title,
        corps: message.notification?.body,
      );

  factory PushMessageRecue.depuisDonnees(
    Map<String, dynamic> data, {
    String? titre,
    String? corps,
  }) {
    final id = data['conversationId'] ?? data['conversation_id'];
    return PushMessageRecue(
      conversationId: id is String && id.isNotEmpty ? id : null,
      titre: titre,
      corps: corps,
    );
  }

  /// Identifiant de la conversation concernée, null si la notification
  /// n'en porte pas.
  final String? conversationId;

  /// Titre affiché par la notification, null sans notification jointe.
  final String? titre;

  /// Corps affiché par la notification, null sans notification jointe.
  final String? corps;
}

/// Notifications push FCM de la messagerie (tranche push FCM).
///
/// Cycle : demande d'autorisation, récupération du jeton FCM,
/// enregistrement auprès du serveur (`POST /messagerie/jetons`),
/// rafraîchissement du jeton, retrait à la déconnexion
/// (`DELETE /messagerie/jetons`). En avant-plan, les messages arrivent
/// sur [enAvantPlan] (bannière dans l'application) ; en arrière-plan
/// ou application fermée, le toucher arrive sur [aOuvrir] ou dans
/// [prendreMessageInitial].
///
/// Sans configuration Firebase (projet `e-system-church` non fourni :
/// ni `google-services.json` sur Android, ni `firebase_options.dart`
/// pour le web), le service se désactive proprement : [actif] est
/// faux, aucun plantage, aucune écoute. La messagerie reste utilisable
/// sans push. [messaging] ne sert qu'aux tests.
class NotificationsPushService {
  NotificationsPushService._(this._api, this._messaging);

  /// Crée le service et le démarre. Sans configuration Firebase,
  /// renvoie un service désactivé ([actif] faux).
  static Future<NotificationsPushService> initialiser(
    ApiService api, {
    FirebaseMessaging? messaging,
  }) async {
    if (messaging != null) {
      final service = NotificationsPushService._(api, messaging);
      await service._demarrer();
      return service;
    }
    try {
      await initialiserFirebase();
    } catch (e) {
      debugPrint(
          '[Push] Firebase non configuré, notifications push désactivées : $e');
      return NotificationsPushService._(api, null);
    }
    try {
      final service =
          NotificationsPushService._(api, FirebaseMessaging.instance);
      await service._demarrer();
      return service;
    } catch (e) {
      debugPrint('[Push] Notifications push indisponibles : $e');
      return NotificationsPushService._(api, null);
    }
  }

  /// Enregistre le gestionnaire d'arrière-plan, à appeler dans `main()`
  /// avant `runApp()`. Sans configuration Firebase, ne fait rien.
  static Future<void> initialiserArrierePlan() async {
    try {
      await initialiserFirebase();
      FirebaseMessaging.onBackgroundMessage(
          gestionnaireNotificationsArrierePlan);
    } catch (e) {
      debugPrint(
          '[Push] Arrière-plan désactivé, Firebase non configuré : $e');
    }
  }

  /// Initialise Firebase : sur le web, avec les options du projet
  /// `e-system-church` ([DefaultFirebaseOptions.web]) ; sur Android,
  /// sans option, la configuration vient de `google-services.json`.
  /// Appelée aussi par le gestionnaire d'arrière-plan.
  static Future<void> initialiserFirebase() async {
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      await Firebase.initializeApp();
    }
  }

  /// Service sans Firebase, pour les tests : les flux restent
  /// utilisables via [simulerMessageRecu] et [simulerMessageAToucher].
  @visibleForTesting
  NotificationsPushService.pourTest(this._api) : _messaging = null;

  final ApiService _api;
  final FirebaseMessaging? _messaging;

  final _avantPlan = StreamController<PushMessageRecue>.broadcast();
  final _aOuvrir = StreamController<PushMessageRecue>.broadcast();
  final _abonnements = <StreamSubscription>[];

  PushMessageRecue? _messageInitiale;
  String? _jeton;
  bool _actif = false;

  /// Vrai quand Firebase est configuré, l'autorisation accordée et les
  /// écoutes branchées. Faux sans configuration Firebase.
  bool get actif => _actif && _messaging != null;

  /// Messages reçus en avant-plan : à afficher dans l'application
  /// (bannière avec bouton Ouvrir).
  Stream<PushMessageRecue> get enAvantPlan => _avantPlan.stream;

  /// Messages dont le toucher doit ouvrir la conversation (arrière-plan
  /// ou application fermée puis rouverte par la notification).
  Stream<PushMessageRecue> get aOuvrir => _aOuvrir.stream;

  /// Message qui a ouvert l'application fermée, null sinon. Consommé
  /// une seule fois : l'appel suivant renvoie null.
  PushMessageRecue? prendreMessageInitial() {
    final message = _messageInitiale;
    _messageInitiale = null;
    return message;
  }

  /// Demande l'autorisation, enregistre le jeton FCM et branche les
  /// écoutes (messages, toucher, rafraîchissement du jeton, message
  /// initial). Un refus d'autorisation ou un échec laisse le service
  /// désactivé, sans planter.
  Future<void> _demarrer() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final autorisation = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (autorisation.authorizationStatus !=
              AuthorizationStatus.authorized &&
          autorisation.authorizationStatus !=
              AuthorizationStatus.provisional) {
        debugPrint('[Push] Autorisation notifications refusée.');
        return;
      }
      // Sur le web, le jeton exige la clé publique VAPID, sinon
      // `getToken` ne renvoie rien et la push web reste inactive.
      // Sur Android, la clé vient de google-services.json.
      // ignore: deprecated_member_use
      _jeton = await messaging.getToken(
        vapidKey:
            kIsWeb ? DefaultFirebaseOptions.clePubliqueVapidWeb : null,
      );
      if (_jeton != null) {
        await _enregistrerJeton(_jeton!);
      }
      // `getToken` et `onTokenRefresh` sont dépréciés dans
      // firebase_messaging 17 au profit de `register` et `onRegistered`,
      // qui fournissent l'identifiant d'installation (FID) et non le
      // jeton FCM. Le contrat de cette tranche est le jeton FCM
      // (`POST /messagerie/jetons`), utilisé tel quel par l'envoi
      // serveur : on garde l'API jeton, fonctionnelle, et la bascule
      // vers le FID se décidera côté serveur.
      // ignore: deprecated_member_use
      _abonnements.add(messaging.onTokenRefresh.listen((jeton) async {
        _jeton = jeton;
        await _enregistrerJeton(jeton);
      }));
      _abonnements.add(FirebaseMessaging.onMessage.listen((message) {
        _avantPlan.add(PushMessageRecue.depuisMessage(message));
      }));
      _abonnements.add(
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _aOuvrir.add(PushMessageRecue.depuisMessage(message));
      }));
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _messageInitiale = PushMessageRecue.depuisMessage(initial);
      }
      _actif = true;
      debugPrint('[Push] Notifications push actives.');
    } catch (e) {
      debugPrint('[Push] Démarrage impossible : $e');
      await _annulerAbonnements();
    }
  }

  /// Retire le jeton FCM auprès du serveur et coupe les écoutes. À
  /// appeler à la déconnexion, tant que l'appel reste authentifié.
  /// Un échec (hors ligne, route indisponible) n'empêche jamais la
  /// déconnexion.
  Future<void> desactiver() async {
    final jeton = _jeton;
    await _annulerAbonnements();
    _actif = false;
    if (jeton != null) {
      try {
        await _api.retirerJetonPush(jeton: jeton);
        debugPrint('[Push] Jeton FCM retiré.');
      } catch (e) {
        debugPrint('[Push] Retrait du jeton impossible : $e');
      }
      _jeton = null;
    }
  }

  Future<void> dispose() async {
    await _annulerAbonnements();
    await _avantPlan.close();
    await _aOuvrir.close();
  }

  Future<void> _annulerAbonnements() async {
    for (final abonnement in _abonnements) {
      await abonnement.cancel();
    }
    _abonnements.clear();
  }

  /// Enregistre le jeton auprès du serveur. Un échec (hors ligne,
  /// route indisponible) ne bloque rien : la messagerie reste
  /// utilisable, seule la push manque, et le jeton sera renvoyé au
  /// prochain démarrage ou au prochain rafraîchissement.
  Future<void> _enregistrerJeton(String jeton) async {
    try {
      await _api.enregistrerJetonPush(jeton: jeton, plateforme: _plateforme);
      debugPrint('[Push] Jeton FCM enregistré.');
    } catch (e) {
      debugPrint('[Push] Enregistrement du jeton impossible : $e');
    }
  }

  /// Canal de cet appareil, pour le ciblage côté serveur.
  String get _plateforme {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'autre';
    }
  }

  /// Injecte un message reçu en avant-plan (tests uniquement).
  @visibleForTesting
  void simulerMessageRecu(PushMessageRecue message) =>
      _avantPlan.add(message);

  /// Injecte un message à ouvrir au toucher (tests uniquement).
  @visibleForTesting
  void simulerMessageAToucher(PushMessageRecue message) =>
      _aOuvrir.add(message);
}
