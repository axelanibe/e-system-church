import 'dart:typed_data';

import '../models/abonnement.dart';
import '../models/attestation.dart';
import '../models/annexe.dart';
import '../models/anniversaire.dart';
import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/biens.dart';
import '../models/campagne.dart';
import '../models/church.dart';
import '../models/code_tutelle.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/checkin_enfant.dart';
import '../models/enfants.dart';
import '../models/fidele.dart';
import '../models/confiance.dart';
import '../models/finances.dart';
import '../models/frequentation.dart';
import '../models/gouvernance.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../models/nettoyage_test.dart';
import '../models/suppression_eglise.dart';
import '../models/paiements.dart';
import '../models/parametres.dart';
import '../models/pastoral.dart';
import '../models/presences.dart';
import '../models/prieres.dart';
import '../models/profil.dart';
import '../models/plateforme.dart';
import '../models/acces_plateforme.dart';
import '../models/transfert.dart';
import '../models/rapport.dart';
import '../models/rapport_annexe.dart';
import '../models/rattachement.dart';
import '../models/serviteurs.dart';
import '../models/stats.dart';
import '../models/sycebnl.dart';
import '../models/us_restantes.dart';

/// Erreur renvoyée par l'API (ou par le service en mode démo).
/// `code` est le code d'erreur du serveur (`code_2fa_requis`,
/// `hors_ligne`…) quand il existe : les écrans décident avec lui,
/// pas avec le texte du message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ApiException(this.message, [this.statusCode, this.code]);

  @override
  String toString() => message;
}

/// Interface unique parlée par les écrans. Une seule implémentation :
/// [HttpApiService] (API réelle). Les écrans ne connaissent que cette
/// interface. Les listes vides restent vides : l'écran affiche un état vide.
abstract class ApiService {
  // -- Authentification -----------------------------------------------------
  /// Connexion par e-mail ou par téléphone : `identifiant` est l'un ou
  /// l'autre, le mot de passe est le même dans les deux cas. Avec
  /// `plateforme: true`, seule une connexion Plateforme est acceptée
  /// (admin de la plateforme ou aide) ; sinon, seules les connexions
  /// églises et membres le sont.
  Future<AuthResult> login(
      {required String identifiant,
      required String password,
      bool plateforme = false,
      String? code2fa});

  Future<AuthResult> register({
    required String churchName,
    required String city,
    String? churchPhone,
    String? churchEmail,
    required String adminName,
    required String adminEmail,
    String? adminPhone,
    required String password,
    String? parentCode,
    // Logo choisi à l'inscription (facultatif) : téléversé après la
    // création de l'église, comme dans Mon église.
    String? logoBase64,
    String? logoFilename,
  });

  Future<MeResult> me();

  // -- Mot de passe et accès fidèle (modules 15-16) -------------------------
  /// Demande de réinitialisation : renvoie vrai si un e-mail a été envoyé
  /// (faux si le SMTP n'est pas configuré — l'admin transmet le lien).
  /// La réponse ne révèle jamais si l'e-mail existe.
  Future<bool> forgotPassword({required String email});

  /// Réinitialisation par jeton (lien reçu par e-mail ou de l'admin).
  Future<void> resetPassword({required String token, required String password});

  /// Initialisation du mot de passe par jeton d'invitation.
  Future<void> initPassword({required String token, required String password});

  /// Changement de mot de passe (connecté) : vérifie l'ancien.
  Future<void> changePassword({required String ancien, required String nouveau});

  /// Invitation par l'admin : crée le compte (sans mot de passe) et renvoie
  /// le lien d'invitation à transmettre. `memberId` lie la fiche membre.
  Future<String> inviter({
    required String email,
    required String role,
    String? memberId,
    String? fullName,
  });

  /// Lien de réinitialisation généré par l'admin (sans SMTP).
  Future<String> adminResetLink({required String email});

  /// Inscription fidèle par matricule : liée immédiatement (avec session)
  /// si l'e-mail concorde avec la fiche membre, demande en attente sinon.
  /// Ancien parcours, conservé côté serveur ; l'écran n'y renvoie plus.
  /// `codeFidele` (optionnel) restreint la recherche du matricule à
  /// l'église de ce code, pour éviter l'inscription dans la mauvaise
  /// église (le matricule est unique par église, pas global).
  Future<FideleInscriptionResult> registerFidele({
    required String email,
    required String password,
    required String matricule,
    String? codeFidele,
  });

  /// Inscription membre par code fidèle, sans validation : le code fait
  /// foi, le matricule est attribué automatiquement, la fiche membre et
  /// la carte sont créées tout de suite, le compte est lié immédiatement.
  /// `codeEglise` est le code fidèle de l'église (ESC-F-…), pas le code
  /// de tutelle (ESC-…, réservé aux églises qui se rattachent).
  Future<FideleInscriptionResult> registerMembreParCode({
    required String nomPrenom,
    required String email,
    required String telephone,
    required String password,
    required String codeEglise,
    String? birthDate,
    String? sexe,
    String? department,
    String? fonction,
  });

  /// Mon profil fidèle (`GET /moi`) : utilisateur, église, rôle, membre lié.
  Future<FideleProfil> getMoi();

  /// Demandes de liaison en attente de mon église (admin).
  Future<List<DemandeLiaison>> getDemandesLiaison();

  /// Valider / refuser une demande de liaison (admin).
  Future<void> decideDemandeLiaison(String id, {required bool accept});

  // -- Lectures fidèle (rôle membre, son église, ses données) ---------------
  Future<List<Announcement>> getMesAnnonces();

  /// Nombre de mes annonces non lues (migration 018).
  Future<int> getAnnoncesNonLues();

  /// Marquer une de mes annonces comme lue (idempotente).
  Future<void> marquerAnnonceLue(String id);

  Future<List<Culte>> getMesCultes();

  Future<List<Presence>> getMesPresences();

  Future<List<Contribution>> getMesContributions();

