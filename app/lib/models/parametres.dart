import '../utils/format.dart';

/// Paramètres d'une église (`GET /parametres` : ligne `eglise_parametres`
/// jointe au nom, au code et à la ville de l'église).
class EgliseParametres {
  final String? adresse;
  final String? ville;
  final String? telephone;
  final String? email;
  final String? logoUrl;
  final String? waveNumero;
  final String? orangeNumero;
  final String? mtnNumero;
  final String? devise;
  final String? fuseauHoraire;
  final String? egliseNom;
  final String? egliseCode;

  const EgliseParametres({
    this.adresse,
    this.ville,
    this.telephone,
    this.email,
    this.logoUrl,
    this.waveNumero,
    this.orangeNumero,
    this.mtnNumero,
    this.devise,
    this.fuseauHoraire,
    this.egliseNom,
    this.egliseCode,
  });

  factory EgliseParametres.fromJson(Map<String, dynamic> json) =>
      EgliseParametres(
        adresse: json['adresse'] as String?,
        ville: json['ville'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        logoUrl: json['logo_url'] as String?,
        waveNumero: json['wave_numero'] as String?,
        orangeNumero: json['orange_numero'] as String?,
        mtnNumero: json['mtn_numero'] as String?,
        devise: json['devise'] as String?,
        fuseauHoraire: json['fuseau_horaire'] as String?,
        egliseNom: json['eglise_nom'] as String?,
        egliseCode: json['eglise_code'] as String?,
      );
}

/// Rôle d'un utilisateur dans son église (`GET /parametres/roles` :
/// `{ roles: [{ user_id, role, full_name, email }] }`).
class RoleEglise {
  final String userId;
  final String role; // admin_eglise | tresorier | responsable_culte | membre
  final String? fullName;
  final String? email;

  const RoleEglise({
    required this.userId,
    required this.role,
    this.fullName,
    this.email,
  });

  factory RoleEglise.fromJson(Map<String, dynamic> json) => RoleEglise(
        userId: json['user_id'] as String,
        role: json['role'] as String,
        fullName: json['full_name'] as String?,
        email: json['email'] as String?,
      );

  static String labelForRole(String role) {
    switch (role) {
      case 'admin_eglise':
        return 'Admin d’église';
      case 'tresorier':
        return 'Trésorier';
      case 'responsable_culte':
        return 'Responsable de culte';
      case 'super_admin':
        return 'Admin plateforme';
      default:
        return 'Membre';
    }
  }

  String get roleLabel => labelForRole(role);
}

/// Entrée du journal d'audit (`GET /parametres/audit` :
/// `{ items: [{ id, action, details, created_at, utilisateur }] }`).
class AuditEntree {
  final String id;
  final String action;
  final Map<String, dynamic>? details;
  final DateTime? createdAt;
  final String? utilisateur;

  const AuditEntree({
    required this.id,
    required this.action,
    this.details,
    this.createdAt,
    this.utilisateur,
  });

  factory AuditEntree.fromJson(Map<String, dynamic> json) => AuditEntree(
        id: json['id'] as String,
        action: json['action'] as String,
        details: (json['details'] as Map?)?.cast<String, dynamic>(),
        createdAt: parseDate(json['created_at'] as String?),
        utilisateur: json['utilisateur'] as String?,
      );
}
