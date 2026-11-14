// Modèles de la tranche T12 — US4 à US17 restantes.
// Aucune donnée inventée : tout vient de l'API réelle, listes vides
// quand l'église n'a rien saisi.

int _entier(dynamic v) => v == null ? 0 : (v as num).toInt();
String _texte(dynamic v, [String defaut = '']) =>
    v == null ? defaut : v as String;
List<String> _textes(dynamic v) => v == null
    ? const []
    : (v as List<dynamic>).map((e) => e as String).toList();

/// Échéance d'une promesse de don (US4).
class EcheancePromesse {
  final String id;
  final String dateEcheance;
  final int montantFcfa;
  final String statut; // en_attente | recu | annulee

  const EcheancePromesse({
    required this.id,
    required this.dateEcheance,
    required this.montantFcfa,
    required this.statut,
  });

  factory EcheancePromesse.fromJson(Map<String, dynamic> json) =>
      EcheancePromesse(
        id: _texte(json['id']),
        dateEcheance: _texte(json['date_echeance']),
        montantFcfa: _entier(json['montant_fcfa']),
        statut: _texte(json['statut']),
      );

  bool get estRecue => statut == 'recu';
  bool get estEnAttente => statut == 'en_attente';
}

/// Promesse de don avec échéancier (US4).
class Promesse {
  final String id;
  final String memberId;
  final String? membreNom;
  final int montantTotalFcfa;
  final String dateDebut;
  final int nbVersements;
  final String statut; // en_cours | terminee | annulee
  final int recuFcfa;
  final int resteFcfa;
  final List<EcheancePromesse> echeances;

  const Promesse({
    required this.id,
    required this.memberId,
    this.membreNom,
    required this.montantTotalFcfa,
    required this.dateDebut,
    required this.nbVersements,
    required this.statut,
    required this.recuFcfa,
    required this.resteFcfa,
    this.echeances = const [],
  });

  factory Promesse.fromJson(Map<String, dynamic> json) => Promesse(
        id: _texte(json['id']),
        memberId: _texte(json['member_id']),
        membreNom: json['membre_nom'] as String?,
        montantTotalFcfa: _entier(json['montant_total_fcfa']),
        dateDebut: _texte(json['date_debut']),
        nbVersements: _entier(json['nb_versements']),
        statut: _texte(json['statut']),
        recuFcfa: _entier(json['recu_fcfa']),
        resteFcfa: _entier(json['reste_fcfa']),
        echeances: json['echeances'] == null
            ? const []
            : (json['echeances'] as List<dynamic>)
                .map((e) => EcheancePromesse.fromJson(e as Map<String, dynamic>))
                .toList(),
      );

  bool get estEnCours => statut == 'en_cours';
  double get progression =>
      montantTotalFcfa <= 0 ? 0 : recuFcfa / montantTotalFcfa;
}

/// Don en nature (US5). Jamais compté dans les totaux financiers.
class DonNature {
  final String id;
  final String? memberId;
  final String? membreNom;
  final String description;
  final int quantite;
  final String? unite;
  final String typeDon; // materiel | nourriture | temps
  final double? heures;
  final String dateDon;
  final bool anonyme;

  const DonNature({
    required this.id,
    this.memberId,
    this.membreNom,
    required this.description,
    required this.quantite,
    this.unite,
    required this.typeDon,
    this.heures,
    required this.dateDon,
    required this.anonyme,
  });

  factory DonNature.fromJson(Map<String, dynamic> json) => DonNature(
        id: _texte(json['id']),
        memberId: json['member_id'] as String?,
        membreNom: json['membre_nom'] as String?,
        description: _texte(json['description']),
        quantite: _entier(json['quantite']),
        unite: json['unite'] as String?,
        typeDon: _texte(json['type_don']),
        heures: json['heures'] == null ? null : (json['heures'] as num).toDouble(),
        dateDon: _texte(json['date_don']),
        anonyme: json['anonyme'] as bool? ?? false,
      );
}

/// Fiche visiteur (US6).
class Visiteur {
  final String id;
  final String nom;
  final String dateVenue;
  final String? telephone;
  final String? email;
  final String? moyenContact;
  final String statut; // nouveau | recontacte | devenu_membre

  const Visiteur({
    required this.id,
    required this.nom,
    required this.dateVenue,
    this.telephone,
    this.email,
    this.moyenContact,
    required this.statut,
  });

  factory Visiteur.fromJson(Map<String, dynamic> json) => Visiteur(
        id: _texte(json['id']),
        nom: _texte(json['nom']),
        dateVenue: _texte(json['date_venue']),
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        moyenContact: json['moyen_contact'] as String?,
        statut: _texte(json['statut']),
      );
}

/// Alerte pour l'église mère (US11).
class AlerteMere {
  final String id;
  final String annexeId;
  final String? annexeNom;
  final String type; // inactive | baisse_contributions | rapport_manquant
  final String periode;
  final String statut; // ouverte | traitee

  const AlerteMere({
    required this.id,
    required this.annexeId,
    this.annexeNom,
    required this.type,
    required this.periode,
    required this.statut,
  });

  factory AlerteMere.fromJson(Map<String, dynamic> json) => AlerteMere(
        id: _texte(json['id']),
        annexeId: _texte(json['annexe_id']),
        annexeNom: json['annexe_nom'] as String?,
        type: _texte(json['type']),
        periode: _texte(json['periode']),
        statut: _texte(json['statut']),
      );

  bool get estOuverte => statut == 'ouverte';
}

/// Entrée de liste configurable (US12, US13).
class ListeConfigurable {
  final String id;
  final String type; // role | categorie_depense | categorie_recette | statut_membre | departement
  final String libelle;
  final String? niveau;
  final bool archive;

