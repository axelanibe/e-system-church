import '../utils/format.dart';

/// Sauvegarde chiffrée de l'église (`sauvegardes`, T11).
class Sauvegarde {
  final String id;
  final int tailleOctets;
  final String empreinte;
  final int nbTables;
  final List<String> tables;
  final String statut; // ok | restauree
  final DateTime? createdAt;

  const Sauvegarde({
    required this.id,
    required this.tailleOctets,
    required this.empreinte,
    required this.nbTables,
    required this.tables,
    required this.statut,
    this.createdAt,
  });

  String get statutLabel => statut == 'restauree' ? 'Restaurée' : 'Disponible';

  String get tailleLabel {
    if (tailleOctets < 1024) return '$tailleOctets o';
    if (tailleOctets < 1024 * 1024) {
      return '${(tailleOctets / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(tailleOctets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  factory Sauvegarde.fromJson(Map<String, dynamic> json) => Sauvegarde(
        id: json['id'] as String,
        tailleOctets: json['taille_octets'] as int? ?? 0,
        empreinte: json['empreinte'] as String? ?? '',
        nbTables: json['nb_tables'] as int? ?? 0,
        tables: (json['tables'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        statut: json['statut'] as String? ?? 'ok',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Notification de la boîte d'envoi (`notifications`, T11). Aucun
/// fournisseur n'est branché : l'envoi reste en attente tant qu'Axel
/// n'a pas choisi de fournisseur.
class NotificationConfiance {
  final String id;
  final String canal; // push | sms
  final String titre;
  final String message;
  final String statut; // en_attente | envoyee | echouee | non_configurée
  final String? erreur;
  final DateTime? createdAt;
  final DateTime? envoyeeAt;

  const NotificationConfiance({
    required this.id,
    required this.canal,
    required this.titre,
    required this.message,
    required this.statut,
    this.erreur,
    this.createdAt,
    this.envoyeeAt,
  });

  String get statutLabel => switch (statut) {
        'envoyee' => 'Envoyée',
        'echouee' => 'Échec',
        'non_configurée' => 'Non configurée',
        _ => 'En attente',
      };

  String get canalLabel => canal == 'sms' ? 'SMS' : 'Push';

  factory NotificationConfiance.fromJson(Map<String, dynamic> json) =>
      NotificationConfiance(
        id: json['id'] as String,
        canal: json['canal'] as String? ?? 'push',
        titre: json['titre'] as String? ?? '',
        message: json['message'] as String? ?? '',
        statut: json['statut'] as String? ?? 'en_attente',
        erreur: json['erreur'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
        envoyeeAt: parseDate(json['envoyee_at'] as String?),
      );
}

/// Résultat de la vérification de la chaîne d'audit.
class VerificationAudit {
  final bool ok;
  final int total;
  final int verifies;
  final String? ruptureId;

  const VerificationAudit({
    required this.ok,
    required this.total,
    required this.verifies,
    this.ruptureId,
  });

  factory VerificationAudit.fromJson(Map<String, dynamic> json) =>
      VerificationAudit(
        ok: json['ok'] as bool? ?? false,
        total: json['total'] as int? ?? 0,
        verifies: json['verifies'] as int? ?? 0,
        ruptureId: json['ruptureId'] as String?,
      );
}

/// Lecture sensible journalisée (`consultations_sensibles`, US17).
class ConsultationSensible {
  final String id;
  final String? userNom;
  final String ressource;
  final String? ressourceId;
  final String? ressourceNom;
  final String action;
  final DateTime? createdAt;

  const ConsultationSensible({
    required this.id,
    this.userNom,
    required this.ressource,
    this.ressourceId,
    this.ressourceNom,
    required this.action,
    this.createdAt,
  });

  String get ressourceLabel => switch (ressource) {
        'membre' => 'Fiche membre',
        _ => ressource,
      };

  factory ConsultationSensible.fromJson(Map<String, dynamic> json) =>
      ConsultationSensible(
        id: json['id'] as String,
        userNom: json['user_nom'] as String?,
        ressource: json['ressource'] as String? ?? '',
        ressourceId: json['ressource_id'] as String?,
        ressourceNom: json['ressource_nom'] as String?,
        action: json['action'] as String? ?? 'lecture',
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Action mise en file hors ligne (`actions_hors_ligne`, T11).
class ActionHorsLigne {
  final String id;
  final String typeAction; // presence.pointer | contribution.creer
  final Map<String, dynamic> charge;
  final String cleClient;
  final String statut; // en_attente | rejouee | echouee
  final String? erreur;
  final DateTime? createdAt;
  final DateTime? rejoueAt;
  final bool dejaEnregistree;

  const ActionHorsLigne({
    required this.id,
    required this.typeAction,
    required this.charge,
    required this.cleClient,
    required this.statut,
    this.erreur,
    this.createdAt,
    this.rejoueAt,
    this.dejaEnregistree = false,
  });

  String get typeLabel => switch (typeAction) {
        'presence.pointer' => 'Pointage',
        'contribution.creer' => 'Contribution',
        _ => typeAction,
      };

  String get statutLabel => switch (statut) {
        'rejouee' => 'Rejouée',
        'echouee' => 'En échec',
        _ => 'En attente',
      };

  factory ActionHorsLigne.fromJson(Map<String, dynamic> json) =>
      ActionHorsLigne(
        id: json['id'] as String,
        typeAction: json['type_action'] as String? ?? '',
        charge: (json['charge'] as Map<String, dynamic>?) ?? {},
        cleClient: json['cle_client'] as String? ?? '',
        statut: json['statut'] as String? ?? 'en_attente',
        erreur: json['erreur'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
        rejoueAt: parseDate(json['rejoue_at'] as String?),
        dejaEnregistree: json['deja_enregistree'] as bool? ?? false,
      );
}

/// Résultat d'un rejeu de la file hors ligne.
class RejeuFile {
  final int rejouees;
  final int echouees;

  const RejeuFile({required this.rejouees, required this.echouees});

  factory RejeuFile.fromJson(Map<String, dynamic> json) => RejeuFile(
        rejouees: json['rejouees'] as int? ?? 0,
        echouees: json['echouees'] as int? ?? 0,
      );
}

/// Paramètres de confiance de l'église (jamais la clé en clair).
class ParametresConfiance {
  final String sauvegardeFrequence; // jamais | quotidienne | hebdomadaire
  final String sauvegardeHeure;
  final DateTime? sauvegardeAutoDerniereAt;
  final String? notificationFournisseur;
  final int notificationPlafondMensuel;
  final bool notificationsActives;
  final bool notificationsConfigurees;

  const ParametresConfiance({
    required this.sauvegardeFrequence,
    required this.sauvegardeHeure,
    this.sauvegardeAutoDerniereAt,
    this.notificationFournisseur,
    required this.notificationPlafondMensuel,
    required this.notificationsActives,
    required this.notificationsConfigurees,
  });

  String get frequenceLabel => switch (sauvegardeFrequence) {
        'quotidienne' => 'Quotidienne',
        'hebdomadaire' => 'Hebdomadaire',
        _ => 'Jamais',
      };

  factory ParametresConfiance.fromJson(Map<String, dynamic> json) =>
      ParametresConfiance(
        sauvegardeFrequence:
            json['sauvegarde_frequence'] as String? ?? 'jamais',
        sauvegardeHeure: json['sauvegarde_heure'] as String? ?? '03:00',
        sauvegardeAutoDerniereAt:
            parseDate(json['sauvegarde_auto_derniere_at'] as String?),
        notificationFournisseur:
            json['notification_fournisseur'] as String?,
        notificationPlafondMensuel:
            json['notification_plafond_mensuel'] as int? ?? 0,
        notificationsActives:
            json['notifications_actives'] as bool? ?? false,
        notificationsConfigurees:
            json['notifications_configurees'] as bool? ?? false,
      );
}

/// Démarrage de la 2FA : URI otpauth à scanner en QR, secret renvoyé
/// une seule fois (jamais stocké en clair, jamais renvoyé ensuite).
class Demarrage2fa {
  final String otpauthUri;
  final String secret;

  const Demarrage2fa({required this.otpauthUri, required this.secret});

  factory Demarrage2fa.fromJson(Map<String, dynamic> json) => Demarrage2fa(
        otpauthUri: json['otpauth_uri'] as String? ?? '',
        secret: json['secret'] as String? ?? '',
      );
}
