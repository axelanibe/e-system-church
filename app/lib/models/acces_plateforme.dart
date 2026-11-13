/// Libellés des droits Plateforme (`GET /plateforme/acces`).
/// Un seul droit aujourd'hui (« chiffres ») ; la liste s'allongera
/// avec les capacités de la Plateforme.
const Map<String, String> libellesDroitsPlateforme = {
  'chiffres': 'Voir les chiffres globaux',
  'acces': 'Gérer les accès Plateforme',
};

/// Accès Plateforme (`GET /plateforme/acces`, super_admin seulement) :
/// l'admin de la plateforme et ses aides, avec leurs droits limités.
class AccesPlateforme {
  final String userId;
  final String nom;
  final String email;
  final String role;
  final List<String> droits;
  final DateTime? creeLe;

  const AccesPlateforme({
    required this.userId,
    required this.nom,
    required this.email,
    required this.role,
    required this.droits,
    this.creeLe,
  });

  bool get estSuperAdmin => role == 'super_admin';

  String get roleLabel =>
      estSuperAdmin ? 'Admin plateforme' : 'Aide Plateforme';

  factory AccesPlateforme.fromJson(Map<String, dynamic> json) =>
      AccesPlateforme(
        userId: json['user_id'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
        droits: (json['droits'] as List<dynamic>?)
                ?.map((d) => d.toString())
                .toList() ??
            const [],
        creeLe: json['cree_le'] == null
            ? null
            : DateTime.tryParse(json['cree_le'].toString()),
      );
}

/// Accès créé (`POST /plateforme/acces`) : compte créé ou rattaché.
/// Le lien d'invitation n'existe que pour un nouveau compte ; une
/// personne déjà membre se connecte avec son mot de passe existant.
class AccesPlateformeCree {
  final String userId;
  final String email;
  final String nom;
  final bool dejaMembre;
  final String? lienInvitation;
  final DateTime? expiresAt;

  const AccesPlateformeCree({
    required this.userId,
    required this.email,
    required this.nom,
    required this.dejaMembre,
    this.lienInvitation,
    this.expiresAt,
  });

  factory AccesPlateformeCree.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return AccesPlateformeCree(
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      nom: user['full_name'] as String? ?? '',
      dejaMembre: json['deja_membre'] as bool? ?? false,
      lienInvitation: json['lien_invitation'] as String?,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'].toString()),
    );
  }
}
