import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/messagerie.dart';

/// Dernière lecture locale par conversation (T-Msg-1).
///
/// Le serveur T-Msg-0 ne renvoie pas de nombre de non lus et n'expose
/// pas de route pour marquer une conversation comme lue (la colonne
/// `last_read_at` existe en base, sans route). Le client persiste donc
/// la date de sa dernière lecture sur l'appareil, dans le stockage
/// sécurisé, et en déduit les non lus. Un compteur serveur exact
/// viendra avec la tranche serveur suivante ; en attendant, le badge
/// ne compte que ce que le client a vu passer.
///
/// Singleton : une seule carte en mémoire, partagée par la liste, la
/// conversation, l'accueil et la carte Modules. Les lectures et
/// écritures du stockage sont protégées : un échec (tests, appareil
/// sans stockage sécurisé) ne bloque jamais l'écran, la carte en
/// mémoire reste la référence.
class MessagerieLectureService {
  static final MessagerieLectureService instance =
      MessagerieLectureService._();

  MessagerieLectureService._() : _stockage = const FlutterSecureStorage();

  /// Constructeur de test : stockage injecté, même comportement.
  MessagerieLectureService.pourTests([FlutterSecureStorage? stockage])
      : _stockage = stockage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _stockage;
  final Map<String, DateTime> _lus = {};
  bool _charge = false;

  static const _prefixeCle = 'messagerie_lu_';

  /// Charge les lectures persistées (une seule fois). Jamais d'erreur.
  /// Le délai protège l'écran si le stockage ne répond pas (en test,
  /// l'appel ne se résout jamais sans greffon) : passé ce délai, on
  /// repart d'une carte vide pour la session, sans bloquer l'écran.
  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final toutes = await _stockage
          .readAll()
          .timeout(const Duration(seconds: 2));
      for (final entree in toutes.entries) {
        if (!entree.key.startsWith(_prefixeCle)) continue;
        final date = DateTime.tryParse(entree.value);
        if (date != null) {
          _lus[entree.key.substring(_prefixeCle.length)] = date;
        }
      }
    } catch (e) {
      // Sans stockage lisible, on repart d'une carte vide.
      debugPrint('[Messagerie] Lectures sécurisées illisibles : $e');
    }
  }

  /// Date de dernière lecture d'une conversation (null = jamais lue).
  DateTime? luLe(String conversationId) => _lus[conversationId];

  /// Marque une conversation comme lue à [date] (par défaut maintenant).
  Future<void> marquerLu(String conversationId, [DateTime? date]) async {
    final moment = date ?? DateTime.now();
    _lus[conversationId] = moment;
    try {
      // Sans délai : l'appelant n'attend pas l'écriture, un stockage
      // qui ne répond pas laisse juste une future en suspens.
      await _stockage.write(
        key: '$_prefixeCle$conversationId',
        value: moment.toIso8601String(),
      );
    } catch (e) {
      // La carte en mémoire reste valable pour la session.
      debugPrint(
        '[Messagerie] Écriture de la lecture sécurisée échouée : $e',
      );
    }
  }

  /// Nombre de conversations avec un message plus récent que la
  /// dernière lecture : le total affiché en badge sur l'accueil et sur
  /// la carte Modules. Ne demande aucun chargement de messages.
  int compterConversationsNonLues(
    List<ConversationMessagerie> conversations,
  ) {
    var total = 0;
    for (final conversation in conversations) {
      final dernier = conversation.lastMessageAt;
      if (dernier == null) continue;
      final lu = _lus[conversation.id];
      if (lu == null || dernier.isAfter(lu)) total++;
    }
    return total;
  }

  /// Remise à zéro (tests uniquement).
  void reinitialiserPourTests() {
    _lus.clear();
    _charge = false;
  }
}