  /// Mes attestations annuelles de dons (US3, rôle membre, les miennes).
  Future<List<Attestation>> getMesAttestations();

  /// Ma carte de membre (fiche + église).
  Future<MaCarte> getMaCarte();

  /// Mon fil de messages avec mon église mère ou ma tutelle
  /// (migration 020) : conversation privée, dans l'application.
  Future<FilMessages> getMesMessages();

  /// Écrire un message à mon église mère ou à ma tutelle (migration 020).
  Future<MessageFidele> envoyerMessageFidele({required String corps});

  /// « Je serai présent » au prochain culte (migration 020) : annonce
  /// de présence, sans pointage.
  Future<void> confirmerPresenceCulte(String culteId);

  /// Annuler ma confirmation de présence à un culte (migration 020).
  Future<void> annulerPresenceCulte(String culteId);

  /// Mon abonnement (tranche P3, migration 021) : l'abonnement de mon
  /// église mère, ou la couverture par la mère si je suis une annexe.
  Future<Abonnement> getMonAbonnement();

  /// Valider un code promo pour la durée choisie (tranche P3) : la
  /// réduction dépend du code. Code inconnu, inactif ou hors dates :
  /// refusé (ApiException).
  Future<ValidationCodePromo> validerCodePromo({
    required String code,
    required int dureeAnnees,
  });

  /// Mes demandes de rendez-vous auprès de mon pasteur (migration 022).
  Future<List<RendezVous>> getMesRendezVous();

  /// Demander un rendez-vous auprès de mon pasteur (migration 022) :
  /// date souhaitée au format AAAA-MM-JJ, créneau facultatif,
  /// motif obligatoire.
  Future<RendezVous> demanderRendezVous({
    required String dateSouhaitee,
    String? creneau,
    required String motif,
  });

  /// Tranche P5 — Rapports à mon église mère (migration 023) : mon
  /// église mère, racine du réseau, avec son adresse e-mail, nulle
  /// tant qu'elle n'est pas renseignée en base (« À compléter »).
  Future<EgliseMereContact> getMaMere();

  /// Envoyer un rapport à mon église mère (tranche P5) : le rapport
  /// est enregistré avec ses chiffres réels, statut
  /// `en_attente_envoi`. L'envoi par e-mail, en pièce jointe PDF,
  /// passe par mailer.ts (Lot B) et reste en attente.
  Future<RapportAnnexe> envoyerRapportAnnexe({
    required String type,
    String? message,
    required int membres,
    required int recettesFcfa,
    required int depensesFcfa,
    required int soldeFcfa,
  });

  /// Rapports reçus par mon église mère (tranche P5) : ceux envoyés
  /// par ses églises annexes, le plus récent d'abord.
  Future<List<RapportAnnexe>> getRapportsRecus();

  // -- Églises et arborescence ----------------------------------------------
  Future<TreeResult> getTree();

  Future<Church> createSubChurch({
    required String name,
    required String city,
    String? phone,
    String? email,
  });

  // -- Rattachements ---------------------------------------------------------
  Future<RattachementsResult> getRattachements();

  Future<Rattachement> requestRattachement({
    required String parentCode,
    String? codeTutelle,
  });

  Future<void> decideRattachement(String id, {required bool accept});

  // -- Annexes et codes de tutelle (migration 009) -------------------------
  // La mère voit ses annexes sans changer d'église ; les codes de tutelle
  // ESC-T-… sont à usage unique.
  Future<List<Annexe>> getAnnexes({String? q});

  Future<AnnexeDetail> getAnnexeDetail(String id);

  Future<List<CodeTutelle>> getCodesTutelle();

  Future<CodeTutelle> createCodeTutelle();

  Future<void> annulerCodeTutelle(String id);

  /// Nettoyage des données TEST : aperçu puis suppression confirmée.
  /// Admin d'église seulement, côté serveur.
  Future<NettoyageTestApercu> getNettoyageTestApercu();

  Future<NettoyageTestResultat> executerNettoyageTest();

  /// Suppression d'une église entière : aperçu puis suppression confirmée.
  /// Sans `egliseId` : sa propre église TEST (admin d'église seulement).
  /// Avec `egliseId` : une annexe directe (mère) ou n'importe quelle
  /// annexe (super admin). Côté serveur.
  Future<SuppressionEgliseApercu> getSuppressionEgliseApercu({String? egliseId});

  Future<SuppressionEgliseResultat> executerSuppressionEglise({String? egliseId});

  Future<TransfertsResult> getTransferts();

  Future<TransfertMembre> requestTransfert({
    required String matricule,
    required String destinationCode,
    String? motif,
  });

  Future<void> decideTransfert(String id, {required bool accept});

  Future<void> annulerTransfert(String id);

  // -- Membres ---------------------------------------------------------------
  Future<MemberPage> getMembers(
      {String? q,
      String? department,
      String? status,
      int? limit,
      int? offset});

  Future<Member> getMember(String id);

  Future<Member> createMember({
    required String fullName,
    String? phone,
    String? email,
    String? birthDate,
    String? sexe,
    String? department,
    String? fonction,
    String? poste,
    String? cellGroup,
    String? status,
    String? dateMariage,
    String? dateConversion,
  });

  Future<Member> updateMember(String id,
      {required String fullName,
      String? phone,
      String? email,
      String? birthDate,
      String? sexe,
      String? department,
      String? fonction,
      String? poste,
      String? cellGroup,
      String? status,
      String? dateMariage,
      String? dateConversion});

  Future<void> deleteMember(String id);

  /// Anniversaires proches (`GET /membres/anniversaires`) : la liste
  /// seulement, aucun message envoyé (tranche T4).
  Future<List<Anniversaire>> getAnniversaires({int jours = 30});

  /// Fréquentation d'un membre (`GET /membres/:id/frequentation`).
  Future<Frequentation> getFrequentation(String memberId);

