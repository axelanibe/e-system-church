import 'rattachement.dart';

/// Église (réponse API : `churches`).
class Church {
  final String id;
  final String code;
  final String name;
  final String? parentChurchId;
  final String? city;
  final String status;

  /// Rôle de l'utilisateur dans cette église (présent dans les réponses
  /// d'authentification, absent sinon).
  final String? role;

  const Church({
    required this.id,
    required this.code,
    required this.name,
    this.parentChurchId,
    this.city,
    required this.status,
    this.role,
  });

  factory Church.fromJson(Map<String, dynamic> json) => Church(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        parentChurchId: json['parent_church_id'] as String?,
        city: json['city'] as String?,
        status: json['status'] as String? ?? 'active',
        role: json['role'] as String?,
      );

  /// Une église sans mère est une église mère (racine de son réseau).
  bool get isMere => parentChurchId == null;
}

/// Nœud de l'arborescence (`GET /eglises/arbre`) : une église + ses enfants.
class ChurchNode extends Church {
  final int membresActifs;
  final List<ChurchNode> children;

  const ChurchNode({
    required super.id,
    required super.code,
    required super.name,
    super.parentChurchId,
    super.city,
    required super.status,
    this.membresActifs = 0,
    this.children = const [],
  });

  factory ChurchNode.fromJson(Map<String, dynamic> json) => ChurchNode(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        parentChurchId: json['parent_church_id'] as String?,
        city: json['city'] as String?,
        status: json['status'] as String? ?? 'active',
        membresActifs: (json['membres_actifs'] as num?)?.toInt() ?? 0,
        children: (json['children'] as List<dynamic>? ?? [])
            .map((e) => ChurchNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Nombre total d'églises dans ce sous-arbre (le nœud compris).
  int get totalEglises =>
      1 + children.fold<int>(0, (sum, c) => sum + c.totalEglises);

  /// Nombre total de membres actifs dans ce sous-arbre.
  int get totalMembresActifs =>
      membresActifs +
      children.fold<int>(0, (sum, c) => sum + c.totalMembresActifs);
}

/// Appartenance d'un utilisateur à une église (réponses `/auth/login`,
/// `/moi/eglise` : `{ role, church }`).
class Membership {
  final Church church;
  final String role;

  const Membership({required this.church, required this.role});

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        church: Church.fromJson(json['church'] as Map<String, dynamic>),
        role: json['role'] as String,
      );
}

/// Résultat de `GET /eglises/arbre`.
class TreeResult {
  final ChurchNode arbre;
  final List<Rattachement> demandesRattachement;

  const TreeResult({required this.arbre, required this.demandesRattachement});
}
