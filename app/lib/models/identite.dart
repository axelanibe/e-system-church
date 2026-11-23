/// Identité institutionnelle d'une église (`GET /identite`,
/// `PATCH /identite`, phase 2). Une église mère définit son identité,
/// ses branches en héritent obligatoirement : quand l'église est une
/// annexe et que l'identité de la mère est publiée, les champs
/// institutionnels renvoyés sont ceux de la mère ([heritee] vrai).
/// Les champs JSONB ([infosLegales], [couleurs] au-delà de la couleur
/// principale, [parametresDocuments]) ne sont pas éditables dans
/// l'écran de cette phase : ils sont lus, jamais écrits.
class IdentiteInstitutionnelle {
  final String egliseId;
  final String egliseCode;
  final String egliseNom;
  final bool estAnnexe;
  final EgliseMereIdentite? mere;
  final bool heritee;
  final String? statut; // brouillon | publié
  final String? statutMere; // null | brouillon | publié
  final String? nomOfficiel;
  final String? sigle;
  final String? slogan;
  final String? logoUrl;
  final String? couleurPrincipale;
  final Map<String, dynamic>? couleurs;
  final String? adresse;
  final String? ville;
  final String? pays;
  final String? telephone;
  final String? email;
  final String? siteWeb;
  final String? devise;
  final String? fuseauHoraire;
  final String? numeroEnregistrement;
  final String? ncc;
  final Map<String, dynamic>? infosLegales;
  final Map<String, dynamic>? parametresDocuments;
  final String? description;
  final List<dynamic>? horairesCultes;
  final String? adresseLocale;
  final String? villeLocale;
  final String? telephoneLocal;
  final String? emailLocal;

  const IdentiteInstitutionnelle({
    required this.egliseId,
    required this.egliseCode,
    required this.egliseNom,
    this.estAnnexe = false,
    this.mere,
    this.heritee = false,
    this.statut,
    this.statutMere,
    this.nomOfficiel,
    this.sigle,
    this.slogan,
    this.logoUrl,
    this.couleurPrincipale,
    this.couleurs,
    this.adresse,
    this.ville,
    this.pays,
    this.telephone,
    this.email,
    this.siteWeb,
    this.devise,
    this.fuseauHoraire,
    this.numeroEnregistrement,
    this.ncc,
    this.infosLegales,
    this.parametresDocuments,
    this.description,
    this.horairesCultes,
    this.adresseLocale,
    this.villeLocale,
    this.telephoneLocal,
    this.emailLocal,
  });

  factory IdentiteInstitutionnelle.fromJson(Map<String, dynamic> json) =>
      IdentiteInstitutionnelle(
        egliseId: json['eglise_id'] as String,
        egliseCode: json['eglise_code'] as String,
        egliseNom: json['eglise_nom'] as String,
        estAnnexe: json['est_annexe'] as bool? ?? false,
        mere: json['mere'] == null
            ? null
            : EgliseMereIdentite.fromJson(
                json['mere'] as Map<String, dynamic>),
        heritee: json['heritee'] as bool? ?? false,
        statut: json['statut'] as String?,
        statutMere: json['statut_mere'] as String?,
        nomOfficiel: json['nom_officiel'] as String?,
        sigle: json['sigle'] as String?,
        slogan: json['slogan'] as String?,
        logoUrl: json['logo_url'] as String?,
        couleurPrincipale: json['couleur_principale'] as String?,
        couleurs: (json['couleurs'] as Map?)?.cast<String, dynamic>(),
        adresse: json['adresse'] as String?,
        ville: json['ville'] as String?,
        pays: json['pays'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        siteWeb: json['site_web'] as String?,
        devise: json['devise'] as String?,
        fuseauHoraire: json['fuseau_horaire'] as String?,
        numeroEnregistrement: json['numero_enregistrement'] as String?,
        ncc: json['ncc'] as String?,
        infosLegales:
            (json['infos_legales'] as Map?)?.cast<String, dynamic>(),
        parametresDocuments:
            (json['parametres_documents'] as Map?)?.cast<String, dynamic>(),
        description: json['description'] as String?,
        horairesCultes: json['horaires_cultes'] as List<dynamic>?,
        adresseLocale: json['adresse_locale'] as String?,
        villeLocale: json['ville_locale'] as String?,
        telephoneLocal: json['telephone_local'] as String?,
        emailLocal: json['email_local'] as String?,
      );

  /// Sérialisation (clés du contrat) : sert au faux service des tests,
  /// qui applique un PATCH en fusionnant les champs modifiés.
  Map<String, dynamic> toJson() => {
        'eglise_id': egliseId,
        'eglise_code': egliseCode,
        'eglise_nom': egliseNom,
        'est_annexe': estAnnexe,
        'mere': mere?.toJson(),
        'heritee': heritee,
        'statut': statut,
        'statut_mere': statutMere,
        'nom_officiel': nomOfficiel,
        'sigle': sigle,
        'slogan': slogan,
        'logo_url': logoUrl,
        'couleur_principale': couleurPrincipale,
        'couleurs': couleurs,
        'adresse': adresse,
        'ville': ville,
        'pays': pays,
        'telephone': telephone,
        'email': email,
        'site_web': siteWeb,
        'devise': devise,
        'fuseau_horaire': fuseauHoraire,
        'numero_enregistrement': numeroEnregistrement,
        'ncc': ncc,
        'infos_legales': infosLegales,
        'parametres_documents': parametresDocuments,
        'description': description,
        'horaires_cultes': horairesCultes,
        'adresse_locale': adresseLocale,
        'ville_locale': villeLocale,
        'telephone_local': telephoneLocal,
        'email_local': emailLocal,
      };
}

/// Église mère d'une annexe (`mere` dans `GET /identite`) : identifiants
/// et nom seulement, jamais les champs institutionnels complets.
class EgliseMereIdentite {
  final String id;
  final String code;
  final String nom;

  const EgliseMereIdentite({
    required this.id,
    required this.code,
    required this.nom,
  });

  factory EgliseMereIdentite.fromJson(Map<String, dynamic> json) =>
      EgliseMereIdentite(
        id: json['id'] as String,
        code: json['code'] as String,
        nom: json['nom'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'nom': nom};
}
