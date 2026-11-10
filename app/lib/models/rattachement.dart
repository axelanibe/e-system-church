import '../utils/format.dart';

/// Demande de rattachement (`rattachements`) : une église demande à rejoindre
/// une mère ; la mère accepte ou refuse.
class Rattachement {
  final String id;
  final String status; // en_attente | acceptee | refusee
  final String egliseId;
  final String egliseCode;
  final String egliseNom;
  final String? egliseVille;
  final DateTime? createdAt;

  const Rattachement({
    required this.id,
    required this.status,
    required this.egliseId,
    required this.egliseCode,
    required this.egliseNom,
    this.egliseVille,
    this.createdAt,
  });

  factory Rattachement.fromJson(Map<String, dynamic> json) => Rattachement(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'en_attente',
        egliseId: json['eglise_id'] as String,
        egliseCode: json['eglise_code'] as String,
        egliseNom: json['eglise_nom'] as String,
        egliseVille: json['eglise_ville'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
      );

  static String labelForStatus(String status) {
    switch (status) {
      case 'en_attente':
        return 'En attente';
      case 'acceptee':
        return 'Acceptée';
      case 'refusee':
        return 'Refusée';
      default:
        return status;
    }
  }

  String get statusLabel => labelForStatus(status);
}

/// Résultat de `GET /rattachements` : demandes reçues et émises.
class RattachementsResult {
  final List<Rattachement> recues;
  final List<Rattachement> emises;

  const RattachementsResult({required this.recues, required this.emises});
}
