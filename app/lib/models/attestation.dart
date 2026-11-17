import 'dart:convert';
import 'dart:typed_data';

import '../utils/format.dart';

/// Signature électronique dessinée (V1) : tracé monté au serveur, image
/// PNG stockée côté serveur, empreinte SHA-256 pour vérifier l'intégrité.
/// Renvoyée par POST `/attestations/:id/signer`,
/// POST `/proces-verbaux/:id/signer` et GET `/signatures/:type/:id`.
/// Le `fromJson` tolère une réponse enveloppée (`{'signature': {...}}`)
/// et un nom sous la clé `signataire` (cas d'un procès-verbal renvoyé).
class Signature {
  final String id;
  final String signataireNom;
  final String? signataireFonction;
  final DateTime? dateSignature;
  final String? empreinteSha256;
  final String? imagePngBase64;
  final String? documentType;
  final String? documentId;

  const Signature({
    required this.id,
    required this.signataireNom,
    this.signataireFonction,
    this.dateSignature,
    this.empreinteSha256,
    this.imagePngBase64,
    this.documentType,
    this.documentId,
  });

  factory Signature.fromJson(Map<String, dynamic> json) {
    final raw = json['signature'] is Map<String, dynamic>
        ? json['signature'] as Map<String, dynamic>
        : json;
    return Signature(
      id: raw['id'] as String? ?? '',
      signataireNom: raw['signataire_nom'] as String? ??
          raw['signataire'] as String? ??
          '',
      signataireFonction: raw['signataire_fonction'] as String?,
      dateSignature: parseDate(raw['date_signature'] as String?),
      empreinteSha256: raw['empreinte_sha256'] as String?,
      imagePngBase64: raw['image_png_base64'] as String?,
      documentType: raw['document_type'] as String?,
      documentId: raw['document_id'] as String?,
    );
  }

  /// Octets PNG du tracé, null si l'image est absente ou illisible.
  Uint8List? get imageBytes {
    final base64 = imagePngBase64;
    if (base64 == null || base64.isEmpty) return null;
    try {
      return base64Decode(base64);
    } catch (_) {
      return null;
    }
  }
}

/// Attestation (US3 + tranche B) : un PDF par membre, contenu figé à
/// l'émission. Type `don` : attestation annuelle de dons, total en FCFA.
/// Types `mariage`, `naissance`, `bapteme` : attestation d'événement,
/// sans total ni nombre de dons (null). Une attestation émise est figée ;
/// une correction en crée une nouvelle et annule l'ancienne (remplace_id).
/// En Côte d'Ivoire, l'attestation de dons est sans valeur fiscale :
/// reçu justificatif seulement.
class Attestation {
  final String id;
  final String numero;
  final int annee;
  final String type; // don | mariage | naissance | bapteme | membre
  final String? memberId;
  final String? membreNom;
  final String? membreMatricule;
  final int? totalFcfa; // dons seulement, null pour un événement
  final int? nbDons; // dons seulement, null pour un événement
  final String statut; // emise | annulee
  final String? remplaceId;
  final DateTime? dateEmission;

  const Attestation({
    required this.id,
    required this.numero,
    required this.annee,
    this.type = 'don',
    this.memberId,
    this.membreNom,
    this.membreMatricule,
    this.totalFcfa,
    this.nbDons,
    required this.statut,
    this.remplaceId,
    this.dateEmission,
  });

  factory Attestation.fromJson(Map<String, dynamic> json) => Attestation(
        id: json['id'] as String,
        numero: json['numero'] as String,
        annee: (json['annee'] as num).toInt(),
        type: json['type'] as String? ?? 'don',
        memberId: json['member_id'] as String?,
        membreNom: json['membre_nom'] as String?,
        membreMatricule: json['membre_matricule'] as String?,
        totalFcfa: (json['total_fcfa'] as num?)?.toInt(),
        nbDons: (json['nb_dons'] as num?)?.toInt(),
        statut: json['statut'] as String? ?? 'emise',
        remplaceId: json['remplace_id'] as String?,
        dateEmission: parseDate(json['date_emission'] as String?),
      );

  bool get estEmise => statut == 'emise';
  bool get estDon => type == 'don';

  /// Libellé du type, pour les listes et les filtres.
  static String libelleType(String type) => switch (type) {
        'mariage' => 'Mariage',
        'naissance' => 'Naissance',
        'bapteme' => 'Baptême',
        'membre' => 'Membre',
        _ => 'Dons',
      };

  String get libelle => libelleType(type);
}