  // -- Import des fidèles (tranche A) ----------------------------------------
  // Modèle CSV, aperçu avant import, confirmation, historique. Les lignes
  // peuvent venir d'un CSV lu en texte ou d'un XLSX lu côté client.
  Future<Uint8List> telechargerModeleImport();

  Future<Map<String, dynamic>> apercuImport({
    String? contenuCsv,
    List<Map<String, String>>? lignes,
    Map<String, String>? mapping,
    String? nomFichier,
  });

  Future<Map<String, dynamic>> confirmerImport({
    String? contenuCsv,
    List<Map<String, String>>? lignes,
    Map<String, String>? mapping,
    String? nomFichier,
  });

  Future<List<Map<String, dynamic>>> historiqueImports();

  // -- Membres (complément, module 1) ----------------------------------------
  Future<List<Famille>> getFamilles();

  Future<Famille> createFamille({
    required String nom,
    String? chefFamilleId,
    String? adresse,
    String? telephone,
  });

  Future<void> deleteFamille(String id);

  Future<List<MembreStatut>> getMembreStatuts(String memberId);

  Future<MembreStatut> changerStatutMembre(String memberId,
      {required String statut, String? motif});

  Future<List<Bapteme>> getBaptemes({String? memberId});

  Future<Bapteme> createBapteme({
    required String memberId,
    required String dateBapteme,
    String? lieu,
    String? pasteur,
    String? certificatNumero,
  });

  Future<List<LienParentEnfant>> getLiensParentEnfant(
      {String? enfantMemberId, String? parentMemberId});

  Future<LienParentEnfant> createLienParentEnfant({
    required String parentMemberId,
    required String enfantMemberId,
    required String lien,
  });

  Future<List<Departement>> getDepartements();

  Future<Departement> createDepartement({
    required String nom,
    String? description,
    String? responsableMemberId,
  });

  Future<void> deleteDepartement(String id);

  Future<Departement> updateDepartement(String id, {required String nom});

  /// Fonctions de l'église (`fonctions`, catalogue amorcé avec les 11
  /// choix). La suppression est refusée si des membres portent la fonction.
  Future<List<Fonction>> getFonctions();

  Future<Fonction> createFonction({required String nom});

  Future<Fonction> updateFonction(String id, {required String nom});

  Future<void> deleteFonction(String id);

  /// Postes de l'église (`postes`, catalogue amorcé avec les 5 postes
  /// d'exemple du document d'architecture). La suppression est refusée
  /// si des membres occupent le poste.
  Future<List<Poste>> getPostes();

  Future<Poste> createPoste({required String nom});

  Future<Poste> updatePoste(String id, {required String nom});

  Future<void> deletePoste(String id);

  Future<List<Cellule>> getCellules();

  Future<Cellule> createCellule({
    required String nom,
    String? quartier,
    String? responsableMemberId,
    String? jourReunion,
    String? heureReunion,
  });

  Future<void> deleteCellule(String id);

  /// Fiche membre enrichie (`GET /membres/:id/complet` : membre, historique
  /// des statuts, baptême, départements, cellules, enfants, parents).
  Future<Map<String, dynamic>> getMembreComplet(String memberId);

  // -- Cultes et programmes (module 2) ---------------------------------------
  Future<List<CulteType>> getCulteTypes();

  Future<CulteType> createCulteType({
    required String nom,
    int? jourSemaine,
    String? heureDebut,
    int? dureeMinutes,
    String? lieu,
  });

  Future<List<Culte>> getCultes();

  Future<Culte> createCulte({
    String? culteTypeId,
    required String titre,
    required String dateHeure,
    String? lieu,
    String? orateur,
    String? theme,
  });

  Future<void> deleteCulte(String id);

  Future<List<OrdreCulteItem>> getOrdreCulte(String culteId);

  Future<OrdreCulteItem> createOrdreCulteItem({
    required String culteId,
    required String titre,
    int ordre = 0,
    String? description,
    String? intervenant,
    int? dureeMinutes,
  });

  Future<List<EvenementSpecial>> getEvenementsSpeciaux({String? type});

  Future<EvenementSpecial> createEvenementSpecial({
    required String type,
    required String titre,
    required String dateDebut,
    String? dateFin,
    String? description,
    String? lieu,
    String? responsable,
  });

  // -- Présences (module 3) --------------------------------------------------
  Future<List<Presence>> getPresences(
      {String? culteId, String? eventId, String? memberId});

  Future<Presence> pointerPresence({
    String? matricule,
    String? memberId,
    String? culteId,
    String? eventId,
    String statut = 'present',
    String mode = 'scan_qr',
  });

  Future<PresenceStats> getPresenceStats({String? from, String? to});

  // -- Finances (module 4) ---------------------------------------------------
  Future<List<PosteBudgetaire>> getPostesBudgetaires({String? categorie});

  Future<PosteBudgetaire> createPosteBudgetaire({
    required String nom,
    required String categorie,
    String? description,
  });

  Future<void> deletePosteBudgetaire(String id);

  Future<List<Budget>> getBudgets({int? annee});

  Future<Budget> createBudget({
    required String posteId,
    required int annee,
    required int montantPrevu,
  });

  Future<void> deleteBudget(String id);

  Future<List<Depense>> getDepenses({String? statut});

  Future<Depense> createDepense({
    String? posteId,
    required int montantFcfa,
    required String motif,
    String? justificatifRef,
    String? dateDepense,
  });

  Future<void> deleteDepense(String id);

  Future<Depense> setDepenseStatut(String id, String statut);

  Future<List<CaisseMouvement>> getCaisseMouvements({String? type});

  Future<CaisseMouvement> createCaisseMouvement({
    required String type,
    required int montantFcfa,
    required String motif,
    String? reference,
  });

  Future<CaisseSolde> getCaisseSolde();

  Future<RapportFinancier> getRapportFinancier(
      {int? annee, String? from, String? to});

  // -- Finances (contributions, existant) ------------------------------------
  Future<ContributionPage> getContributions({String? type, String? status});

