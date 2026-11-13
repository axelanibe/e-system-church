// Paiements par pays et clés API de chaque église (module 14).
//
// Les identifiants ne sont jamais renvoyés par l'API : la lecture est
// masquée seulement (`apercu`, ex. `••••1234`) et les champs secrets ne
// sont jamais pré-remplis ni affichés après saisie.

/// Un champ requis par un fournisseur (ex. clé API, secret, identifiant
/// marchand). `secret` vrai = champ masqué à la saisie (`obscureText`).
/// `optionnel` vrai (tranche T8) = champ requis pour une fonction mais pas
/// pour l'exécution — ex. le secret de signature du webhook Wave : sans
/// lui la configuration fonctionne, mais les webhooks sont rejetés.
class ChampPaiement {
  final String nom;
  final String label;
  final bool secret;
  final bool optionnel;

  const ChampPaiement({
    required this.nom,
    required this.label,
    required this.secret,
    this.optionnel = false,
  });

  factory ChampPaiement.fromJson(Map<String, dynamic> json) => ChampPaiement(
        nom: json['nom'] as String,
        label: json['label'] as String? ?? json['nom'] as String,
        secret: json['secret'] as bool? ?? false,
        optionnel: json['optionnel'] as bool? ?? false,
      );
}

/// Un fournisseur du catalogue (`GET /paiements/fournisseurs`).
class FournisseurPaiement {
  final String code;
  final String nom;
  final List<String> pays;
  final String type;
  final List<ChampPaiement> champsRequis;

  const FournisseurPaiement({
    required this.code,
    required this.nom,
    required this.pays,
    required this.type,
    required this.champsRequis,
  });

  factory FournisseurPaiement.fromJson(Map<String, dynamic> json) =>
      FournisseurPaiement(
        code: json['code'] as String,
        nom: json['nom'] as String,
        pays: (json['pays'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        type: json['type'] as String,
        champsRequis: (json['champs_requis'] as List<dynamic>? ?? [])
            .map((e) => ChampPaiement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Vrai si le fournisseur est disponible pour ce pays (ou partout).
  bool disponiblePour(String codePays) =>
      pays.contains(codePays) || pays.contains('*');
}

/// Un champ d'une configuration d'église, avec son état (configuré ou non).
/// La valeur n'est jamais renvoyée par l'API.
class ChampPaiementConfigure {
  final String nom;
  final String label;
  final bool secret;
  final bool configure;

  const ChampPaiementConfigure({
    required this.nom,
    required this.label,
    required this.secret,
    required this.configure,
  });

  factory ChampPaiementConfigure.fromJson(Map<String, dynamic> json) =>
      ChampPaiementConfigure(
        nom: json['nom'] as String,
        label: json['label'] as String? ?? json['nom'] as String,
        secret: json['secret'] as bool? ?? false,
        configure: json['configure'] as bool? ?? false,
      );
}

/// Configuration masquée d'un moyen de paiement pour une église
/// (`GET /eglises/:id/paiements`). Aucune valeur secrète n'est exposée.
class EglisePaiement {
  final String id;
  final String fournisseurCode;
  final String fournisseurNom;
  final String type;
  final String pays;
  final String? libelle;
  final String? apercu;
  final bool actif;
  final List<ChampPaiementConfigure> champs;

  const EglisePaiement({
    required this.id,
    required this.fournisseurCode,
    required this.fournisseurNom,
    required this.type,
    required this.pays,
    this.libelle,
    this.apercu,
    required this.actif,
    required this.champs,
  });

  factory EglisePaiement.fromJson(Map<String, dynamic> json) => EglisePaiement(
        id: json['id'] as String,
        fournisseurCode: json['fournisseur_code'] as String,
        fournisseurNom: json['fournisseur_nom'] as String,
        type: json['type'] as String,
        pays: json['pays'] as String,
        libelle: json['libelle'] as String?,
        apercu: json['apercu'] as String?,
        actif: json['actif'] as bool? ?? false,
        champs: (json['champs'] as List<dynamic>? ?? [])
            .map((e) =>
                ChampPaiementConfigure.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
