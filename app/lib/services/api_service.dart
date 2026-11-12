import 'dart:typed_data';

import '../models/attestation.dart';
import '../models/annexe.dart';
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
import '../models/finances.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../models/nettoyage_test.dart';
import '../models/paiements.dart';
import '../models/parametres.dart';
import '../models/pastoral.dart';
import '../models/presences.dart';
import '../models/prieres.dart';
import '../models/profil.dart';
import '../models/plateforme.dart';
import '../models/transfert.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';
import '../models/serviteurs.dart';
import '../models/stats.dart';

/// Erreur renvoyée par l'API (ou par le service en mode démo).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Interface unique parlée par les écrans. Une seule implémentation :
/// [HttpApiService] (API réelle). Les écrans ne connaissent que cette
/// interface. Les listes vides restent vides : l'écran affiche un état vide.
abstract class ApiService {
  // -- Authentification -----------------------------------------------------
  Future<AuthResult> login({required String email, required String password});

  Future<AuthResult> register({
    required String churchName,
    required String city,
    String? churchPhone,
    String? churchEmail,
    required String adminName,
    required String adminEmail,
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

  Future<List<Culte>> getMesCultes();

  Future<List<Presence>> getMesPresences();

  Future<List<Contribution>> getMesContributions();

  /// Mes attestations annuelles de dons (US3, rôle membre, les miennes).
  Future<List<Attestation>> getMesAttestations();

  /// Ma carte de membre (fiche + église).
  Future<MaCarte> getMaCarte();

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

  Future<TransfertsResult> getTransferts();

  Future<TransfertMembre> requestTransfert({
    required String matricule,
    required String destinationCode,
    String? motif,
  });

  Future<void> decideTransfert(String id, {required bool accept});

  Future<void> annulerTransfert(String id);

  // -- Membres ---------------------------------------------------------------
  Future<MemberPage> getMembers({String? q, String? department, String? status});

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
      String? status});

  Future<void> deleteMember(String id);

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

  Future<RapportFinancier> getRapportFinancier({int? annee});

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
  /// Liste de mon église, filtre par année. Génère pour tous les donateurs
  /// identifiés avec au moins un don confirmé cette année (ne régénère
  /// pas une attestation émise existante).
  Future<List<Attestation>> getAttestations({int? annee});

  Future<List<Attestation>> genererAttestations({required int annee});

  /// Nouvelle attestation qui annule l'ancienne (motif obligatoire).
  Future<Attestation> corrigerAttestation(String id, {required String motif});

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

  Future<List<VisitePastorale>> getVisitesPastorales({String? statut});

  Future<VisitePastorale> createVisitePastorale({
    required String memberId,
    required String dateVisite,
    String? motif,
    String? compteRendu,
  });

  Future<List<Accompagnement>> getAccompagnements(
      {String? type, String? statut});

  Future<Accompagnement> createAccompagnement({
    required String memberId,
    required String type,
    String? description,
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

  // -- Statistiques et export (module 11) ------------------------------------
  Future<StatsGlobales> getStatsGlobales();

  /// Export CSV (`membres` ou `contributions`) : renvoie le contenu brut.
  Future<String> exportCsv(String type);

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
  });

  Future<List<RoleEglise>> getRoles();

  Future<RoleEglise> setRole(String userId, String role);

  Future<List<AuditEntree>> getAudit();

  // -- Présentation et identité de l'église (module 13) ----------------------
  Future<ProfilEglise> getPresentation(String code);

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

  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  });

  Future<void> deleteAnnonce(String id);
}