  Future<Contribution> getReceipt(String id);

  Future<Contribution> createContribution({
    required String type,
    required int amountFcfa,
    required String paymentMethod,
    String? paymentRef,
    String? memberId,
    String? campagneId,
    String? note,
  });

  Future<Contribution> setContributionStatus(String id, String status);

  // -- Finances complètes (tranche T7) --------------------------------------
  Future<CotisationConfig?> getCotisationsConfig();

  Future<CotisationConfig> saveCotisationsConfig({
    required int montantFcfa,
    String? periodicite,
    bool? actif,
  });

  Future<SuiviCotisations> getCotisationsSuivi({String? periode});

  Future<List<CompteBancaire>> getComptesBancaires();

  Future<CompteBancaire> createCompteBancaire({
    required String banque,
    String? titulaire,
    String? numeroCompte,
    String type = 'banque',
    String devise = 'FCFA',
  });

  Future<CompteBancaire> updateCompteBancaire(
    String id, {
    String? banque,
    String? titulaire,
    String? numeroCompte,
    String? type,
    String? devise,
    bool? actif,
  });

  Future<void> deleteCompteBancaire(String id);

  Future<Rapprochement> getRapprochement({int? annee, int? mois});

  Future<List<ClotureCaisse>> getCloturesCaisse();

  Future<ClotureCaisse> cloturerCaisse({
    required String periode,
    int? soldeCompteFcfa,
    String? commentaire,
  });

  /// Reçu numéroté en PDF (octets) : `GET /contributions/:id/recu.pdf`.
  Future<Uint8List> telechargerRecuPdf(String id);

  // -- Campagnes de collecte (US2) -----------------------------------------
  Future<List<Campagne>> getCampagnes();

  Future<Campagne> createCampagne({
    required String nom,
    required int objectifFcfa,
    required String dateDebut,
    required String dateFin,
    String statut = 'brouillon',
    bool visibleMembres = false,
  });

  Future<Campagne> setCampagneStatut(String id, String statut);

  Future<void> cloturerCampagne(String id);

  Future<Contribution> affecterContributionCampagne(String id, String? campagneId);

  // -- Attestations annuelles de dons (US3, trésorier / admin) --------------
  /// Liste de mon église, filtres par année et par type. Génère pour tous
  /// les donateurs identifiés avec au moins un don confirmé cette année
  /// (ne régénère pas une attestation émise existante).
  Future<List<Attestation>> getAttestations({int? annee, String? type});

  Future<List<Attestation>> genererAttestations({required int annee});

  /// Émet une attestation d'événement (mariage, naissance, baptême)
  /// pour un membre : la date de l'événement est obligatoire, lieu,
  /// officiant et champs propres au type sont facultatifs.
  Future<Attestation> emettreAttestation({
    required String type,
    required String memberId,
    required String dateEvenement,
    String? lieu,
    String? officiant,
    String? conjointNom,
    String? pereNom,
    String? mereNom,
    String? parrainNom,
    String? marraineNom,
  });

  /// Nouvelle attestation qui annule l'ancienne (motif obligatoire).
  /// Pour un événement, seuls les champs fournis changent.
  Future<Attestation> corrigerAttestation(String id,
      {required String motif,
      String? dateEvenement,
      String? lieu,
      String? officiant,
      String? conjointNom,
      String? pereNom,
      String? mereNom,
      String? parrainNom,
      String? marraineNom});

  /// PDF de l'attestation (octets bruts, contenu figé).
  Future<Uint8List> telechargerAttestationPdf(String id);

  // -- Communication : prières et messages (module 5) ------------------------
  Future<List<DemandePriere>> getDemandesPriere({String? statut});

  Future<DemandePriere> createDemandePriere({
    required String sujet,
    String? memberId,
    String? demandeurNom,
    String? details,
    bool confidentiel = false,
  });

  Future<void> deleteDemandePriere(String id);

  Future<DemandePriere> setDemandePriereStatut(String id, String statut);

  Future<List<MessageInterne>> getMessagesInternes();

  Future<MessageInterne> createMessageInterne({
    required String sujet,
    required String corps,
    String? destinataireId,
  });

  // -- Suivi pastoral (module 6) ---------------------------------------------
  Future<List<ParcoursNouveau>> getParcoursNouveaux({String? etape});

  Future<ParcoursNouveau> createParcoursNouveau({
    required String memberId,
    String etape = 'accueil',
    String? note,
  });

  Future<ParcoursNouveau> setParcoursEtape(String id, String etape);

  /// Radar des absences consécutives (T6, vue calculée) : seuil de 1 à
  /// 10, 3 par défaut.
  Future<List<AlerteRadar>> getRadarAbsences({int seuil = 3});

  /// Rendez-vous de l'église, côté admin (T6, table 022 réutilisée).
  Future<List<RendezVous>> getRendezVousAdmin({String? statut});

  /// Machine à états d'un rendez-vous (T6) : confirme exige un créneau
  /// (400 sinon), refuse depuis en attente, annule depuis confirmé.
  Future<RendezVous> setRendezVousStatut(String id, String statut,
      {String? creneau});

  /// Tableau des cas ouverts (T6) : accompagnements en cours, par
  /// défaut les personnes en difficulté, triés par le serveur
  /// (priorité puis ancienneté).
  Future<List<Accompagnement>> getCasOuverts(
      {String type = 'difficulte', String? priorite});

  /// Rencontres datées d'un accompagnement (T6).
  Future<List<RencontreAccompagnement>> getRencontresAccompagnement(
      String accompagnementId);

  Future<RencontreAccompagnement> createRencontreAccompagnement({
    required String accompagnementId,
    required String dateRencontre,
    String? note,
  });

  /// Priorité d'un accompagnement (T6) : basse, normale, haute, urgente.
  Future<Accompagnement> setAccompagnementPriorite(
      String id, String priorite);

