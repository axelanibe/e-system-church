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
///
/// T-Msg-4 : [editedAt] est renseigné quand l'auteur a modifié le
/// message (l'écran affiche « (modifié) ») ; [deletedAt] quand il a
/// été supprimé doucement — le serveur renvoie alors le contenu
/// « Message supprimé » à la place du contenu d'origine, jamais de
/// suppression dure.
class MessageMessagerie {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String type;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  const MessageMessagerie({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.type = 'text',
    this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  factory MessageMessagerie.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur as String);
    }

    return MessageMessagerie(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
      createdAt: lireDate(json['created_at']),
      editedAt: lireDate(json['edited_at']),
      deletedAt: lireDate(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'type': type,
    'created_at': createdAt?.toIso8601String(),
    'edited_at': editedAt?.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  /// Vrai quand le message a été supprimé (doucement).
  bool get supprime => deletedAt != null;

  /// Vrai quand le message a été modifié par son auteur.
  bool get estModifie => editedAt != null;

  MessageMessagerie copyWith({
    String? content,
    DateTime? editedAt,
    DateTime? deletedAt,
  }) {
    return MessageMessagerie(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content ?? this.content,
      type: type,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Motifs de signalement, enum de reports.reason (migration 034).
/// Les 3 motifs propres à Connexion Prophétique (erreur doctrinale,
/// trafic d'influence, mauvaise gestion des finances) n'y figurent
/// pas : les ajouter exigerait une migration qui élargit le CHECK.
const motifsSignalement = [
  'harassment',
  'hate_speech',
  'threat',
  'misinformation',
  'spam',
  'child_safety',
  'other',
];

/// Libellé court d'un motif de signalement.
String libelleMotifSignalement(String motif) {
  switch (motif) {
    case 'harassment':
      return 'Harcèlement';
    case 'hate_speech':
      return 'Propos haineux';
    case 'threat':
      return 'Menace';
    case 'misinformation':
      return 'Informations trompeuses';
    case 'spam':
      return 'Spam';
    case 'child_safety':
      return 'Sécurité d’un enfant';
    case 'other':
    default:
      return 'Autre';
  }
}

/// Destinataires d'un signalement : les modérateurs de mon église,
/// ou l'église mère. La sécurité d'un enfant part toujours vers le
/// référent protection de l'enfance, quel que soit ce choix.
const destinatairesSignalement = ['local', 'mother'];

String libelleDestinataireSignalement(String destinataire) {
  switch (destinataire) {
    case 'mother':
      return 'Église mère';
    default:
      return 'Modérateurs de mon église';
  }
}

/// Phrase de visibilité, affichée avant l'envoi du signalement.
/// Le rapporteur est informé de qui verra son signalement, avant
/// d'envoyer ; la personne signalée ne voit jamais son nom.
String phraseVisibiliteSignalement(String destinataire, String motif) {
  if (motif == 'child_safety') {
    return 'Ce signalement est transmis au référent protection de '
        'l’enfance, hors du circuit ordinaire, quel que soit le '
        'destinataire choisi. La personne signalée ne verra jamais '
        'votre nom.';
  }
  if (destinataire == 'mother') {
    return 'L’église mère verra votre nom. Les modérateurs de votre '
        'église sauront seulement qu’un signalement a été transmis, '
        'sans en recevoir le contenu. La personne signalée ne verra '
        'jamais votre nom.';
  }
  return 'Les modérateurs de votre église verront votre nom. La '
      'personne signalée ne verra jamais votre nom.';
}

/// Statuts d'un signalement, enum de reports.status (migration 034).
String libelleStatutSignalement(String statut) {
  switch (statut) {
    case 'pending':
      return 'En attente';
    case 'in_review':
      return 'En cours';
    case 'resolved':
      return 'Résolu';
    case 'dismissed':
      return 'Rejeté';
    case 'escalated':
      return 'Transmis';
    case 'appealed':
      return 'Contesté';
    default:
      return statut;
  }
}

/// Actions de modération. Chaque action exige une note motivée.
const actionsModeration = ['rejeter', 'avertir', 'sourdine', 'suspendre'];

String libelleActionModeration(String action) {
  switch (action) {
    case 'rejeter':
      return 'Rejeter';
    case 'avertir':
      return 'Avertir';
    case 'sourdine':
      return 'Mettre en sourdine';
    case 'suspendre':
      return 'Suspendre la messagerie';
    default:
      return action;
  }
}

/// Durées de sourdine ou de suspension, en heures, proposées par
/// l'écran de modération. Le serveur applique la durée choisie.
const dureesModerationHeures = [24, 168, 720];

String libelleDureeModeration(int heures) {
  switch (heures) {
    case 24:
      return '24 heures';
    case 168:
      return '7 jours';
    case 720:
      return '30 jours';
    default:
      return '$heures heures';
  }
}

/// Délai de recours : 15 jours pour contester une sanction, 30 jours
/// pour y répondre. Le délai de réponse relève du serveur ; le client
/// n'applique que le délai de contestation.
const delaiRecoursJours = 15;
const delaiReponseRecoursJours = 30;

/// Vrai si une sanction du [dateSanction] peut encore être contestée
/// à [maintenant] (15 jours).
bool peutContester(DateTime dateSanction, [DateTime? maintenant]) {
  final maintenantReel = maintenant ?? DateTime.now();
  return maintenantReel.isBefore(
    dateSanction.add(const Duration(days: delaiRecoursJours)),
  );
}

/// Jours entiers restants pour contester, 0 quand le délai est
/// dépassé.
int joursRestantsRecours(DateTime dateSanction, [DateTime? maintenant]) {
  final maintenantReel = maintenant ?? DateTime.now();
  final reste = dateSanction
      .add(const Duration(days: delaiRecoursJours))
      .difference(maintenantReel);
  if (reste.isNegative) return 0;
  return reste.inDays;
}

/// Un signalement, tel que renvoyé par le serveur. [evidence] est la
/// preuve figée au moment du signalement (contenu, auteur, date) ;
/// [escalade] marque un signalement transmis par une église fille,
/// en lecture seule, sans nom de rapporteur.
class Signalement {
  final String id;
  final String targetType;
  final String targetId;
  final String motif;
  final String? description;
  final Map<String, dynamic>? evidence;
  final String routedTo;
  final String? routedToChurchId;
  final String statut;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? resolutionNotes;
  final String? rapporteurNom;
  final bool escalade;
  final List<ModerationAction> actions;
  final List<RecoursMessagerie> recours;

  const Signalement({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.motif,
    this.description,
    this.evidence,
    required this.routedTo,
    this.routedToChurchId,
    required this.statut,
    this.createdAt,
    this.resolvedAt,
    this.resolutionNotes,
    this.rapporteurNom,
    this.escalade = false,
    this.actions = const [],
    this.recours = const [],
  });

  factory Signalement.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur.toString());
    }

    List<ModerationAction> lireActions(Object? valeur) {
      if (valeur is! List) return const [];
      return valeur
          .whereType<Map<String, dynamic>>()
          .map(ModerationAction.fromJson)
          .toList();
    }

    List<RecoursMessagerie> lireRecours(Object? valeur) {
      if (valeur is! List) return const [];
      return valeur
          .whereType<Map<String, dynamic>>()
          .map(RecoursMessagerie.fromJson)
          .toList();
    }

    return Signalement(
      id: (json['id'] ?? '').toString(),
      targetType: (json['target_type'] ?? 'message').toString(),
      targetId: (json['target_id'] ?? '').toString(),
      motif: (json['reason'] ?? json['motif'] ?? 'other').toString(),
      description: json['description'] as String?,
      evidence: json['evidence_snapshot'] is Map<String, dynamic>
          ? json['evidence_snapshot'] as Map<String, dynamic>
          : null,
      routedTo: (json['routed_to'] ?? 'local').toString(),
      routedToChurchId: json['routed_to_church_id'] as String?,
      statut: (json['status'] ?? json['statut'] ?? 'pending').toString(),
      createdAt: lireDate(json['created_at']),
      resolvedAt: lireDate(json['resolved_at']),
      resolutionNotes: json['resolution_notes'] as String?,
      rapporteurNom: json['reporter_nom'] as String?,
      escalade: json['escalade'] as bool? ?? false,
      actions: lireActions(json['actions']),
      recours: lireRecours(json['recours']),
    );
  }

  /// Contenu figé au moment du signalement (message, ou titre de la
  /// conversation signalée).
  String get evidenceContenu =>
      ((evidence?['content'] ?? evidence?['title'] ?? '')).toString();

  /// Auteur du contenu figé, quand le serveur le renvoie.
  String get evidenceAuteur =>
      ((evidence?['sender_nom'] ?? '')).toString();

  /// Date du contenu figé, quand le serveur la renvoie.
  DateTime? get evidenceDate {
    final brut = evidence?['created_at'];
    if (brut == null) return null;
    return DateTime.tryParse(brut.toString());
  }
}

/// Une action de modération posée sur un signalement.
class ModerationAction {
  final String id;
  final String signalementId;
  final String action;
  final String? notes;
  final DateTime? date;

  const ModerationAction({
    required this.id,
    required this.signalementId,
    required this.action,
    this.notes,
    this.date,
  });

  factory ModerationAction.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur.toString());
    }

