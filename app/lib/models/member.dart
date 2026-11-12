import '../utils/format.dart';

/// Membre d'une église (`members`). Le matricule est unique dans tout le système (nouveaux numéros, M-LA-171268-01).
class Member {
  final String id;
  final String matricule;
  final String fullName;
  final String? phone;
  final String? email;
  final String? birthDate; // « AAAA-MM-JJ »
  /// Sexe du membre : 'M' ou 'F' (null = non précisé). Il entre dans le
  /// matricule québécois (règle +50 au mois pour les femmes).
  final String? sexe;
  final String? department;
  /// Fonction du membre (libellé « Fonction », catalogue `fonctions`).
  /// Null ou « Aucun » veut dire sans fonction précise.
  final String? fonction;
  /// Poste du membre (catalogue `postes`), séparé de la fonction et du
  /// département (document d'architecture, §4).
  final String? poste;
  final String? cellGroup;
  final String status; // actif | nouveau_converti | inactif
  final DateTime? createdAt;

  /// Photo du membre (migration 018) : URL fournie par le membre ou
  /// l'église, null tant qu'aucune photo n'est fournie, jamais inventée.
  final String? photoUrl;

  const Member({
    required this.id,
    required this.matricule,
    required this.fullName,
    this.phone,
    this.email,
    this.birthDate,
    this.sexe,
    this.department,
    this.fonction,
    this.poste,
    this.cellGroup,
    required this.status,
    this.createdAt,
    this.photoUrl,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        matricule: json['matricule'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        birthDate: json['birth_date'] as String?,
        sexe: json['sexe'] as String?,
        department: json['department'] as String?,
        fonction: json['fonction'] as String?,
        poste: json['poste'] as String?,
        cellGroup: json['cell_group'] as String?,
        status: json['status'] as String? ?? 'actif',
        createdAt: parseDate(json['created_at'] as String?),
        photoUrl: json['photo_url'] as String?,
      );

  static String labelForStatus(String status) {
    switch (status) {
      case 'actif':
        return 'Actif';
      case 'nouveau_converti':
        return 'Nouveau converti';
      case 'inactif':
        return 'Inactif';
      default:
        return status;
    }
  }

  String get statusLabel => labelForStatus(status);

  /// Fonction affichée sur le profil et la carte : sans fonction précise
  /// (« Aucun » ou vide), la carte montre « Membre ».
  String get fonctionAffichee {
    final f = fonction?.trim() ?? '';
    if (f.isEmpty || f == 'Aucun') return 'Membre';
    return f;
  }
}

/// Page de membres (`GET /membres` : `{ total, membres }`).
class MemberPage {
  final int total;
  final List<Member> membres;

  const MemberPage({required this.total, required this.membres});
}