  Future<List<VisitePastorale>> getVisitesPastorales(
      {String? statut, String? type});

  Future<VisitePastorale> createVisitePastorale({
    required String memberId,
    required String dateVisite,
    String? motif,
    String? compteRendu,
    String? type,
    String? lieu,
  });

  Future<List<Accompagnement>> getAccompagnements(
      {String? type, String? statut});

  Future<Accompagnement> createAccompagnement({
    required String memberId,
    required String type,
    String? description,
    String priorite = 'normale',
  });

  // -- Serviteurs (module 7) -------------------------------------------------
  Future<List<Serviteur>> getServiteurs({String? departementId});

  Future<Serviteur> createServiteur({
    required String memberId,
    required String departementId,
    String role = 'serviteur',
    String? disponibilite,
  });

  Future<void> deleteServiteur(String id);

  Future<List<PlanningServiteur>> getPlanningServiteurs();

  Future<PlanningServiteur> createPlanningServiteur({
    required String serviteurId,
    required String dateService,
    String? culteId,
    String? roleService,
  });

  // -- Enfants et jeunesse (module 8) -----------------------------------------
  Future<List<ClasseEnfant>> getClassesEnfants();

  Future<ClasseEnfant> createClasseEnfant({
    required String nom,
    int? ageMin,
    int? ageMax,
    String? salle,
  });

  Future<void> deleteClasseEnfant(String id);

  Future<List<AutorisationSortie>> getAutorisationsSorties({String? statut});

  Future<AutorisationSortie> createAutorisationSortie({
    required String enfantMemberId,
    required String activite,
    required String dateSortie,
    String? parentMemberId,
  });

  Future<AutorisationSortie> setAutorisationStatut(String id, String statut);

  Future<List<ActiviteJeunesse>> getActivitesJeunesse();

  Future<ActiviteJeunesse> createActiviteJeunesse({
    required String titre,
    required String dateActivite,
    String? description,
    String? lieu,
    String? responsableMemberId,
  });

  // -- Check-ins enfants, double QR ECODIM ------------------------------------
  // Arrivée jumelée (code parent + code enfant), sortie sécurisée par le
  // code enfant, alerte silencieuse au parent (enregistrement en base).
  Future<CheckinEnfant> checkinEnfant({
    required String enfantMemberId,
    required String parentMemberId,
    required String codeParent,
    required String codeEnfant,
    String? salle,
    String? allergie,
  });

  Future<CheckinEnfant> sortieEnfant({
    required String checkinId,
    required String codeEnfant,
    required String codeParent,
  });

  Future<CheckinEnfant> alerteCheckinEnfant({
    required String checkinId,
    required String message,
  });

  Future<List<CheckinEnfant>> getCheckinsEnfantsJour({String? salle});

  // -- Médias et enseignements (module 9) ------------------------------------
  Future<List<Predication>> getPredications();

  Future<Predication> createPredication({
    required String titre,
    required String datePredication,
    String? orateur,
    String? serie,
    String? urlAudio,
    String? urlVideo,
  });

  Future<List<PlanLecture>> getPlansLecture();

  Future<PlanLecture> createPlanLecture({
    required String nom,
    String? description,
    int? dureeJours,
  });

  Future<List<Livre>> getLivres();

  Future<Livre> createLivre({
    required String titre,
    String? auteur,
    String? categorie,
    int exemplaires = 1,
  });

  Future<void> deleteLivre(String id);

  Future<List<PretLivre>> getPretsLivres({String? statut});

  Future<PretLivre> createPretLivre({
    required String livreId,
    required String memberId,
    String? dateRetourPrevue,
  });

  Future<PretLivre> rendreLivre(String id);

  // -- Biens et inventaire (module 10) ---------------------------------------
  Future<List<Salle>> getSalles();

  Future<Salle> createSalle({
    required String nom,
    int? capacite,
    String? description,
  });

  Future<void> deleteSalle(String id);

  Future<List<ReservationSalle>> getReservationsSalles({String? salleId});

  Future<ReservationSalle> createReservationSalle({
    required String salleId,
    required String titre,
    required String debut,
    required String fin,
    String? reservePar,
  });

  Future<List<Materiel>> getMateriel({String? etat});

  Future<Materiel> createMateriel({
    required String nom,
    String? categorie,
    int quantite = 1,
    String etat = 'bon',
    String? responsableMemberId,
  });

  Future<List<MaintenanceMateriel>> getMaintenanceMateriel({String? materielId});

  Future<MaintenanceMateriel> createMaintenanceMateriel({
    required String materielId,
    required String description,
    String? dateMaintenance,
    int? coutFcfa,
    String? realisePar,
  });

  // -- Gouvernance, secrétariat, documents, action sociale (T10) ------------
  Future<List<ReunionConseil>> getReunionsConseil({String? statut});

  Future<ReunionConseil> createReunionConseil({
    required String titre,
    required String dateReunion,
    String? lieu,
    String? ordreDuJour,
    String statut = 'prevue',
  });

  Future<void> deleteReunionConseil(String id);

  Future<List<Decision>> getDecisions({String? statut, String? reunionId});

  Future<Decision> createDecision({
    String? reunionId,
    required String titre,
    String? description,
    String? dateDecision,
    String statut = 'adoptee',
  });

  Future<void> deleteDecision(String id);

  /// Mandats en cours (`statut: 'en_cours'`) ou tous les mandats
  /// (les nominations : l'historique des nominations).
  Future<List<Mandat>> getMandats({String? statut});

  Future<Mandat> createMandat({
    required String memberId,
    required String fonction,
    required String dateDebut,
    String? dateFin,
    String? decisionId,
  });

  Future<Mandat> terminerMandat(String id);

  Future<void> deleteMandat(String id);

  Future<List<ProcesVerbal>> getProcesVerbaux({String? statut, String? reunionId});

  Future<ProcesVerbal> createProcesVerbal({
    String? reunionId,
    String? numero,
    required String contenu,
    String? datePv,
    String? signataire,
  });