  const ListeConfigurable({
    required this.id,
    required this.type,
    required this.libelle,
    this.niveau,
    required this.archive,
  });

  factory ListeConfigurable.fromJson(Map<String, dynamic> json) =>
      ListeConfigurable(
        id: _texte(json['id']),
        type: _texte(json['type']),
        libelle: _texte(json['libelle']),
        niveau: json['niveau'] as String?,
        archive: json['archive'] as bool? ?? false,
      );
}

/// Rappel d'événement de vie (US7).
class EvenementVie {
  final String memberId;
  final String nom;
  final String type; // anniversaire | mariage | conversion | bapteme
  final String date;
  final int joursRestants;

  const EvenementVie({
    required this.memberId,
    required this.nom,
    required this.type,
    required this.date,
    required this.joursRestants,
  });

  factory EvenementVie.fromJson(Map<String, dynamic> json) => EvenementVie(
        memberId: _texte(json['member_id']),
        nom: _texte(json['nom']),
        type: _texte(json['type']),
        date: _texte(json['date']),
        joursRestants: _entier(json['jours_restants']),
      );
}

/// Transparence financière agrégée (US8) : totaux seulement, aucune
/// ligne nominative.
class Transparence {
  final String eglise;
  final String periode;
  final List<TotalParType> totauxParType;
  final List<DepenseParPoste> depensesParPoste;
  final int totalRecettesFcfa;
  final int totalDepensesFcfa;
  final int soldeFcfa;

  const Transparence({
    required this.eglise,
    required this.periode,
    required this.totauxParType,
    required this.depensesParPoste,
    required this.totalRecettesFcfa,
    required this.totalDepensesFcfa,
    required this.soldeFcfa,
  });

  factory Transparence.fromJson(Map<String, dynamic> json) => Transparence(
        eglise: _texte(json['eglise']),
        periode: _texte(json['periode']),
        totauxParType: (json['totaux_par_type'] as List<dynamic>? ?? const [])
            .map((e) => TotalParType.fromJson(e as Map<String, dynamic>))
            .toList(),
        depensesParPoste:
            (json['depenses_par_poste'] as List<dynamic>? ?? const [])
                .map((e) => DepenseParPoste.fromJson(e as Map<String, dynamic>))
                .toList(),
        totalRecettesFcfa: _entier(json['total_recettes_fcfa']),
        totalDepensesFcfa: _entier(json['total_depenses_fcfa']),
        soldeFcfa: _entier(json['solde_fcfa']),
      );
}

class TotalParType {
  final String type;
  final int totalFcfa;
  final int nombre;

  const TotalParType({
    required this.type,
    required this.totalFcfa,
    required this.nombre,
  });

  factory TotalParType.fromJson(Map<String, dynamic> json) => TotalParType(
        type: _texte(json['type']),
        totalFcfa: _entier(json['total_fcfa']),
        nombre: _entier(json['nombre']),
      );
}

class DepenseParPoste {
  final String poste;
  final int totalFcfa;

  const DepenseParPoste({required this.poste, required this.totalFcfa});

  factory DepenseParPoste.fromJson(Map<String, dynamic> json) =>
      DepenseParPoste(
        poste: _texte(json['poste']),
        totalFcfa: _entier(json['total_fcfa']),
      );
}

/// Carte exportable vers le portefeuille du téléphone (US9). Aucun
/// compte Apple Wallet ni Google Wallet n'est branché : `compteWallet`
/// est null tant qu'Axel n'a pas choisi.
class CartePortefeuille {
  final String nom;
  final String? matricule;
  final String? fonction;
  final String? telephone;
  final String egliseNom;
  final String egliseCode;
  final String qrDonnees;
  final String? compteWallet;
  final String note;

  const CartePortefeuille({
    required this.nom,
    this.matricule,
    this.fonction,
    this.telephone,
    required this.egliseNom,
    required this.egliseCode,
    required this.qrDonnees,
    this.compteWallet,
    required this.note,
  });

  factory CartePortefeuille.fromJson(Map<String, dynamic> json) =>
      CartePortefeuille(
        nom: _texte(json['nom']),
        matricule: json['matricule'] as String?,
        fonction: json['fonction'] as String?,
        telephone: json['telephone'] as String?,
        egliseNom: _texte(json['eglise_nom']),
        egliseCode: _texte(json['eglise_code']),
        qrDonnees: _texte(json['qr_donnees']),
        compteWallet: json['compte_wallet'] as String?,
        note: _texte(json['note']),
      );
}

/// Membre ayant consenti à WhatsApp (US10). Aucun envoi réel : aucun
/// fournisseur n'est branché.
class WhatsappConsentement {
  final String id;
  final String nom;
  final String? telephone;

  const WhatsappConsentement({
    required this.id,
    required this.nom,
    this.telephone,
  });

  factory WhatsappConsentement.fromJson(Map<String, dynamic> json) =>
      WhatsappConsentement(
        id: _texte(json['id']),
        nom: _texte(json['full_name']),
        telephone: json['telephone'] as String?,
      );
}

/// Consentements du membre (US10 WhatsApp, US16 repli SMS).
class MesConsentements {
  final bool whatsapp;
  final bool smsRepli;
  final List<String> evenementsVieMasques;

  const MesConsentements({
    required this.whatsapp,
    required this.smsRepli,
    required this.evenementsVieMasques,
  });

  factory MesConsentements.fromJson(Map<String, dynamic> json) =>
      MesConsentements(
        whatsapp: json['whatsapp_consentement'] as bool? ?? false,
        smsRepli: json['sms_repli_consentement'] as bool? ?? false,
        evenementsVieMasques: _textes(json['evenements_vie_masques']),
      );
}
