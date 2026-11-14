import '../utils/format.dart';

/// Paramètres d'une église (`GET /parametres` : ligne `eglise_parametres`
/// jointe au nom, au code et à la ville de l'église).
class EgliseParametres {
  final String? adresse;
  final String? ville;
  final String? telephone;
  final String? email;
  final String? logoUrl;
  final String? waveNumero;
  final String? orangeNumero;
  final String? mtnNumero;
  final String? devise;
  final String? fuseauHoraire;
  // T10 : signataires configurables, vides par défaut.
  final String? signataireNominations;
  final String? signataireProcesVerbaux;
  // T12 (US8, US11, US14) : dîme suggérée, transparence, seuils d'alerte.
  final int? montantDimeSuggere;
  final bool transparenceVisibleMembres;
  final int seuilInactiviteSemaines;
  final int seuilBaisseContributionsPct;
  final String? egliseNom;
  final String? egliseCode;

  const EgliseParametres({
    this.adresse,
    this.ville,
    this.telephone,
    this.email,
    this.logoUrl,
    this.waveNumero,
    this.orangeNumero,
    this.mtnNumero,
    this.devise,
    this.fuseauHoraire,
    this.signataireNominations,
    this.signataireProcesVerbaux,
    this.montantDimeSuggere,
    this.transparenceVisibleMembres = false,
    this.seuilInactiviteSemaines = 4,
    this.seuilBaisseContributionsPct = 30,
    this.egliseNom,
    this.egliseCode,
  });

  factory EgliseParametres.fromJson(Map<String, dynamic> json) =>
      EgliseParametres(
        adresse: json['adresse'] as String?,
        ville: json['ville'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        logoUrl: json['logo_url'] as String?,
        waveNumero: json['wave_numero'] as String?,
        orangeNumero: json['orange_numero'] as String?,
        mtnNumero: json['mtn_numero'] as String?,
        devise: json['devise'] as String?,
        fuseauHoraire: json['fuseau_horaire'] as String?,
        signataireNominations: json['signataire_nominations'] as String?,
        signataireProcesVerbaux: json['signataire_proces_verbaux'] as String?,
        montantDimeSuggere: json['montant_dime_suggere'] == null
            ? null
            : (json['montant_dime_suggere'] as num).toInt(),
        transparenceVisibleMembres:
            json['transparence_visible_membres'] as bool? ?? false,
        seuilInactiviteSemaines:
            json['seuil_inactivite_semaines'] == null
                ? 4
                : (json['seuil_inactivite_semaines'] as num).toInt(),
        seuilBaisseContributionsPct:
            json['seuil_baisse_contributions_pct'] == null
                ? 30
                : (json['seuil_baisse_contributions_pct'] as num).toInt(),
        egliseNom: json['eglise_nom'] as String?,
        egliseCode: json['eglise_code'] as String?,
      );
}

/// Rôle d'un utilisateur dans son église (`GET /parametres/roles` :
/// `{ roles: [{ user_id, role, full_name, email }] }`).
class RoleEglise {
  final String userId;
  final String role; // admin_eglise | tresorier | responsable_culte | membre
  final String? fullName;
  final String? email;

  const RoleEglise({
    required this.userId,
    required this.role,
    this.fullName,
    this.email,
  });

  factory RoleEglise.fromJson(Map<String, dynamic> json) => RoleEglise(
        userId: json['user_id'] as String,
        role: json['role'] as String,
        fullName: json['full_name'] as String?,
        email: json['email'] as String?,
      );

  static String labelForRole(String role) {
    switch (role) {
      case 'admin_eglise':
        return 'Admin d’église';
      case 'tresorier':
        return 'Trésorier';
      case 'responsable_culte':
        return 'Responsable de culte';
      case 'super_admin':
        return 'Admin plateforme';
      default:
        return 'Membre';
    }
  }

  String get roleLabel => labelForRole(role);
}

/// Entrée du journal d'audit (`GET /audit` :
/// `{ items: [{ id, action, details, created_at, user_nom, hash,
/// hash_precedent }] }`). Lecture seule, chaîne de hachage (T11).
class AuditEntree {
  final String id;
  final String action;
  final Map<String, dynamic>? details;
  final DateTime? createdAt;
  final String? utilisateur;
  final String? hash;
  final String? hashPrecedent;

  const AuditEntree({
    required this.id,
    required this.action,
    this.details,
    this.createdAt,
    this.utilisateur,
    this.hash,
    this.hashPrecedent,
  });

