import '../utils/format.dart';

/// Contribution financière (`contributions`) : dîme, offrande, don,
/// dépense ou cotisation.
class Contribution {
  final String id;
  final String type; // dime | offrande | don | depense | cotisation
  final int amountFcfa;
  final String paymentMethod; // wave | orange_money | mtn_momo | especes | virement
  final String? paymentRef;
  final String status; // en_attente | confirme | annule
  final String? note;
  final String? memberId;
  final String? membreNom;
  final String? membreMatricule;
  final String? campagneId;
  final DateTime? createdAt;

  /// Numéro de reçu (T7) : REC-AAAA-NNNN, émis à la confirmation.
  final String? recuNumero;

  /// Champs du reçu (`GET /contributions/:id` → `{ recu }`).
  final String? egliseNom;
  final String? egliseCode;

  const Contribution({
    required this.id,
    required this.type,
    required this.amountFcfa,
    required this.paymentMethod,
    this.paymentRef,
    required this.status,
    this.note,
    this.memberId,
    this.membreNom,
    this.membreMatricule,
    this.campagneId,
    this.createdAt,
    this.recuNumero,
    this.egliseNom,
    this.egliseCode,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) => Contribution(
        id: json['id'] as String,
        type: json['type'] as String,
        amountFcfa: (json['amount_fcfa'] as num).toInt(),
        paymentMethod: json['payment_method'] as String,
        paymentRef: json['payment_ref'] as String?,
        status: json['status'] as String? ?? 'en_attente',
        note: json['note'] as String?,
        memberId: json['member_id'] as String?,
        membreNom: json['membre_nom'] as String?,
        membreMatricule: json['membre_matricule'] as String?,
        campagneId: json['campagne_id'] as String?,
        createdAt: parseDate(json['created_at'] as String?),
        recuNumero: json['recu_numero'] as String?,
        egliseNom: json['eglise_nom'] as String?,
        egliseCode: json['eglise_code'] as String?,
      );

  static String labelForTypePluriel(String type) {
    switch (type) {
      case 'dime':
        return 'Dîmes confirmées';
      case 'offrande':
        return 'Offrandes confirmées';
      case 'don':
        return 'Dons confirmés';
      case 'depense':
        return 'Dépenses confirmées';
      case 'cotisation':
        return 'Cotisations confirmées';
      default:
        return type;
    }
  }

  static String labelForType(String type) {
    switch (type) {
      case 'dime':
        return 'Dîme';
      case 'offrande':
        return 'Offrande';
      case 'don':
        return 'Don';
      case 'depense':
        return 'Dépense';
      case 'cotisation':
        return 'Cotisation';
      default:
        return type;
    }
  }

  static String labelForPayment(String method) {
    switch (method) {
      case 'wave':
        return 'Wave';
      case 'orange_money':
        return 'Orange Money';
      case 'mtn_momo':
        return 'MTN MoMo';
      case 'especes':
        return 'Espèces';
      case 'virement':
        return 'Virement';
      default:
        return method;
    }
  }

  static String labelForStatus(String status) {
    switch (status) {
      case 'en_attente':
        return 'En attente';
      case 'confirme':
        return 'Confirmée';
      case 'annule':
        return 'Annulée';
      default:
        return status;
    }
  }

  String get typeLabel => labelForType(type);
  String get paymentLabel => labelForPayment(paymentMethod);
  String get statusLabel => labelForStatus(status);
}

/// Totaux par type (`GET /contributions` : `{ contributions, totaux }`).
class ContributionTotals {
  final int totalFcfa;
  final int nombre;

  const ContributionTotals({required this.totalFcfa, required this.nombre});

  factory ContributionTotals.fromJson(Map<String, dynamic> json) =>
      ContributionTotals(
        totalFcfa: (json['total_fcfa'] as num?)?.toInt() ?? 0,
        nombre: (json['nombre'] as num?)?.toInt() ?? 0,
      );
}

/// Page de contributions avec totaux par type.
class ContributionPage {
  final List<Contribution> contributions;
  final Map<String, ContributionTotals> totaux;

  const ContributionPage({required this.contributions, required this.totaux});
}