  Future<ProcesVerbal> signerProcesVerbal(String id, {required String signataire});

  Future<void> deleteProcesVerbal(String id);

  /// Documents classés, avec recherche et filtres (catégorie, sens).
  Future<List<GouvernanceDocument>> getDocuments(
      {String? q, String? categorie, String? sens});

  Future<GouvernanceDocument> createDocument({
    required String titre,
    String categorie = 'autre',
    String? sens,
    String? reference,
    String? fichierUrl,
    String? description,
    String? dateDocument,
  });

  Future<void> deleteDocument(String id);

  Future<List<Beneficiaire>> getBeneficiaires({String? statut});

  Future<Beneficiaire> createBeneficiaire({
    required String nom,
    String? telephone,
    String? adresse,
    String? besoin,
    String? memberId,
  });

  Future<void> deleteBeneficiaire(String id);

  Future<List<Aide>> getAides({String? beneficiaireId, String? statut});

  Future<Aide> createAide({
    required String beneficiaireId,
    required String typeAide,
    int? montantFcfa,
    String? dateAide,
    String? description,
  });

  Future<Aide> marquerAideVersee(String id);

  Future<void> deleteAide(String id);

  // -- Patrimoine (T10, avec les biens) ---------------------------------------
  Future<List<BienPatrimoine>> getBiensPatrimoine({String? categorie});

  Future<BienPatrimoine> createBienPatrimoine({
    required String nom,
    required String categorie,
    int? valeurFcfa,
    String? assurance,
    String? photoUrl,
    String? codeInventaire,
  });

  Future<void> deleteBienPatrimoine(String id);

  Future<List<MaintenancePatrimoine>> getMaintenancePatrimoine({String? bienId});

  Future<MaintenancePatrimoine> createMaintenancePatrimoine({
    required String bienId,
    required String description,
    String? dateMaintenance,
    int? coutFcfa,
    String? realisePar,
    String? depenseId,
  });

  // -- Statistiques et export (module 11) ------------------------------------
  Future<StatsGlobales> getStatsGlobales();

  /// Export CSV (`membres` ou `contributions`) : renvoie le contenu brut.
  Future<String> exportCsv(String type);

  // -- Exports PDF (tranche C) ------------------------------------------------
  /// PDF bruts (octets) des exports : détail et résumé des finances
  /// (admin et trésorier), cultes (tous les rôles de l'église), rapport
  /// consolidé (admin seulement). Mêmes droits que les routes GET
  /// correspondantes, le serveur refuse le reste (403).
  Future<Uint8List> exporterFinancesDetailPdf({String? from, String? to});

  Future<Uint8List> exporterFinancesResumePdf(
      {String? from, String? to, int? annee});

  Future<Uint8List> exporterCultesPdf({String? from, String? to});

  Future<Uint8List> exporterRapportConsolidePdf();

  // -- Plan comptable des dépenses (tranche dépenses prévisibles) ------------
  /// Les dix catégories comptables globales.
  Future<List<CategorieDepense>> getCategoriesDepenses();

  /// Crée un poste avec catégorie comptable et marqueur récurrente.
  Future<PosteBudgetaire> creerPostePlanComptable({
    required String nom,
    required String categorie,
    String? description,
    String? categorieId,
    bool estRecurrente = false,
  });

  /// Change la catégorie comptable et le marqueur récurrente d'un poste.
  Future<PosteBudgetaire> modifierPostePlanComptable({
    required String id,
    String? categorieId,
    required bool estRecurrente,
  });

  Future<List<BudgetMensuel>> getBudgetsMensuels(
      {int? annee, int? mois, String? posteId});

  /// Crée ou remplace le budget mensuel d'un poste.
  Future<BudgetMensuel> creerBudgetMensuel({
    required String posteId,
    required int annee,
    required int mois,
    required int montantPrevu,
  });

  Future<void> supprimerBudgetMensuel(String id);

  /// Crée une dépense avec tous les champs du plan comptable.
  /// La référence DEP-AAAA-NNNN est générée par le serveur.
  Future<Depense> creerDepenseComplete({
    String? posteId,
    required int montantFcfa,
    required String motif,
    String? justificatifRef,
    String? dateDepense,
    String? departementId,
    String? modePaiement,
    String? fournisseurBeneficiaire,
    String? responsableDepense,
    String? responsableAutorisation,
    String? devise,
  });

  /// Prévu mensuel contre réel, par catégorie et par poste.
  Future<SuiviMensuel> getSuiviMensuel(
      {required int annee, required int mois});

  /// Budgets mensuels par département (tranche T7).
  Future<List<BudgetDepartement>> getBudgetsDepartements(
      {int? annee, int? mois, String? departementId});

  /// Crée ou remplace le budget mensuel d'un département.
  Future<BudgetDepartement> creerBudgetDepartement({
    required String departementId,
    required int annee,
    required int mois,
    required int montantPrevu,
  });

  Future<void> supprimerBudgetDepartement(String id);

  /// Prévu mensuel contre réel, par département, avec alerte de dépassement.
  Future<SuiviDepartements> getSuiviDepartements(
      {required int annee, required int mois});

  /// Rapport des dépenses, mensuel (mois donné) ou annuel.
  Future<RapportPlanComptable> getRapportPlanComptable(
      {required int annee, int? mois});

  /// Le même rapport en PDF (octets).
  Future<Uint8List> exporterRapportPlanComptablePdf(
      {required int annee, int? mois});
  /// Export PDF d'un état SYCEBNL (`bilan`, `compte_resultat`, `flux` ou
  /// `notes`), généré depuis la vraie comptabilité (tranche P6).
  Future<Uint8List> exporterSycebnlPdf(
      {required String etat, int? annee});

  /// Données JSON des quatre états SYCEBNL pour l'écran (mêmes sommes
  /// que l'export PDF). Admin et trésorier, sans passer par
  /// GET /finances/rapport (réservé à l'admin et au responsable de culte).
  Future<EtatsSycebnl> getDonneesSycebnl({required int annee});

