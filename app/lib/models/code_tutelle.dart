import '../utils/format.dart';

/// Code de tutelle à usage unique (`codes_tutelle`, migration 009) :
/// `ESC-T-XXXXXX`, généré par la mère, donné à une église qui veut se
/// rattacher à elle. À l'acceptation du rattachement il passe à `utilise`,
/// automatiquement, et n'est plus valide.
class CodeTutelle {
  final String id;
  final String code;
  final String status; // actif | utilise | annule
  final String? utiliseeParNom;
  final String? utiliseeParCode;
  final DateTime? usedAt;
  final DateTime? createdAt;

  const CodeTutelle({
    required this.id,
    required this.code,
    required this.status,
    this.utiliseeParNom,
    this.utiliseeParCode,
    this.usedAt,
    this.createdAt,
  });

  factory CodeTutelle.fromJson(Map<String, dynamic> json) => CodeTutelle(
        id: json['id'] as String,
        code: json['code'] as String,
        status: json['status'] as String? ?? 'actif',
        utiliseeParNom: json['utilisee_par_nom'] as String?,
        utiliseeParCode: json['utilisee_par_code'] as String?,
        usedAt: parseDate(json['used_at'] as String?),
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatus(String status) {
    switch (status) {
      case 'actif':
        return 'Actif';
      case 'utilise':
        return 'Utilisé';
      case 'annule':
        return 'Annulé';
      default:
        return status;
    }
  }

  String get statusLabel => labelForStatus(status);
  bool get estActif => status == 'actif';
}