    return ModerationAction(
      id: (json['id'] ?? '').toString(),
      signalementId:
          (json['report_id'] ?? json['signalement_id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      notes: json['notes'] as String?,
      date: lireDate(json['created_at'] ?? json['date']),
    );
  }
}

/// Un recours contre une action de modération.
class RecoursMessagerie {
  final String id;
  final String signalementId;
  final String? actionId;
  final String? motif;
  final String statut;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final DateTime? repondreAvant;

  const RecoursMessagerie({
    required this.id,
    required this.signalementId,
    this.actionId,
    this.motif,
    required this.statut,
    this.createdAt,
    this.resolvedAt,
    this.repondreAvant,
  });

  factory RecoursMessagerie.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur.toString());
    }

    return RecoursMessagerie(
      id: (json['id'] ?? '').toString(),
      signalementId:
          (json['report_id'] ?? json['signalement_id'] ?? '').toString(),
      actionId:
          (json['moderation_action_id'] ?? json['action_id'] ?? '')
              .toString(),
      motif: json['reason'] as String?,
      statut: (json['status'] ?? json['statut'] ?? 'pending').toString(),
      createdAt: lireDate(json['created_at']),
      resolvedAt: lireDate(json['resolved_at']),
      repondreAvant: lireDate(json['repondre_avant']),
    );
  }

  /// Vrai tant que le recours est en attente de réponse.
  bool get enCours => statut == 'pending' || statut == 'in_review';
}