  // -- Administration : paramètres, rôles, audit (module 12) -----------------
  Future<EgliseParametres> getParametres();

  Future<EgliseParametres> saveParametres({
    String? adresse,
    String? ville,
    String? telephone,
    String? email,
    String? logoUrl,
    String? waveNumero,
    String? orangeNumero,
    String? mtnNumero,
    String? devise,
    String? fuseauHoraire,
    // T10 : signataires configurables, vides par défaut.
    String? signataireNominations,
    String? signataireProcesVerbaux,
    // T12 (US8, US11, US14). `effacerDimeSuggere` remet la dîme à vide
    // (désactivée) ; sans lui, un montant null ne touche pas au champ.
    int? montantDimeSuggere,
    bool effacerDimeSuggere = false,
    bool? transparenceVisibleMembres,
    int? seuilInactiviteSemaines,
    int? seuilBaisseContributionsPct,
  });

  Future<List<RoleEglise>> getRoles();

  Future<RoleEglise> setRole(String userId, String role);

  Future<List<AuditEntree>> getAudit({String? action, String? userId});

  // -- Présentation et identité de l'église (module 13) ----------------------
  Future<ProfilEglise> getPresentation(String code);

  /// Régénère le code de tutelle de mon église ; renvoie le nouveau code.
  /// L'ancien code cesse de fonctionner immédiatement (rattachements,
  /// transferts et lien de présentation publique avec l'ancien code de
  /// tutelle).
  Future<String> regenererCode({required String type});

  Future<Church> updateProfil({
    required String churchId,
    String? name,
    String? description,
    List<HoraireCulte>? horaires,
    String? couleurPrincipale,
    String? devise,
    String? fuseauHoraire,
    String? address,
    String? phone,
    String? email,
    String? city,
  });

  /// Téléverse le logo (base64) ; renvoie l'URL du logo (`logo_url`).
  Future<String> uploadLogo({
    required String churchId,
    required String base64,
    String? filename,
  });

  /// Bascule l'église active (le jeton est renouvelé côté serveur).
  Future<void> switchChurch(String churchId);

  /// Renouvelle la session par le jeton de rafraîchissement (rotation) :
  /// nouveau JWT + nouveau jeton, sans ressaisir le mot de passe.
  Future<AuthResult> refresh();

  /// Déconnexion : révoque le jeton de rafraîchissement de cet appareil
  /// côté serveur (le JWT restant expire seul).
  Future<void> logout();

  /// Mes églises, paginées + recherche (nom, code, ville) :
  /// `GET /moi/eglises`, 50 par page par défaut. L'église active est
  /// en tête de la première page.
  Future<MesEglisesPage> listerMesEglises(
      {String? recherche, int page = 1, int limite = 50});

  // -- Paiements par pays et clés API (module 14) ---------------------------
  /// Catalogue des fournisseurs pour un pays (`CI`, `SN`, `KE`, `INTL`).
  /// Sans pays : tout le catalogue.
  Future<List<FournisseurPaiement>> getFournisseursPaiement({String? pays});

  /// Configuration masquée des moyens de paiement de l'église
  /// (aucune valeur secrète n'est jamais renvoyée).
  Future<List<EglisePaiement>> getMesPaiements(String churchId);

  /// Saisit ou met à jour un moyen de paiement (admin, sa propre église).
  /// À la création, tous les champs requis doivent être fournis ; en mise
  /// à jour, seuls les secrets fournis sont remplacés. Renvoie la
  /// configuration masquée.
  Future<EglisePaiement> configurerPaiement({
    required String churchId,
    required String fournisseurCode,
    required String pays,
    String? libelle,
    bool? actif,
    required List<Map<String, String>> secrets,
  });

  /// Retire un moyen de paiement configuré (admin).
  Future<void> supprimerPaiement({
    required String churchId,
    required String fournisseurCode,
  });

  /// Teste la connexion d'un moyen configuré (admin). Renvoie succès /
  /// échec et un message seulement — jamais la clé.
  Future<({bool ok, String message})> testerPaiement({
    required String churchId,
    required String fournisseurCode,
  });

  /// Exécute un paiement côté serveur (admin, trésorier). Renvoie le JSON
  /// brut : `{ contribution, session_id?, launch_url? }`.
  Future<Map<String, dynamic>> executerPaiement({
    required String fournisseurCode,
    required String type,
    required int montant,
    String devise = 'XOF',
    String? memberId,
    required String successUrl,
    required String errorUrl,
    String? note,
  });

  // -- Rapports et annonces --------------------------------------------------
  Future<RapportConsolide> getRapport();

  /// Finances de la mère en détail : total consolidé + détail par branche,
  /// par période (mois, trimestre, année) et par type, avec chaque
  /// transaction confirmée. La vue agrégée reste pour le tableau de bord.
  Future<RapportDetailConsolide> getRapportDetail({
    required String periode,
    String? mois,
  });

  Future<List<Announcement>> getAnnonces();

  // -- Plateforme ------------------------------------------------------------
  /// Chiffres globaux seulement (`GET /plateforme/chiffres`, super_admin
  /// seulement). Aucun détail nominatif, aucune gestion des membres.
  Future<ChiffresPlateforme> getPlateforme();

  /// Accès Plateforme (`GET /plateforme/acces`, super_admin seulement).
  Future<List<AccesPlateforme>> listerAccesPlateforme();

  /// Ajouter une personne pour aider (`POST /plateforme/acces`,
  /// super_admin seulement) : invitation si nouveau compte, sinon son
  /// mot de passe existant.
  Future<AccesPlateformeCree> creerAccesPlateforme({
    required String email,
    String? nom,
    required List<String> droits,
  });

