/// Modèles de la messagerie (tranche T-Msg-1, spécification v2).
///
/// Contrats du serveur (T-Msg-0, `server/src/routes/messagerie.ts`) :
/// - `GET /messagerie/conversations` renvoie `id, type, title,
///   created_at, last_message_at` : ni participants, ni aperçu du dernier
///   message, ni nombre de non lus. L'aperçu et les non lus sont donc
///   calculés côté client, à partir des messages lus (voir
///   [MessagerieLectureService]) ; une route serveur qui les renvoie
///   directement reste à construire (tranche suivante).
/// - `GET /messagerie/conversations/:id/messages` renvoie les messages
///   en ordre chronologique (`limit` 100 maximum).
/// - Seul le type de message `text` existe en T-Msg-1.
library;

import 'member.dart';

/// Types de conversation créables en T-Msg-1. La pastorale
/// confidentielle et le canal de modération viennent plus tard : le
/// serveur les accepte, l'application ne les propose pas.
const typesConversationMessagerie = [
  'directe',
  'groupe_departement',
  'groupe_eglise',
];

/// Libellé court d'un type de conversation.
String libelleTypeConversation(String type) {
  switch (type) {
    case 'directe':
      return 'Directe';
    case 'groupe_departement':
      return 'Groupe';
    case 'groupe_eglise':
      return 'Canal d’église';
    case 'pastorale':
      return 'Pastorale';
    case 'moderation':
      return 'Modération';
    default:
      return 'Conversation';
  }
}

/// Une conversation de messagerie, telle que renvoyée par le serveur.
/// [dernierMessage] et [nonLus] sont calculés côté client (voir
/// l'en-tête du fichier) ; [reponsesDesactivees] est lu quand le
/// serveur le renvoie (canal d'annonces, réponses désactivables) : la
/// colonne n'existe pas encore côté serveur en T-Msg-0, la valeur
/// reste donc fausse jusqu'à la tranche serveur correspondante.
class ConversationMessagerie {
  final String id;
  final String type;
  final String? title;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;

  /// Contenu du dernier message, calculé côté client (null tant que
  /// les messages n'ont pas été lus).
  final String? dernierMessage;

  /// Nombre de messages non lus, calculé côté client.
  final int nonLus;

  /// Réponses désactivées (canal d'église) : la saisie est alors
  /// masquée et une note s'affiche.
  final bool reponsesDesactivees;

  const ConversationMessagerie({
    required this.id,
    required this.type,
    this.title,
    this.createdAt,
    this.lastMessageAt,
    this.dernierMessage,
    this.nonLus = 0,
    this.reponsesDesactivees = false,
  });

  factory ConversationMessagerie.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur as String);
    }

    return ConversationMessagerie(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      createdAt: lireDate(json['created_at']),
      lastMessageAt: lireDate(json['last_message_at']),
      reponsesDesactivees:
          json['reponses_desactivees'] as bool? ??
          json['replies_disabled'] as bool? ??
          false,
    );
  }

  ConversationMessagerie copyWith({
    String? dernierMessage,
    int? nonLus,
    bool? reponsesDesactivees,
  }) {
    return ConversationMessagerie(
      id: id,
      type: type,
      title: title,
      createdAt: createdAt,
      lastMessageAt: lastMessageAt,
      dernierMessage: dernierMessage ?? this.dernierMessage,
      nonLus: nonLus ?? this.nonLus,
      reponsesDesactivees:
          reponsesDesactivees ?? this.reponsesDesactivees,
    );
  }

  /// Vrai pour un groupe (département ou église), faux pour une directe.
  bool get estGroupe =>
      type == 'groupe_departement' || type == 'groupe_eglise';
}

/// Un message texte d'une conversation.
class MessageMessagerie {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String type;
  final DateTime? createdAt;

  const MessageMessagerie({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.type = 'text',
    this.createdAt,
  });

  factory MessageMessagerie.fromJson(Map<String, dynamic> json) {
    return MessageMessagerie(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'type': type,
    'created_at': createdAt?.toIso8601String(),
  };
}

/// Nombre de messages non lus : envoyés par un autre membre, après
/// la dernière lecture [luLe] (null = jamais lu, tout compte).
/// Les messages sans date ne comptent pas, ils sont déjà affichés.
int compterMessagesNonLus(
  List<MessageMessagerie> messages,
  String? monMembreId,
  DateTime? luLe,
) {
  var total = 0;
  for (final message in messages) {
    if (monMembreId != null && message.senderId == monMembreId) continue;
    final date = message.createdAt;
    if (date == null) continue;
    if (luLe == null || date.isAfter(luLe)) total++;
  }
  return total;
}

/// Heure courte d'une date : « 14:32 » aujourd'hui, « 12/11 » sinon.
String heureCourteConversation(DateTime? date) {
  if (date == null) return '';
  final locale = date.toLocal();
  final maintenant = DateTime.now();
  final hh = locale.hour.toString().padLeft(2, '0');
  final mm = locale.minute.toString().padLeft(2, '0');
  if (locale.year == maintenant.year &&
      locale.month == maintenant.month &&
      locale.day == maintenant.day) {
    return '$hh:$mm';
  }
  return '${locale.day.toString().padLeft(2, '0')}/'
      '${locale.month.toString().padLeft(2, '0')}';
}

/// Identifiant de ma fiche membre, retrouvé par mon adresse e-mail
/// dans la liste des membres de l'église. Le serveur ne renvoie pas
/// mon `member_id` au client (`GET /moi/eglise` ne le contient pas) :
/// la comparaison par e-mail est le moyen disponible en T-Msg-1 pour
/// distinguer mes messages de ceux des autres. Null si aucune fiche
/// ne porte mon e-mail (compte sans fiche membre liée).
String? trouverMonMembreId(List<Member> membres, String? monEmail) {
  if (monEmail == null || monEmail.isEmpty) return null;
  final email = monEmail.toLowerCase();
  for (final membre in membres) {
    if (membre.email?.toLowerCase() == email) return membre.id;
  }
  return null;
}
