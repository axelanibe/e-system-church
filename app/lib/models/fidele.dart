import 'auth.dart';
import 'church.dart';
import 'member.dart';

/// Profil fidèle (`GET /moi`) : utilisateur + église active + rôle +
/// fiche membre liée (si le compte est lié à un membre).
class FideleProfil {
  final AppUser user;
  final Church church;
  final String role;
  final String? memberId;
  final String? matricule;

  const FideleProfil({
    required this.user,
    required this.church,
    required this.role,
    this.memberId,
    this.matricule,
  });

  factory FideleProfil.fromJson(Map<String, dynamic> json) => FideleProfil(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        church: Church.fromJson(json['church'] as Map<String, dynamic>),
        role: json['role'] as String,
        memberId: (json['user'] as Map<String, dynamic>)['member_id'] as String?,
        matricule:
            (json['user'] as Map<String, dynamic>)['matricule'] as String?,
      );
}

/// Demande de liaison compte ↔ fiche membre (`GET /membres/demandes-liaison`).
class DemandeLiaison {
  final String id;
  final String status; // en_attente
  final String memberId;
  final String matricule;
  final String membreNom;
  final String? membreEmail;
  final String userId;
  final String userEmail;
  final String userNom;
  final DateTime? createdAt;

  const DemandeLiaison({
    required this.id,
    required this.status,
    required this.memberId,
    required this.matricule,
    required this.membreNom,
    this.membreEmail,
    required this.userId,
    required this.userEmail,
    required this.userNom,
    this.createdAt,
  });

  factory DemandeLiaison.fromJson(Map<String, dynamic> json) => DemandeLiaison(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'en_attente',
        memberId: json['member_id'] as String,
        matricule: json['matricule'] as String,
        membreNom: json['membre_nom'] as String,
        membreEmail: json['membre_email'] as String?,
        userId: json['user_id'] as String,
        userEmail: json['user_email'] as String,
        userNom: json['user_nom'] as String,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );
}

/// Résultat de `POST /auth/inscription-fidele` : lié immédiatement
/// (avec session) ou demande en attente de validation par l'admin.
class FideleInscriptionResult {
  final bool lie;
  final AuthResult? auth;
  final String message;
  final String? demandeId;
  /// Matricule attribué automatiquement (inscription par code d'église).
  final String? matricule;

  const FideleInscriptionResult({
    required this.lie,
    this.auth,
    required this.message,
    this.demandeId,
    this.matricule,
  });

  factory FideleInscriptionResult.fromJson(Map<String, dynamic> json) {
    final lie = json['lie'] as bool? ?? false;
    return FideleInscriptionResult(
      lie: lie,
      auth: lie ? AuthResult.fromJson(json) : null,
      message: json['message'] as String? ?? '',
      demandeId: json['demande_id'] as String?,
      matricule: json['matricule'] as String?,
    );
  }
}

/// Carte de membre du fidèle (`GET /moi/carte`) : fiche membre + église.
/// Affichée avec la carte existante (MemberDetailScreen) — sans la reconstruire.
class MaCarte {
  final Member member;
  final Church church;

  const MaCarte({required this.member, required this.church});

  factory MaCarte.fromJson(Map<String, dynamic> json) => MaCarte(
        member: Member.fromJson(json['member'] as Map<String, dynamic>),
        church: Church.fromJson(json['church'] as Map<String, dynamic>),
      );
}

/// Demande de rendez-vous du fidèle auprès de son pasteur
/// (`GET` et `POST /moi/rendez-vous`, migration 022) : date souhaitée
/// au format AAAA-MM-JJ, créneau à compléter, motif. Le statut est
/// géré par l'église ; la gestion côté admin reste la tranche T6.
class RendezVous {
  final String id;
  final String? memberId; // côté admin (GET /rendez-vous, T6)
  final String? membreNom; // côté admin (joint par le serveur)
  final String? membreMatricule; // côté admin (joint par le serveur)
  final String dateSouhaitee; // AAAA-MM-JJ
  final String? creneau;
  final String motif;
  final String statut; // en_attente | confirme | refuse | annule
  final DateTime? createdAt;

  const RendezVous({
    required this.id,
    this.memberId,
    this.membreNom,
    this.membreMatricule,
    required this.dateSouhaitee,
    this.creneau,
    required this.motif,
    this.statut = 'en_attente',
    this.createdAt,
  });

  factory RendezVous.fromJson(Map<String, dynamic> json) {
    final brute = json['date_souhaitee'] as String? ?? '';
    final date = brute.length >= 10 ? brute.substring(0, 10) : brute;
    return RendezVous(
      id: json['id'] as String,
      memberId: json['member_id'] as String?,
      membreNom: json['membre_nom'] as String?,
      membreMatricule: json['membre_matricule'] as String?,
      dateSouhaitee: date,
      creneau: json['creneau'] as String?,
      motif: json['motif'] as String? ?? '',
      statut: json['statut'] as String? ?? 'en_attente',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }

  /// Date souhaitée, sous forme de date locale (sans heure).
  DateTime? get date => DateTime.tryParse(dateSouhaitee);
}

/// Message du fil privé du fidèle (`GET /moi/messages`, migration 020) :
/// écrit par le fidèle (`membre`) ou par son église (`eglise`), dans
/// l'application, pas par e-mail.
class MessageFidele {
  final String id;
  final String auteur; // membre | eglise
  final String corps;
  final DateTime? createdAt;

  const MessageFidele({
    required this.id,
    required this.auteur,
    required this.corps,
    this.createdAt,
  });

  factory MessageFidele.fromJson(Map<String, dynamic> json) =>
      MessageFidele(
        id: json['id'] as String,
        auteur: json['auteur'] as String? ?? 'membre',
        corps: json['corps'] as String? ?? '',
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );

  bool get deMoi => auteur == 'membre';
}

/// Fil privé du fidèle : nom de l'église destinataire (église mère ou
/// tutelle) et messages, du plus ancien au plus récent.
class FilMessages {
  final String? destinataireNom;
  final List<MessageFidele> messages;

  const FilMessages({this.destinataireNom, required this.messages});

  factory FilMessages.fromJson(Map<String, dynamic> json) => FilMessages(
        destinataireNom: json['destinataire_nom'] as String?,
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((e) => MessageFidele.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
