// Tranche P5 — Rapports à mon église mère : une annexe choisit le
// type de rapport, l'application le génère depuis ses vraies données
// et l'envoie par e-mail à son église mère, en pièce jointe PDF.
// Textes repris mot pour mot de la projection validée par Axel le
// 12 novembre 2026. Aucune adresse e-mail inventée : tant que
// l'église mère n'a pas d'adresse en base, elle affiche « À compléter ».
// L'envoi par e-mail passe par mailer.ts (Lot B) : en attendant, le
// rapport est enregistré avec le statut `en_attente_envoi`, visible
// par la mère dans « Rapports reçus », et l'envoi est marqué en
// attente du Lot B, jamais présenté comme envoyé.

/// Types de rapport, dans l'ordre de la projection.
const typesRapportAnnexe = <String, String>{
  'bilan_annuel': 'Bilan annuel',
  'bilan_activite': 'Bilan d’activité',
  'rapport_financier': 'Rapport financier',
};

/// Église mère de mon église (`GET /moi/eglise-mere`) : racine du
/// réseau, nom et adresse e-mail, nulle tant qu'elle n'est pas
/// renseignée en base.
class EgliseMereContact {
  final String id;
  final String nom;
  final String? email;

  const EgliseMereContact({
    required this.id,
    required this.nom,
    this.email,
  });

  factory EgliseMereContact.fromJson(Map<String, dynamic> json) =>
      EgliseMereContact(
        id: json['id'] as String,
        nom: json['nom'] as String,
        email: json['email'] as String?,
      );
}

/// Un rapport envoyé par une annexe à son église mère (table
/// `rapports_annexe`, migration 023). Les chiffres viennent des
/// vraies données de l'église expéditrice, au moment de l'envoi.
class RapportAnnexe {
  final String id;
  final String type;
  final String? message;
  final int membres;
  final int recettesFcfa;
  final int depensesFcfa;
  final int soldeFcfa;
  final String statut; // en_attente_envoi | envoye
  final DateTime? creeLe;

  /// Nom de l'église expéditrice, pour la mère qui lit ses rapports
  /// reçus. Absent dans la réponse d'envoi.
  final String? egliseNom;

  const RapportAnnexe({
    required this.id,
    required this.type,
    this.message,
    required this.membres,
    required this.recettesFcfa,
    required this.depensesFcfa,
    required this.soldeFcfa,
    required this.statut,
    this.creeLe,
    this.egliseNom,
  });

  factory RapportAnnexe.fromJson(Map<String, dynamic> json) =>
      RapportAnnexe(
        id: json['id'] as String,
        type: json['type'] as String,
        message: json['message'] as String?,
        membres: (json['membres'] as num?)?.toInt() ?? 0,
        recettesFcfa: (json['recettes_fcfa'] as num?)?.toInt() ?? 0,
        depensesFcfa: (json['depenses_fcfa'] as num?)?.toInt() ?? 0,
        soldeFcfa: (json['solde_fcfa'] as num?)?.toInt() ?? 0,
        statut: json['statut'] as String? ?? 'en_attente_envoi',
        creeLe: json['cree_le'] == null
            ? null
            : DateTime.tryParse(json['cree_le'] as String),
        egliseNom: json['eglise_nom'] as String?,
      );

  /// Libellé du type, tel qu'il apparaît dans la projection.
  String get typeLibelle => typesRapportAnnexe[type] ?? type;

  /// Vrai tant que l'envoi par e-mail n'a pas eu lieu (Lot B).
  bool get enAttenteEnvoi => statut == 'en_attente_envoi';
}
