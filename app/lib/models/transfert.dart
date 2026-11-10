import '../utils/format.dart';

/// Transfert de membre entre branches (`transferts_membre`) : demande par
/// matricule, validation par les deux pasteurs (départ puis arrivée),
/// historique gardé. À la double acceptation, le membre change d'église et
/// reçoit un nouveau matricule dans l'église d'arrivée.
class TransfertMembre {
  final String id;
  final String membreId;
  final String membreNom;
  final String ancienMatricule;
  final String? nouveauMatricule;
  final String egliseDepartId;
  final String egliseDepartCode;
  final String egliseDepartNom;
  final String? egliseDepartVille;
  final String egliseArriveeId;
  final String egliseArriveeCode;
  final String egliseArriveeNom;
  final String? egliseArriveeVille;
  final String? motif;
  final String status; // en_attente | accepte | refuse | annule
  final String decisionDepart; // en_attente | accepte | refuse
  final String decisionArrivee; // en_attente | accepte | refuse
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TransfertMembre({
    required this.id,
    required this.membreId,
    required this.membreNom,
    required this.ancienMatricule,
    this.nouveauMatricule,
    required this.egliseDepartId,
    required this.egliseDepartCode,
    required this.egliseDepartNom,
    this.egliseDepartVille,
    required this.egliseArriveeId,
    required this.egliseArriveeCode,
    required this.egliseArriveeNom,
    this.egliseArriveeVille,
    this.motif,
    required this.status,
    required this.decisionDepart,
    required this.decisionArrivee,
    this.createdAt,
    this.updatedAt,
  });

  factory TransfertMembre.fromJson(Map<String, dynamic> json) =>
      TransfertMembre(
        id: json['id'] as String,
        membreId: json['membre_id'] as String,
        membreNom: json['membre_nom'] as String,
        ancienMatricule: json['ancien_matricule'] as String,
        nouveauMatricule: json['nouveau_matricule'] as String?,
        egliseDepartId: json['eglise_depart_id'] as String,
        egliseDepartCode: json['eglise_depart_code'] as String? ?? '',
        egliseDepartNom: json['eglise_depart_nom'] as String? ?? '',
        egliseDepartVille: json['eglise_depart_ville'] as String?,
        egliseArriveeId: json['eglise_arrivee_id'] as String,
        egliseArriveeCode: json['eglise_arrivee_code'] as String? ?? '',
        egliseArriveeNom: json['eglise_arrivee_nom'] as String? ?? '',
        egliseArriveeVille: json['eglise_arrivee_ville'] as String?,
        motif: json['motif'] as String?,
        status: json['status'] as String? ?? 'en_attente',
        decisionDepart: json['decision_depart'] as String? ?? 'en_attente',
        decisionArrivee: json['decision_arrivee'] as String? ?? 'en_attente',
        createdAt: parseDate(json['created_at'] as String?),
        updatedAt: parseDate(json['updated_at'] as String?),
      );

  static String labelForStatus(String status) {
    switch (status) {
      case 'en_attente':
        return 'En attente';
      case 'accepte':
        return 'Accepté';
      case 'refuse':
        return 'Refusé';
      case 'annule':
        return 'Annulé';
      default:
        return status;
    }
  }

  static String labelForDecision(String decision) {
    switch (decision) {
      case 'en_attente':
        return 'En attente';
      case 'accepte':
        return 'Acceptée';
      case 'refuse':
        return 'Refusée';
      default:
        return decision;
    }
  }

  String get statusLabel => labelForStatus(status);

  /// Mon église doit décider maintenant sur ce transfert (elle est le
  /// départ en attente, ou l'arrivée alors que le départ a accepté).
  bool aTraiterPour(String churchId) {
    if (status != 'en_attente') return false;
    if (egliseDepartId == churchId && decisionDepart == 'en_attente') {
      return true;
    }
    return egliseArriveeId == churchId &&
        decisionDepart == 'accepte' &&
        decisionArrivee == 'en_attente';
  }

  /// Mon église est l'église de départ de ce transfert.
  bool estDepartDe(String churchId) => egliseDepartId == churchId;
}

/// Résultat de `GET /transferts` : à traiter, émises, reçues, historique.
class TransfertsResult {
  final List<TransfertMembre> aTraiter;
  final List<TransfertMembre> emises;
  final List<TransfertMembre> recues;
  final List<TransfertMembre> historique;

  const TransfertsResult({
    required this.aTraiter,
    required this.emises,
    required this.recues,
    required this.historique,
  });
}