  factory AuditEntree.fromJson(Map<String, dynamic> json) => AuditEntree(
        id: json['id'] as String,
        action: json['action'] as String,
        details: (json['details'] as Map?)?.cast<String, dynamic>(),
        createdAt: parseDate(json['created_at'] as String?),
        utilisateur: (json['utilisateur'] as String?) ??
            json['user_nom'] as String?,
        hash: json['hash'] as String?,
        hashPrecedent: json['hash_precedent'] as String?,
      );
}

/// Libellé français lisible d'une action du journal d'audit, par exemple
/// « modules.modifie » → « Module modifié ». Le serveur journalise des
/// codes, l'écran ne les montre jamais bruts. Repli : le code rendu
/// lisible (tirets et points remplacés, première lettre en majuscule).
String libelleActionAudit(String action) {
  const explicites = <String, String>{
    'annonce.publiee': 'Annonce publiée',
    'annonce.supprimee': 'Annonce supprimée',
    'attestation.corrige': 'Attestation corrigée',
    'attestation.generee': 'Attestation générée',
    'auth.eglise_active_changee': 'Église active changée',
    'auth.invitation_creee': 'Invitation créée',
    'auth.lien_reinitialisation_genere':
        'Lien de réinitialisation généré',
    'auth.login': 'Connexion',
    'auth.login_failed': 'Échec de connexion',
    'auth.mot_de_passe_change': 'Mot de passe changé',
    'auth.mot_de_passe_initialise': 'Mot de passe initialisé',
    'auth.mot_de_passe_oublie': 'Mot de passe oublié',
    'auth.mot_de_passe_reinitialise': 'Mot de passe réinitialisé',
    'campagne.cloturee': 'Campagne clôturée',
    'campagne.creee': 'Campagne créée',
    'campagne.modifiee': 'Campagne modifiée',
    'checkin_enfant.alerte': 'Alerte d’accueil d’enfant',
    'checkin_enfant.cree': 'Arrivée d’enfant enregistrée',
    'checkin_enfant.sortie': 'Sortie d’enfant enregistrée',
    'codes_tutelle.annule': 'Code de tutelle annulé',
    'codes_tutelle.cree': 'Code de tutelle créé',
    'codes_tutelle.utilise': 'Code de tutelle utilisé',
    'contribution.campagne_affectee':
        'Contribution rattachée à une campagne',
    'contribution.enregistree': 'Contribution enregistrée',
    'eglise.inscrite': 'Église inscrite',
    'eglise.logo_televerse': 'Logo de l’église téléversé',
    'eglise.profil_modifie': 'Profil de l’église modifié',
    'eglise.sous_eglise_creee': 'Sous-église créée',
    'fidele.demande_liaison': 'Demande de liaison de fidèle',
    'fidele.inscrit_lie': 'Fidèle inscrit et lié',
    'fidele.inscrit_par_code': 'Fidèle inscrit par code',
    'membre.cree': 'Membre créé',
    'membre.modifie': 'Membre modifié',
    'membre.statut_change': 'Statut de membre changé',
    'membre.supprime': 'Membre supprimé',
    'modules.actives_tutelle': 'Modules activés pour une tutelle',
    'modules.modifie': 'Module modifié',
    'paiement.configure': 'Moyen de paiement configuré',
    'paiement.execute': 'Paiement exécuté',
    'paiement.supprime': 'Moyen de paiement supprimé',
    'paiement.teste': 'Paiement testé',
    'parametres.modifies': 'Paramètres modifiés',
    'plateforme.chiffres_consultes': 'Chiffres de la plateforme consultés',
    'presence.pointee': 'Présence pointée',
    'pret_livre.rendu': 'Livre rendu',
    'rapport.detail_consulte': 'Rapport détaillé consulté',
    'rattachement.demande': 'Demande de rattachement',
    'role.modifie': 'Rôle modifié',
    'transfert.annule': 'Transfert annulé',
    'transfert.demande': 'Demande de transfert',
    'transfert.effectue': 'Transfert effectué',
  };
  final explicite = explicites[action];
  if (explicite != null) return explicite;
  // Actions génériques du CRUD (`<objet>.cree / .modifie / .supprime`) :
  // nom de l'objet et genre, pour accorder le participe.
  const noms = <String, (String, bool)>{
    'accompagnement': ('Accompagnement', false),
    'activite_jeunesse': ('Activité jeunesse', true),
    'autorisation_sortie': ('Autorisation de sortie', true),
    'bapteme': ('Baptême', false),
    'budget': ('Budget', false),
    'caisse': ('Caisse', true),
    'cellule': ('Cellule', true),
    'classe_enfant': ('Classe d’enfant', true),
    'culte': ('Culte', false),
    'culte_type': ('Type de culte', false),
    'demande_priere': ('Demande de prière', true),
    'departement': ('Département', false),
    'depense': ('Dépense', true),
    'enseignant_classe': ('Enseignant de classe', false),
    'evenement_special': ('Événement spécial', false),
    'famille': ('Famille', true),
    'fonction': ('Fonction', true),
    'lien_parent_enfant': ('Lien parent-enfant', false),
    'livre': ('Livre', false),
    'maintenance_materiel': ('Maintenance du matériel', true),
    'materiel': ('Matériel', false),
    'membre_cellule': ('Membre de cellule', false),
    'membre_departement': ('Membre de département', false),
    'membre_statut': ('Statut de membre', false),
    'message_interne': ('Message interne', false),
    'ordre_culte': ('Ordre du culte', false),
    'parcours_nouveau': ('Parcours nouveau', false),
    'plan_lecture': ('Plan de lecture', false),
    'planning_serviteur': ('Planning de serviteur', false),
    'poste': ('Poste', false),
    'poste_budgetaire': ('Poste budgétaire', false),
    'predication': ('Prédication', true),
    'presence': ('Présence', true),
    'pret_livre': ('Prêt de livre', false),
    'reservation_salle': ('Réservation de salle', true),
    'salle': ('Salle', true),
    'serviteur': ('Serviteur', false),
    'visite_pastorale': ('Visite pastorale', true),
  };
  final parties = action.split('.');
  if (parties.length == 2) {
    final nom = noms[parties[0]];
    if (nom != null) {
      final (label, feminin) = nom;
      final participe = switch (parties[1]) {
        'cree' => feminin ? 'créée' : 'créé',
        'modifie' => feminin ? 'modifiée' : 'modifié',
        'supprime' => feminin ? 'supprimée' : 'supprimé',
        _ => parties[1],
      };
      return '$label $participe';
    }
  }
  final lisible = action.replaceAll('_', ' ').replaceAll('.', ' — ');
  return lisible.isEmpty
      ? action
      : '${lisible[0].toUpperCase()}${lisible.substring(1)}';
}
