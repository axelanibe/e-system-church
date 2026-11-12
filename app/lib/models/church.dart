import 'dart:ui';

import 'profil.dart';
import 'rattachement.dart';

/// Église (réponse API : `churches`).
class Church {
  final String id;

  /// Code de tutelle (ESC-…) : une église secondaire l'utilise pour se
  /// rattacher à sa mère.
  final String code;

  /// Code fidèle (ESC-F-…) : les membres l'utilisent pour s'inscrire dans
  /// cette église. Nullable pour compatibilité avec les réponses servies
  /// avant la migration 010.
  final String? codeFidele;

  final String name;
  final String? parentChurchId;
  final String? city;
  final String status;

  /// Rôle de l'utilisateur dans cette église (présent dans les réponses
  /// d'authentification, absent sinon).
  final String? role;

  /// Logo de l'église (URL, null si aucun logo : on affiche les initiales).
  final String? logoUrl;

  /// Couleur principale de l'église, au format hex (« #1E4D3B »).
  final String? couleurPrincipale;

  /// Devise de l'église (« FCFA », « EUR »…).
  final String? devise;

  /// Fuseau horaire de l'église (« Africa/Abidjan »).
  final String? fuseauHoraire;

  /// Texte de présentation de l'église.
  final String? description;

  /// Horaires des cultes affichés dans la présentation.
  final List<HoraireCulte> horairesCultes;

  const Church({
    required this.id,
    required this.code,
    this.codeFidele,
    required this.name,
    this.parentChurchId,
    this.city,
    required this.status,
    this.role,
    this.logoUrl,
    this.couleurPrincipale,
    this.devise,
    this.fuseauHoraire,
    this.description,
    this.horairesCultes = const [],
  });

  factory Church.fromJson(Map<String, dynamic> json) => Church(
        id: json['id'] as String,
        code: json['code'] as String,
        codeFidele: json['code_fidele'] as String?,
        name: json['name'] as String,
        parentChurchId: json['parent_church_id'] as String?,
        city: json['city'] as String?,
        status: json['status'] as String? ?? 'active',
        role: json['role'] as String?,
        logoUrl: json['logo_url'] as String?,
        couleurPrincipale: json['couleur_principale'] as String?,
        devise: json['devise'] as String?,
        fuseauHoraire: json['fuseau_horaire'] as String?,
        description: json['description'] as String?,
        horairesCultes: (json['horaires_cultes'] as List<dynamic>? ?? [])
            .map((e) => HoraireCulte.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Une église sans mère est une église mère (racine de son réseau).
  bool get isMere => parentChurchId == null;

  /// Initiales de l'église : premières lettres des deux premiers mots du
  /// nom. Sert de logo par défaut quand l'église n'a pas de logo.
  String get initiales {
    final mots = name
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .take(2)
        .toList();
    if (mots.isEmpty) return '';
    return mots.map((mot) => mot[0].toUpperCase()).join();
  }

  /// Couleur principale parsée depuis [couleurPrincipale] (hex), null si
  /// absente ou invalide.
  Color? get couleur {
    final hex = couleurPrincipale;
    if (hex == null) return null;
    final nettoye = hex.replaceFirst('#', '');
    final valeur = int.tryParse(
      nettoye.length == 6 ? 'FF$nettoye' : nettoye,
      radix: 16,
    );
    if (valeur == null) return null;
    return Color(valeur);
  }
}

/// Nœud de l'arborescence (`GET /eglises/arbre`) : une église + ses enfants.
class ChurchNode extends Church {
  final int membresActifs;
  final List<ChurchNode> children;

  const ChurchNode({
    required super.id,
    required super.code,
    super.codeFidele,
    required super.name,
    super.parentChurchId,
    super.city,
    required super.status,
    super.role,
    super.logoUrl,
    super.couleurPrincipale,
    super.devise,
    super.fuseauHoraire,
    super.description,
    super.horairesCultes,
    this.membresActifs = 0,
    this.children = const [],
  });

  factory ChurchNode.fromJson(Map<String, dynamic> json) => ChurchNode(
        id: json['id'] as String,
        code: json['code'] as String,
        codeFidele: json['code_fidele'] as String?,
        name: json['name'] as String,
        parentChurchId: json['parent_church_id'] as String?,
        city: json['city'] as String?,
        status: json['status'] as String? ?? 'active',
        role: json['role'] as String?,
        logoUrl: json['logo_url'] as String?,
        couleurPrincipale: json['couleur_principale'] as String?,
        devise: json['devise'] as String?,
        fuseauHoraire: json['fuseau_horaire'] as String?,
        description: json['description'] as String?,
        horairesCultes: (json['horaires_cultes'] as List<dynamic>? ?? [])
            .map((e) => HoraireCulte.fromJson(e as Map<String, dynamic>))
            .toList(),
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

/// Une page de `GET /moi/eglises` : mes églises, paginées + recherche.
/// Le sélecteur d'églises charge 50 églises par page et ne demande la
/// suite qu'au défilement, pour rester utilisable avec 500 branches.
class MesEglisesPage {
  final List<Membership> eglises;
  final int total;
  final int page;
  final int limite;
  final int pages;

  const MesEglisesPage({
    required this.eglises,
    required this.total,
    required this.page,
    required this.limite,
    required this.pages,
  });

  factory MesEglisesPage.fromJson(Map<String, dynamic> json) =>
      MesEglisesPage(
        eglises: (json['eglises'] as List<dynamic>? ?? [])
            .map((e) => Membership.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        limite: json['limite'] as int? ?? 50,
        pages: json['pages'] as int? ?? 0,
      );

  /// Vrai s'il reste des pages à charger après celle-ci.
  bool get aUneSuite => page < pages;
}

/// Résultat de `GET /eglises/arbre`.
class TreeResult {
  final ChurchNode arbre;
  final List<Rattachement> demandesRattachement;

  const TreeResult({required this.arbre, required this.demandesRattachement});
}