/// Une sanction qui me concerne, telle que renvoyée par le serveur,
/// avec le délai de recours restant.
class SanctionMessagerie {
  final String id;
  final String signalementId;
  final String action;
  final String? notes;
  final DateTime? date;
  final DateTime? contesterAvant;
  final bool contestable;
  final bool appelEnCours;

  const SanctionMessagerie({
    required this.id,
    required this.signalementId,
    required this.action,
    this.notes,
    this.date,
    this.contesterAvant,
    this.contestable = false,
    this.appelEnCours = false,
  });

  factory SanctionMessagerie.fromJson(Map<String, dynamic> json) {
    DateTime? lireDate(Object? valeur) {
      if (valeur == null) return null;
      return DateTime.tryParse(valeur.toString());
    }

    final date = lireDate(json['created_at'] ?? json['date']);
    final contesterAvant = lireDate(json['contester_avant']);
    final contestable = json['contestable'] as bool? ??
        (date != null && peutContester(date));

    return SanctionMessagerie(
      id: (json['action_id'] ?? json['id'] ?? '').toString(),
      signalementId:
          (json['report_id'] ?? json['signalement_id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      notes: json['notes'] as String?,
      date: date,
      contesterAvant: contesterAvant,
      contestable: contestable,
      appelEnCours: json['appel_en_cours'] as bool? ?? false,
    );
  }

  /// Jours entiers restants pour contester, 0 quand le délai est
  /// dépassé ou qu'un recours est déjà en cours.
  int get joursRestants {
    if (!contestable || date == null) return 0;
    return joursRestantsRecours(date!);
  }
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
