import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/messagerie.dart';

/// Client WebSocket de la messagerie (T-Msg-1, spécification §10).
///
/// Connexion à `wss://<base API>/messagerie/ws?token=<jeton JWT>`,
/// avec le jeton courant du service API (lu à chaque connexion, pour
/// suivre les rotations). Reconnexion automatique avec délai
/// exponentiel (sauf après une fermeture 1008, jeton ou rôle refusé),
/// réabonnement après reconnexion, et repli HTTP : tant que le
/// WebSocket est coupé, les écrans rafraîchissent par `GET` (au retour
/// sur l'écran et par interrogation périodique) et affichent
/// « Reconnexion… ».
///
/// État du serveur : la route `/messagerie/ws` existe depuis T-Msg-1
/// (T-Msg-0 n'avait installé que la dépendance `@fastify/websocket`).
/// Le serveur ferme en 1008 quand le jeton est invalide ou le rôle
/// refusé ; le client ne reconnecte pas après une 1008, toute
/// reconnexion serait vouée à l'échec, et bascule sur le repli HTTP.
///
/// Protocole (T-Msg-1) :
/// - abonnement envoyé à chaque connexion, par conversation ouverte :
///   `{"type":"subscribe","conversation_id":"…"}` ;
/// - message reçu : `{"type":"message","message":{…}}`, ou l'objet
///   message nu (`{id, conversation_id, sender_id, content, …}`).
/// Les autres trames sont ignorées.
class MessagerieTempsReel {
  MessagerieTempsReel({
    required this.baseUrl,
    required this.jeton,
    WebSocketChannel Function(Uri uri)? fabriqueCanal,
  }) : _fabriqueCanal =
           fabriqueCanal ?? ((uri) => WebSocketChannel.connect(uri));

  /// Base de l'API, par exemple `https://e-system-church.onrender.com`.
  final String baseUrl;

  /// Jeton JWT courant, lu à chaque (re)connexion.
  final String? Function() jeton;

  final WebSocketChannel Function(Uri uri) _fabriqueCanal;

  final _messagesController =
      StreamController<MessageMessagerie>.broadcast();
  final _etatController = StreamController<bool>.broadcast();

  /// Messages reçus par WebSocket (déjà décodés).
  Stream<MessageMessagerie> get messages => _messagesController.stream;

  /// État de la connexion : vrai quand le WebSocket est ouvert.
  Stream<bool> get connecte => _etatController.stream;

  bool get estConnecte => _connecte;

  WebSocketChannel? _canal;
  bool _connecte = false;
  bool _ferme = false;

  /// Fermeture 1008 reçue (jeton invalide ou rôle refusé) : le
  /// serveur l'a dit, toute reconnexion serait vouée à l'échec.
  bool _refusAuthentification = false;
  int _tentative = 0;
  Timer? _minuteurReconnexion;
  final Set<String> _abonnements = {};

  /// URL WebSocket : `http` devient `ws`, `https` devient `wss`,
  /// jeton en paramètre de requête quand il est présent.
  static Uri urlWebSocket(String baseUrl, String? token) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(
      scheme: scheme,
      path: '${base.path}/messagerie/ws'.replaceAll('//', '/'),
      queryParameters: token == null ? null : {'token': token},
    );
  }

  /// Délai avant la tentative [tentative] (1 = première reconnexion) :
  /// 1 s, 2 s, 4 s, 8 s, 16 s, puis 30 s plafonné.
  static Duration delaiReconnexion(int tentative) {
    final secondes = math.min(1 << (tentative - 1), 30);
    return Duration(seconds: secondes);
  }

  /// Ouvre (ou rouvre) la connexion. Sans effet si déjà connecté, si
  /// le service est fermé, ou après un refus d'authentification (1008).
  void connecter() {
    if (_ferme || _refusAuthentification || _connecte || _canal != null) {
      return;
    }
    WebSocketChannel canal;
    try {
      canal = _fabriqueCanal(urlWebSocket(baseUrl, jeton()));
    } catch (_) {
      _programmerReconnexion();
      return;
    }
    _canal = canal;
    canal.stream.listen(
      _recevoir,
      onError: (_) => _perdreConnexion(),
      onDone: () => _perdreConnexion(codeFermeture: canal.closeCode),
      cancelOnError: true,
    );
    _connecte = true;
    _tentative = 0;
    _etatController.add(true);
    for (final conversationId in _abonnements) {
      _envoyerAbonnement(conversationId);
    }
  }

  /// S'abonne à une conversation : ses nouveaux messages arrivent sur
  /// [messages]. L'abonnement survit aux reconnexions.
  void abonner(String conversationId) {
    _abonnements.add(conversationId);
    if (_connecte) _envoyerAbonnement(conversationId);
  }

  /// Ne plus recevoir les messages d'une conversation.
  void desabonner(String conversationId) {
    _abonnements.remove(conversationId);
  }

  void _envoyerAbonnement(String conversationId) {
    try {
      _canal?.sink.add(jsonEncode({
        'type': 'subscribe',
        'conversation_id': conversationId,
      }));
    } catch (_) {
      // L'envoi échouera à nouveau à la reconnexion.
    }
  }

  void _recevoir(dynamic donnees) {
    final objet = decoderMessage(donnees);
    if (objet != null) _messagesController.add(objet);
  }

  /// Décode une trame entrante en message, ou null si ce n'en est pas
  /// une (trame de présence, accusé, bruit).
  static MessageMessagerie? decoderMessage(dynamic donnees) {
    if (donnees is! String) return null;
    final dynamic json;
    try {
      json = jsonDecode(donnees);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final Map<String, dynamic>? contenu;
    if (json['type'] == 'message' && json['message'] is Map) {
      contenu = json['message'] as Map<String, dynamic>;
    } else if (json['conversation_id'] is String &&
        json['content'] is String) {
      contenu = json;
    } else {
      return null;
    }
    try {
      return MessageMessagerie.fromJson(contenu);
    } catch (_) {
      return null;
    }
  }

  void _perdreConnexion({int? codeFermeture}) {
    if (!_connecte && _canal == null) return;
    _connecte = false;
    _canal = null;
    if (codeFermeture == 1008) {
      // Jeton invalide ou rôle refusé : le serveur l'a dit, toute
      // reconnexion serait vouée à l'échec, on ne reprogramme rien.
      _refusAuthentification = true;
      debugPrint(
        '[Messagerie] WebSocket fermé en 1008, pas de reconnexion.',
      );
    }
    if (!_ferme) {
      _etatController.add(false);
      _programmerReconnexion();
    }
  }

  void _programmerReconnexion() {
    if (_refusAuthentification) return;
    _minuteurReconnexion?.cancel();
    _tentative++;
    _minuteurReconnexion = Timer(
      delaiReconnexion(_tentative),
      connecter,
    );
  }

  /// Ferme la connexion et annule les reconnexions programmées.
  Future<void> deconnecter() async {
    _ferme = true;
    _minuteurReconnexion?.cancel();
    _minuteurReconnexion = null;
    try {
      await _canal?.sink.close();
    } catch (_) {
      // Canal déjà fermé.
    }
    _canal = null;
    _connecte = false;
    await _messagesController.close();
    await _etatController.close();
  }
}