  /// Révoquer un accès d'aide (`DELETE /plateforme/acces/:userId`,
  /// super_admin seulement, jamais soi-même, jamais un super_admin).
  Future<void> revoquerAccesPlateforme(String userId);

  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  });

  Future<void> deleteAnnonce(String id);

  // -- Confiance (T11) -------------------------------------------------------
  /// État 2FA du compte (`GET /2fa/etat`).
  Future<bool> getEtat2fa();

  /// Démarre la 2FA : renvoie l'URI otpauth (QR) et le secret, une
  /// seule fois (`POST /2fa/demarrer`). Le secret est chiffré côté
  /// serveur, jamais stocké en clair.
  Future<Demarrage2fa> demarrer2fa();

  /// Confirme l'activation 2FA avec un code à 6 chiffres.
  Future<void> verifier2fa(String code);

  /// Désactive la 2FA avec un code à 6 chiffres valide.
  Future<void> desactiver2fa(String code);

  /// Vérifie la chaîne de hachage du journal d'audit.
  Future<VerificationAudit> verifierAudit();

  /// Lectures sensibles journalisées (`GET /consultations`, US17).
  Future<List<ConsultationSensible>> getConsultations();

  /// Crée une sauvegarde chiffrée de l'église (`POST /sauvegardes`).
  Future<Sauvegarde> creerSauvegarde();

  /// Liste les sauvegardes de l'église.
  Future<List<Sauvegarde>> getSauvegardes();

  /// Restaure une sauvegarde : les données de l'église reviennent à
  /// l'état sauvegardé (le journal d'audit n'est jamais réécrit).
  Future<void> restaurerSauvegarde(String id);

  /// Paramètres de confiance de l'église (`GET /confiance/parametres`).
  /// La clé du fournisseur n'est jamais renvoyée.
  Future<ParametresConfiance> getParametresConfiance();

  /// Modifie les paramètres de confiance : fréquence de sauvegarde,
  /// fournisseur de notification, clé, plafond mensuel.
  Future<ParametresConfiance> patchParametresConfiance({
    String? sauvegardeFrequence,
    String? sauvegardeHeure,
    bool? notificationsActives,
    String? notificationFournisseur,
    String? notificationCle,
    int? notificationPlafondMensuel,
  });

  /// Notifications de la boîte d'envoi (`GET /notifications`).
  Future<List<NotificationConfiance>> getNotifications(
      {String? statut, String? canal});

  /// Crée une notification en file (`POST /notifications`). Tant
  /// qu'aucun fournisseur n'est choisi, rien n'est envoyé.
  Future<NotificationConfiance> createNotification({
    required String canal,
    required String titre,
    required String message,
    String? userId,
  });

  /// Déclenche l'envoi d'une notification en attente.
  Future<NotificationConfiance> envoyerNotification(String id);

  /// Soumet une action hors ligne au serveur (`POST /file-hors-ligne`) :
  /// idempotente par `cleClient`, jamais appliquée deux fois.
  Future<ActionHorsLigne> soumettreActionHorsLigne({
    required String typeAction,
    required Map<String, dynamic> charge,
    required String cleClient,
  });

  /// File d'attente hors ligne du serveur (`GET /file-hors-ligne`).
  Future<List<ActionHorsLigne>> getActionsHorsLigne({String? statut});

  /// Rejoue toute la file hors ligne du serveur, dans l'ordre.
  Future<RejeuFile> rejouerFileHorsLigne();

  /// Rejoue une seule action hors ligne.
  Future<ActionHorsLigne> rejouerActionHorsLigne(String id);

  // -- US4 à US17 restantes (T12) --------------------------------------------
  Future<List<Promesse>> getPromesses({String? memberId});
  Future<Promesse> getPromesse(String id);
  Future<Promesse> createPromesse({
    required String memberId,
    required int montantTotalFcfa,
    String? dateDebut,
    int nbVersements = 1,
  });
  Future<Promesse> annulerPromesse(String id);
  Future<Map<String, dynamic>> verserPromesse({
    required String promesseId,
    required String echeanceId,
    required int amountFcfa,
    required String paymentMethod,
    String? paymentRef,
    String? note,
  });

  Future<List<DonNature>> getDonsNature({String? typeDon});
  Future<DonNature> createDonNature({
    String? memberId,
    required String description,
    int quantite = 1,
    String? unite,
    String typeDon = 'materiel',
    double? heures,
    String? dateDon,
    bool anonyme = false,
  });

  Future<List<Visiteur>> getVisiteurs({String? statut});
  Future<Visiteur> createVisiteur({
    required String nom,
    String? dateVenue,
    String? telephone,
    String? email,
    String? moyenContact,
  });
  Future<Visiteur> devenirMembre(String visiteurId, String memberId);

  Future<List<EvenementVie>> getEvenementsVie({int jours = 30});
  Future<void> masquerEvenementsVie(List<String> types);

  Future<Transparence> getTransparence({String? periode});

  Future<CartePortefeuille> getCartePortefeuille();

  Future<MesConsentements> getMesConsentements();
  Future<MesConsentements> saveMesConsentements({
    bool? whatsapp,
    bool? smsRepli,
  });
  Future<List<WhatsappConsentement>> getWhatsappConsentements();

  Future<List<AlerteMere>> getAlertesMere({String? statut});
  Future<Map<String, dynamic>> detecterAlertes();
  Future<AlerteMere> traiterAlerte(String id);

  Future<List<ListeConfigurable>> getListesConfigurables({String? type});
  Future<ListeConfigurable> createListeConfigurable({
    required String type,
    required String libelle,
    String? niveau,
  });
  Future<ListeConfigurable> updateListeConfigurable(
    String id, {
    bool? archive,
  });
  Future<void> deleteListeConfigurable(String id);
  Future<List<String>> getStatutsMembre();

  Future<List<ConsultationSensible>> getConsultationsSensibles();
  Future<List<ConsultationSensible>> getMesConsultations();
  Future<void> journaliserConsultation(String ressource, {String? ressourceId});
}
