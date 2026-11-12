import 'church.dart';

/// Utilisateur connecté (réponses `/auth/*`, `/moi/eglise`).
class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? phone;

  /// Photo du membre lié (migration 018, renvoyée par `GET /moi`) :
  /// null tant qu'aucune photo n'est fournie.
  final String? photoUrl;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.photoUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        photoUrl: json['photo_url'] as String?,
      );
}

/// Résultat de `/auth/login` et `/auth/register` :
/// `{ token, user, church, eglises? }` (register renvoie aussi `rattachement`).
class AuthResult {
  final String token;
  final AppUser user;
  final Church church;
  final List<Membership> eglises;

  /// Rattachement créé à l'inscription (cas « Rejoindre une église mère »),
  /// null sinon.
  final Map<String, dynamic>? rattachement;

  const AuthResult({
    required this.token,
    required this.user,
    required this.church,
    required this.eglises,
    this.rattachement,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: json['token'] as String,
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        church: Church.fromJson(json['church'] as Map<String, dynamic>),
        eglises: (json['eglises'] as List<dynamic>? ?? [])
            .map((e) => Membership.fromJson(e as Map<String, dynamic>))
            .toList(),
        rattachement: json['rattachement'] as Map<String, dynamic>?,
      );
}

/// Résultat de `GET /moi/eglise` : `{ user, church, role, eglises }`.
class MeResult {
  final AppUser user;
  final Church church;
  final String role;
  final List<Membership> eglises;

  const MeResult({
    required this.user,
    required this.church,
    required this.role,
    required this.eglises,
  });

  factory MeResult.fromJson(Map<String, dynamic> json) => MeResult(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        church: Church.fromJson(json['church'] as Map<String, dynamic>),
        role: json['role'] as String,
        eglises: (json['eglises'] as List<dynamic>? ?? [])
            .map((e) => Membership.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
