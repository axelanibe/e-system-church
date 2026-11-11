import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/biens.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/enfants.dart';
import '../models/finances.dart';
import '../models/medias.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
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
  });

  Future<MeResult> me();

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

  Future<Rattachement> requestRattachement({required String parentCode});

  Future<void> decideRattachement(String id, {required bool accept});

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
    String? department,
    String? cellGroup,
    String? status,
  });

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

  Future<List<Cellule>> getCellules();

  Future<Cellule> createCellule({
    required String nom,
    String? quartier,
    String? responsableMemberId,
    String? jourReunion,
    String? heureReunion,
  });

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

  Future<List<Budget>> getBudgets({int? annee});

  Future<Budget> createBudget({
    required String posteId,
    required int annee,
    required int montantPrevu,
  });

  Future<List<Depense>> getDepenses({String? statut});

  Future<Depense> createDepense({
    String? posteId,
    required int montantFcfa,
    required String motif,
    String? justificatifRef,
    String? dateDepense,
  });

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
    String? note,
  });

  Future<Contribution> setContributionStatus(String id, String status);

  // -- Communication : prières et messages (module 5) ------------------------
  Future<List<DemandePriere>> getDemandesPriere({String? statut});

  Future<DemandePriere> createDemandePriere({
    required String sujet,
    String? memberId,
    String? demandeurNom,
    String? details,
    bool confidentiel = false,
  });

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
}
