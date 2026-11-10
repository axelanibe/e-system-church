import '../utils/format.dart';

/// Membre d'une église (`members`). Le matricule est unique PAR église.
class Member {
  final String id;
  final String matricule;
  final String fullName;
  final String? phone;
  final String? email;
  final String? birthDate; // « AAAA-MM-JJ »
  final String? department;
  final String? cellGroup;
  final String status; // actif | nouveau_converti | inactif
  final DateTime? createdAt;

  const Member({
    required this.id,
    required this.matricule,
    required this.fullName,
    this.phone,
    this.email,
    this.birthDate,
    this.department,
    this.cellGroup,
    required this.status,
    this.createdAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        matricule: json['matricule'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        birthDate: json['birth_date'] as String?,
        department: json['department'] as String?,
        cellGroup: json['cell_group'] as String?,
        status: json['status'] as String? ?? 'actif',
        createdAt: parseDate(json['created_at'] as String?),
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
}

/// Page de membres (`GET /membres` : `{ total, membres }`).
class MemberPage {
  final int total;
  final List<Member> membres;

  const MemberPage({required this.total, required this.membres});
}
