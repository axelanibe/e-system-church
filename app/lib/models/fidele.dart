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
