import '../utils/format.dart';

/// Famille de membres (`familles`).
class Famille {
  final String id;
  final String nom;
  final String? chefFamilleId;
  final String? adresse;
  final String? telephone;
  final DateTime? createdAt;

  const Famille({
    required this.id,
    required this.nom,
    this.chefFamilleId,
    this.adresse,
    this.telephone,
    this.createdAt,
  });

  factory Famille.fromJson(Map<String, dynamic> json) => Famille(
        id: json['id'] as String,
        nom: json['nom'] as String,
        chefFamilleId: json['chef_famille_id'] as String?,
        adresse: json['adresse'] as String?,
        telephone: json['telephone'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Entrée de l'historique des statuts d'un membre (`membre_statuts`).
class MembreStatut {
  final String id;
  final String memberId;
  final String statut; // membre | sympathisant | nouveau_converti | en_formation | suspendu | parti
  final String? ancienStatut;
  final String? motif;
  final DateTime? createdAt;

  const MembreStatut({
    required this.id,
    required this.memberId,
    required this.statut,
    this.ancienStatut,
    this.motif,
    this.createdAt,
  });

  factory MembreStatut.fromJson(Map<String, dynamic> json) => MembreStatut(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        statut: json['statut'] as String,
        ancienStatut: json['ancien_statut'] as String?,
        motif: json['motif'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'membre':
        return 'Membre';
      case 'sympathisant':
        return 'Sympathisant';
      case 'nouveau_converti':
        return 'Nouveau converti';
      case 'en_formation':
        return 'En formation';
      case 'suspendu':
        return 'Suspendu';
      case 'parti':
        return 'Parti';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}

/// Baptême d'un membre (`baptemes`).
class Bapteme {
  final String id;
  final String memberId;
  final String dateBapteme; // « AAAA-MM-JJ »
  final String? lieu;
  final String? pasteur;
  final String? certificatNumero;
  final DateTime? createdAt;

  const Bapteme({
    required this.id,
    required this.memberId,
    required this.dateBapteme,
    this.lieu,
    this.pasteur,
    this.certificatNumero,
    this.createdAt,
  });

  factory Bapteme.fromJson(Map<String, dynamic> json) => Bapteme(
        id: json['id'] as String,
        memberId: json['member_id'] as String,
        dateBapteme: json['date_bapteme'] as String,
        lieu: json['lieu'] as String?,
        pasteur: json['pasteur'] as String?,
        certificatNumero: json['certificat_numero'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Lien parent-enfant entre deux membres (`liens_parent_enfant`).
class LienParentEnfant {
  final String id;
  final String parentMemberId;
  final String enfantMemberId;
  final String lien; // pere | mere | tuteur | autre
  final String statut; // en_attente | valide | refuse
  final DateTime? createdAt;

  const LienParentEnfant({
    required this.id,
    required this.parentMemberId,
    required this.enfantMemberId,
    required this.lien,
    required this.statut,
    this.createdAt,
  });

  factory LienParentEnfant.fromJson(Map<String, dynamic> json) =>
      LienParentEnfant(
        id: json['id'] as String,
        parentMemberId: json['parent_member_id'] as String,
        enfantMemberId: json['enfant_member_id'] as String,
        lien: json['lien'] as String,
        statut: json['statut'] as String? ?? 'en_attente',
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForLien(String lien) {
    switch (lien) {
      case 'pere':
        return 'Père';
      case 'mere':
        return 'Mère';
      case 'tuteur':
        return 'Tuteur';
      default:
        return 'Autre';
    }
  }

  String get lienLabel => labelForLien(lien);
}

/// Département de l'église (`departements` : louange, intercession…).
class Departement {
  final String id;
  final String nom;
  final String? description;
  final String? responsableMemberId;
  final DateTime? createdAt;

  const Departement({
    required this.id,
    required this.nom,
    this.description,
    this.responsableMemberId,
    this.createdAt,
  });

  factory Departement.fromJson(Map<String, dynamic> json) => Departement(
        id: json['id'] as String,
        nom: json['nom'] as String,
        description: json['description'] as String?,
        responsableMemberId: json['responsable_member_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Fonction de l'église (`fonctions`, catalogue par église).
class Fonction {
  final String id;
  final String nom;
  final DateTime? createdAt;

  const Fonction({required this.id, required this.nom, this.createdAt});

  factory Fonction.fromJson(Map<String, dynamic> json) => Fonction(
        id: json['id'] as String,
        nom: json['nom'] as String,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// Poste de l'église (`postes`, catalogue par église).
class Poste {
  final String id;
  final String nom;
  final DateTime? createdAt;

  const Poste({required this.id, required this.nom, this.createdAt});

  factory Poste.fromJson(Map<String, dynamic> json) => Poste(
        id: json['id'] as String,
        nom: json['nom'] as String,
        createdAt: parseDate(json['created_at'] as String?),
      );
}

/// 16 départements de départ, en 4 pôles (document d'architecture, §3).
/// Catalogue de départ, pas une structure rigide, à valider par Axel, tous
/// modifiables ensuite par l'administrateur. Mêmes valeurs côté serveur
/// (`DEPARTEMENTS_DEFAUT` dans `server/src/auth.ts`, pôle en description).
const List<String> departementsParDefaut = [
  'Prière et intercession',
  'Évangélisation et missions',
  'Formation biblique',
  'Louange et adoration',
  'Accompagnement pastoral',
  'Administration générale',
  'Finances et comptabilité',
  'Ressources humaines',
  'Logistique et patrimoine',
  'Protocole, accueil et sécurité',
  'Communication et médias',
  'Informatique et numérique',
  'Événementiel',
  'Jeunesse et enfants',
  'Femmes, hommes et familles',
  'Action sociale et solidarité',
];

/// Fonctions habituelles dans les églises (liste d'Axel), libellé « Fonction ».
/// « Aucun » veut dire sans fonction précise, la carte montre alors « Membre ».
/// Pas la liste de CONNEXION PROPHÉTIQUE. Mêmes valeurs côté serveur
/// (`FONCTIONS_DEFAUT` dans `server/src/auth.ts`).
const List<String> fonctionsParDefaut = [
  'Pasteur',
  'Ancien',
  'Diacre',
  'Diaconesse',
  'Intercesseur',
  'Chantre',
  'Responsable',
  'Secrétaire',
  'Trésorier',
  'Leader',
  'Membre',
  'Aucun',
];

/// Postes d'exemple (document d'architecture, §4). Fonction, département et
/// poste sont trois notions séparées, stockées séparément. Mêmes valeurs côté
/// serveur (`POSTES_DEFAUT` dans `server/src/auth.ts`).
const List<String> postesParDefaut = [
  'Directeur de département',
  'Directeur adjoint',
  "Chef de service ou d'équipe",
  "Responsable d'activité",
  'Collaborateur ou bénévole',
];

/// Cellule de maison / groupe de quartier (`cellules`).
class Cellule {
  final String id;
  final String nom;
  final String? quartier;
  final String? responsableMemberId;
  final String? jourReunion;
  final String? heureReunion;
  final DateTime? createdAt;

  const Cellule({
    required this.id,
    required this.nom,
    this.quartier,
    this.responsableMemberId,
    this.jourReunion,
    this.heureReunion,
    this.createdAt,
  });

  factory Cellule.fromJson(Map<String, dynamic> json) => Cellule(
        id: json['id'] as String,
        nom: json['nom'] as String,
        quartier: json['quartier'] as String?,
        responsableMemberId: json['responsable_member_id'] as String?,
        jourReunion: json['jour_reunion'] as String?,
        heureReunion: json['heure_reunion'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );
}
