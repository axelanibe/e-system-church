// DONNÉES FICTIVES — DÉMO UNIQUEMENT.
//
// Ces données n'ont rien de réel : le réseau « Grâce Divine », ses églises,
// ses membres, ses montants et ses noms sont inventés pour présenter
// l'application. Ce fichier n'est utilisé QUE par la version démo
// (`lib/main_demo.dart` + `lib/demo/mock_api_service.dart`).
// L'application réelle (`lib/main.dart`) n'y touche jamais : elle n'affiche
// que les données de l'API, et ses listes vides restent vides.

import '../models/announcement.dart';
import '../models/biens.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/ecole_biblique.dart';
import '../models/enfants.dart';
import '../models/fidele.dart';
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
import '../models/rattachement.dart';
import '../models/serviteurs.dart';
import '../models/transfert.dart';

/// Identifiants stables des églises fictives.
class DemoIds {
  static const plateau = 'demo-eglise-plateau';
  static const yopougon = 'demo-eglise-yopougon';
  static const bouake = 'demo-eglise-bouake';
  static const yamoussoukro = 'demo-eglise-yamoussoukro';
  static const sanPedro = 'demo-eglise-san-pedro';
  static const marcory = 'demo-eglise-marcory';
}

/// Comptes de démonstration (mot de passe : `demo1234` pour les trois).
class DemoAccounts {
  static const adminEmail = 'admin@gracedivine.ci';
  static const membreEmail = 'membre@gracedivine.ci';
  static const plateformeEmail = 'plateforme@gracedivine.ci';
  static const password = 'demo1234';

  /// Matricule du membre lié au compte fidèle de démo.
  static const membreMatricule = 'GD-001';
}

/// Jeu de données fictif complet. Chaque instance est indépendante
/// (listes modifiables : les créations de la démo s'y ajoutent en mémoire).
class DemoSeed {
  final List<Church> churches = _buildChurches();
  final Map<String, List<Member>> membersByChurch = _buildMembers();
  final Map<String, List<Contribution>> contributionsByChurch =
      _buildContributions();
  final List<CulteType> culteTypes = _buildCulteTypes();
  final List<Culte> cultes = _buildCultes();
  final List<OrdreCulteItem> ordreCulte = _buildOrdreCulte();
  final List<EvenementSpecial> evenements = _buildEvenements();
  final List<Presence> presences = _buildPresences();
  final List<Announcement> annonces = _buildAnnonces();
  final List<Famille> familles = _buildFamilles();
  final List<Departement> departements = _buildDepartements();
  final List<Fonction> fonctions = _buildFonctions();
  // Postes de l'organigramme (distincts des postes budgétaires `postes`).
  final List<Poste> postesOrganisation = _buildPostesOrganisation();
  final List<Cellule> cellules = _buildCellules();
  final List<Bapteme> baptemes = _buildBaptemes();
  final List<LienParentEnfant> liens = _buildLiens();
  final List<MembreStatut> statuts = _buildStatuts();
  final List<PosteBudgetaire> postes = _buildPostes();
  final List<Budget> budgets = _buildBudgets();
  final List<Depense> depenses = _buildDepenses();
  final List<CaisseMouvement> caisseMouvements = _buildCaisseMouvements();
  final List<DemandePriere> prieres = _buildPrieres();
  final List<MessageInterne> messages = _buildMessages();
  final List<ParcoursNouveau> parcours = _buildParcours();
  final List<VisitePastorale> visites = _buildVisites();
  final List<Accompagnement> accompagnements = _buildAccompagnements();
  final List<Serviteur> serviteurs = _buildServiteurs();
  final List<PlanningServiteur> planning = _buildPlanning();
  final List<ClasseEnfant> classesEnfants = _buildClassesEnfants();
  final List<AutorisationSortie> autorisations = _buildAutorisations();
  final List<ActiviteJeunesse> activitesJeunesse = _buildActivitesJeunesse();
  final List<Predication> predications = _buildPredications();
  final List<PlanLecture> plansLecture = _buildPlansLecture();
  final List<Livre> livres = _buildLivres();
  final List<CoursEcole> coursEcole = _buildCoursEcole();
  final List<LeconEcole> leconsEcole = _buildLeconsEcole();
  final List<InscriptionEcole> inscriptionsEcole = _buildInscriptionsEcole();

  /// Leçons terminées par inscription (inscriptionId -> ids de leçons).
  /// Le membre de démo (Awa Koné) a terminé la première leçon du cours 1.
  final Map<String, List<String>> progressionsEcole = {
    'demo-insc-1': ['demo-lecon-1'],
  };
  final List<PretLivre> pretsLivres = _buildPretsLivres();
  final List<Salle> salles = _buildSalles();
  final List<ReservationSalle> reservationsSalles = _buildReservationsSalles();
  final List<Materiel> materiel = _buildMateriel();
  final List<MaintenanceMateriel> maintenances = _buildMaintenances();
  final List<RoleEglise> roles = _buildRoles();
  final List<AuditEntree> audit = _buildAudit();
  final List<Rattachement> rattachementsRecus = _buildRattachementsRecus();
  final List<Rattachement> rattachementsEmis = [];
  final List<TransfertMembre> transferts = _buildTransferts();
  final List<DemandeLiaison> demandesLiaison = _buildDemandesLiaison();
  final List<EglisePaiement> paiements = _buildPaiements();

  /// Paramètres par église (le seed ne concerne que Plateau ; chaque
  /// nouvelle église reçoit des paramètres vides à son nom).
  final Map<String, EgliseParametres> parametresByChurch = {
    DemoIds.plateau: _buildParametres(),
  };

  Church get plateau => churches.firstWhere((e) => e.id == DemoIds.plateau);

  List<Member> membersOf(String churchId) =>
      membersByChurch.putIfAbsent(churchId, () => []);

  List<Contribution> contributionsOf(String churchId) =>
      contributionsByChurch.putIfAbsent(churchId, () => []);

  Church? churchByCode(String code) {
    for (final e in churches) {
      if (e.code == code) return e;
    }
    return null;
  }

  Church? churchById(String id) {
    for (final e in churches) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Préfixe des matricules d'une église (« GD », « GY », …).
  static String matriculePrefix(String churchId) {
    switch (churchId) {
      case DemoIds.yopougon:
        return 'GY';
      case DemoIds.bouake:
        return 'GB';
      case DemoIds.yamoussoukro:
        return 'GK';
      case DemoIds.sanPedro:
        return 'GS';
      default:
        return 'GD';
    }
  }
}

// -- Églises ----------------------------------------------------------------

List<Church> _buildChurches() => [
      const Church(
        id: DemoIds.plateau,
        code: 'GD-PLAT',
        name: 'Grâce Divine — Plateau',
        city: 'Abidjan',
        status: 'active',
        role: 'admin_eglise',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
        couleurPrincipale: '#0B1F3A',
        description:
            'Église mère du réseau Grâce Divine, au Plateau à Abidjan.',
        horairesCultes: [
          HoraireCulte(jour: 'Dimanche', heure: '09:00', titre: 'Culte du dimanche'),
          HoraireCulte(jour: 'Mercredi', heure: '18:30', titre: 'Culte d’enseignement'),
          HoraireCulte(jour: 'Vendredi', heure: '21:00', titre: 'Veillée de prière'),
        ],
      ),
      const Church(
        id: DemoIds.yopougon,
        code: 'GD-YOP',
        name: 'Grâce Divine — Yopougon',
        parentChurchId: DemoIds.plateau,
        city: 'Abidjan',
        status: 'active',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
      ),
      const Church(
        id: DemoIds.bouake,
        code: 'GD-BKE',
        name: 'Grâce Divine — Bouaké',
        parentChurchId: DemoIds.plateau,
        city: 'Bouaké',
        status: 'active',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
      ),
      const Church(
        id: DemoIds.yamoussoukro,
        code: 'GD-YAK',
        name: 'Grâce Divine — Yamoussoukro',
        parentChurchId: DemoIds.plateau,
        city: 'Yamoussoukro',
        status: 'active',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
      ),
      const Church(
        id: DemoIds.sanPedro,
        code: 'GD-SPD',
        name: 'Grâce Divine — San Pedro',
        parentChurchId: DemoIds.plateau,
        city: 'San Pedro',
        status: 'active',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
      ),
      // Église indépendante qui demande son rattachement au réseau.
      const Church(
        id: DemoIds.marcory,
        code: 'NA-MAR',
        name: 'Nouvelle Alliance — Marcory',
        city: 'Abidjan',
        status: 'active',
        devise: 'FCFA',
        fuseauHoraire: 'Africa/Abidjan',
      ),
    ];

// -- Membres ----------------------------------------------------------------

Member _m(
  String id,
  String matricule,
  String nom, {
  String? email,
  String? phone,
  String? birthDate,
  String? department,
  String? cellGroup,
  String status = 'actif',
}) =>
    Member(
      id: id,
      matricule: matricule,
      fullName: nom,
      email: email,
      phone: phone,
      birthDate: birthDate,
      department: department,
      cellGroup: cellGroup,
      status: status,
      createdAt: DateTime.parse('2026-01-15T10:00:00'),
    );

Map<String, List<Member>> _buildMembers() => {
      DemoIds.plateau: [
        _m('demo-m-001', 'GD-001', 'Awa Koné',
            email: 'awa.kone@demo.ci',
            phone: '+225 07 47 12 34 01',
            birthDate: '1990-04-12',
            department: 'Louange',
            cellGroup: 'Cocody'),
        _m('demo-m-002', 'GD-002', 'Koffi Yao',
            email: 'koffi.yao@demo.ci',
            phone: '+225 07 47 12 34 02',
            birthDate: '1985-09-30',
            department: 'Intercession',
            cellGroup: 'Cocody'),
        _m('demo-m-003', 'GD-003', 'Mariam Traoré',
            email: 'mariam.traore@demo.ci',
            phone: '+225 07 47 12 34 03',
            birthDate: '1988-02-18',
            department: 'Protocole',
            cellGroup: 'Plateau'),
        _m('demo-m-004', 'GD-004', 'Jean-Marc N’Guessan',
            email: 'jm.nguessan@demo.ci',
            phone: '+225 07 47 12 34 04',
            birthDate: '1992-11-05',
            department: 'Médias',
            cellGroup: 'Plateau'),
        _m('demo-m-005', 'GD-005', 'Fatou Diabaté',
            email: 'fatou.diabate@demo.ci',
            phone: '+225 07 47 12 34 05',
            birthDate: '1995-07-22',
            department: 'Enfants',
            cellGroup: 'Cocody'),
        _m('demo-m-006', 'GD-006', 'Serge Kouassi',
            email: 'serge.kouassi@demo.ci',
            phone: '+225 07 47 12 34 06',
            birthDate: '1998-01-27',
            department: 'Louange',
            cellGroup: 'Plateau',
            status: 'nouveau_converti'),
        _m('demo-m-007', 'GD-007', 'Aïcha Bamba',
            email: 'aicha.bamba@demo.ci',
            phone: '+225 07 47 12 34 07',
            birthDate: '1993-05-14',
            department: 'Intercession',
            cellGroup: 'Yopougon'),
        _m('demo-m-008', 'GD-008', 'Emmanuel Aka',
            email: 'emmanuel.aka@demo.ci',
            phone: '+225 07 47 12 34 08',
            birthDate: '1980-12-03',
            department: 'Protocole',
            cellGroup: 'Plateau'),
        _m('demo-m-009', 'GD-009', 'Nadia Touré',
            email: 'nadia.toure@demo.ci',
            phone: '+225 07 47 12 34 09',
            birthDate: '1996-08-19',
            department: 'Médias',
            cellGroup: 'Yopougon'),
        _m('demo-m-010', 'GD-010', 'Paul Yao',
            email: 'paul.yao@demo.ci',
            phone: '+225 07 47 12 34 10',
            birthDate: '1987-03-08',
            department: 'Enfants',
            cellGroup: 'Plateau',
            status: 'inactif'),
        _m('demo-m-011', 'GD-011', 'Grâce Adjoua',
            email: 'grace.adjoua@demo.ci',
            phone: '+225 07 47 12 34 11',
            birthDate: '2001-06-25',
            department: 'Louange',
            cellGroup: 'Cocody',
            status: 'nouveau_converti'),
        _m('demo-m-012', 'GD-012', 'David Konan',
            email: 'david.konan@demo.ci',
            phone: '+225 07 47 12 34 12',
            birthDate: '1991-10-11',
            department: 'Intercession',
            cellGroup: 'Plateau'),
      ],
      DemoIds.yopougon: [
        _m('demo-m-101', 'GY-001', 'Yao N’Dri',
            email: 'yao.ndri@demo.ci',
            department: 'Louange',
            cellGroup: 'Yopougon'),
        _m('demo-m-102', 'GY-002', 'Aminata Cissé',
            email: 'aminata.cisse@demo.ci',
            department: 'Intercession',
            cellGroup: 'Yopougon'),
        _m('demo-m-103', 'GY-003', 'Luc Gohou',
            email: 'luc.gohou@demo.ci',
            department: 'Protocole',
            cellGroup: 'Yopougon'),
      ],
      DemoIds.bouake: [
        _m('demo-m-201', 'GB-001', 'Konan Yao',
            email: 'konan.yao@demo.ci', department: 'Louange'),
        _m('demo-m-202', 'GB-002', 'Marie Koné',
            email: 'marie.kone@demo.ci', department: 'Enfants'),
        _m('demo-m-203', 'GB-003', 'Isaac Touré',
            email: 'isaac.toure@demo.ci', department: 'Intercession'),
      ],
      DemoIds.yamoussoukro: [
        _m('demo-m-301', 'GK-001', 'Awa N’Guessan',
            email: 'awa.nguessan@demo.ci', department: 'Louange'),
        _m('demo-m-302', 'GK-002', 'Pierre Aka',
            email: 'pierre.aka@demo.ci', department: 'Protocole'),
      ],
      DemoIds.sanPedro: [
        _m('demo-m-401', 'GS-001', 'Fatou Koné',
            email: 'fatou.kone@demo.ci', department: 'Intercession'),
        _m('demo-m-402', 'GS-002', 'Jean Yao',
            email: 'jean.yao@demo.ci', department: 'Médias'),
      ],
    };

// -- Contributions ----------------------------------------------------------

Contribution _c(
  String id,
  String type,
  int montant,
  String moyen, {
  String? memberId,
  String? membreNom,
  String? membreMatricule,
  String status = 'confirme',
  String? note,
  required String date,
  String? paymentRef,
}) =>
    Contribution(
      id: id,
      type: type,
      amountFcfa: montant,
      paymentMethod: moyen,
      paymentRef: paymentRef,
      status: status,
      note: note,
      memberId: memberId,
      membreNom: membreNom,
      membreMatricule: membreMatricule,
      createdAt: DateTime.parse(date),
      egliseNom: 'Grâce Divine — Plateau',
      egliseCode: 'GD-PLAT',
    );

Map<String, List<Contribution>> _buildContributions() => {
      DemoIds.plateau: [
        _c('demo-c-001', 'dime', 50000, 'wave',
            memberId: 'demo-m-001',
            membreNom: 'Awa Koné',
            membreMatricule: 'GD-001',
            date: '2026-11-01T10:15:00',
            paymentRef: 'WAVE-DEMO-001'),
        _c('demo-c-002', 'offrande', 25000, 'orange_money',
            memberId: 'demo-m-002',
            membreNom: 'Koffi Yao',
            membreMatricule: 'GD-002',
            date: '2026-11-01T10:20:00',
            paymentRef: 'OM-DEMO-002'),
        _c('demo-c-003', 'dime', 75000, 'mtn_momo',
            memberId: 'demo-m-003',
            membreNom: 'Mariam Traoré',
            membreMatricule: 'GD-003',
            date: '2026-11-01T10:25:00',
            paymentRef: 'MTN-DEMO-003'),
        _c('demo-c-004', 'don', 100000, 'wave',
            note: 'Don anonyme pour la toiture',
            date: '2026-11-02T09:00:00',
            paymentRef: 'WAVE-DEMO-004'),
        _c('demo-c-005', 'offrande', 15000, 'especes',
            memberId: 'demo-m-004',
            membreNom: 'Jean-Marc N’Guessan',
            membreMatricule: 'GD-004',
            date: '2026-11-03T18:45:00'),
        _c('demo-c-006', 'dime', 40000, 'wave',
            memberId: 'demo-m-006',
            membreNom: 'Serge Kouassi',
            membreMatricule: 'GD-006',
            date: '2026-11-04T09:30:00',
            paymentRef: 'WAVE-DEMO-006'),
        _c('demo-c-007', 'offrande', 20000, 'orange_money',
            memberId: 'demo-m-007',
            membreNom: 'Aïcha Bamba',
            membreMatricule: 'GD-007',
            date: '2026-11-05T19:00:00',
            paymentRef: 'OM-DEMO-007'),
        _c('demo-c-008', 'don', 60000, 'virement',
            memberId: 'demo-m-008',
            membreNom: 'Emmanuel Aka',
            membreMatricule: 'GD-008',
            note: 'Don pour les missions',
            date: '2026-11-06T11:00:00'),
        _c('demo-c-009', 'dime', 55000, 'wave',
            memberId: 'demo-m-001',
            membreNom: 'Awa Koné',
            membreMatricule: 'GD-001',
            date: '2026-11-08T10:10:00',
            paymentRef: 'WAVE-DEMO-009'),
        _c('demo-c-010', 'offrande', 30000, 'mtn_momo',
            memberId: 'demo-m-009',
            membreNom: 'Nadia Touré',
            membreMatricule: 'GD-009',
            date: '2026-11-08T10:20:00',
            paymentRef: 'MTN-DEMO-010'),
        _c('demo-c-011', 'dime', 45000, 'wave',
            memberId: 'demo-m-012',
            membreNom: 'David Konan',
            membreMatricule: 'GD-012',
            date: '2026-11-08T10:25:00',
            paymentRef: 'WAVE-DEMO-011'),
        _c('demo-c-012', 'offrande', 12000, 'especes',
            memberId: 'demo-m-005',
            membreNom: 'Fatou Diabaté',
            membreMatricule: 'GD-005',
            status: 'en_attente',
            date: '2026-11-09T09:00:00'),
        _c('demo-c-013', 'don', 200000, 'wave',
            note: 'Don anonyme — campagne',
            status: 'en_attente',
            date: '2026-11-09T15:30:00',
            paymentRef: 'WAVE-DEMO-013'),
        _c('demo-c-014', 'dime', 35000, 'orange_money',
            memberId: 'demo-m-010',
            membreNom: 'Paul Yao',
            membreMatricule: 'GD-010',
            status: 'en_attente',
            date: '2026-11-10T08:00:00',
            paymentRef: 'OM-DEMO-014'),
      ],
      DemoIds.yopougon: [
        _c('demo-c-101', 'dime', 60000, 'wave',
            memberId: 'demo-m-101',
            membreNom: 'Yao N’Dri',
            membreMatricule: 'GY-001',
            date: '2026-11-08T10:00:00'),
        _c('demo-c-102', 'offrande', 25000, 'orange_money',
            memberId: 'demo-m-102',
            membreNom: 'Aminata Cissé',
            membreMatricule: 'GY-002',
            date: '2026-11-08T10:10:00'),
      ],
      DemoIds.bouake: [
        _c('demo-c-201', 'dime', 40000, 'mtn_momo',
            memberId: 'demo-m-201',
            membreNom: 'Konan Yao',
            membreMatricule: 'GB-001',
            date: '2026-11-08T10:00:00'),
        _c('demo-c-202', 'offrande', 18000, 'wave',
            memberId: 'demo-m-202',
            membreNom: 'Marie Koné',
            membreMatricule: 'GB-002',
            date: '2026-11-08T10:05:00'),
      ],
      DemoIds.yamoussoukro: [
        _c('demo-c-301', 'dime', 35000, 'wave',
            memberId: 'demo-m-301',
            membreNom: 'Awa N’Guessan',
            membreMatricule: 'GK-001',
            date: '2026-11-08T10:00:00'),
        _c('demo-c-302', 'offrande', 12000, 'especes',
            memberId: 'demo-m-302',
            membreNom: 'Pierre Aka',
            membreMatricule: 'GK-002',
            date: '2026-11-08T10:10:00'),
      ],
      DemoIds.sanPedro: [
        _c('demo-c-401', 'dime', 30000, 'orange_money',
            memberId: 'demo-m-401',
            membreNom: 'Fatou Koné',
            membreMatricule: 'GS-001',
            date: '2026-11-08T10:00:00'),
        _c('demo-c-402', 'offrande', 10000, 'wave',
            memberId: 'demo-m-402',
            membreNom: 'Jean Yao',
            membreMatricule: 'GS-002',
            date: '2026-11-08T10:05:00'),
      ],
    };

// -- Cultes -----------------------------------------------------------------

List<CulteType> _buildCulteTypes() => [
      const CulteType(
          id: 'demo-ct-1',
          nom: 'Culte du dimanche',
          jourSemaine: 0,
          heureDebut: '09:00',
          dureeMinutes: 120,
          lieu: 'Temple du Plateau'),
      const CulteType(
          id: 'demo-ct-2',
          nom: 'Culte d’enseignement',
          jourSemaine: 3,
          heureDebut: '18:30',
          dureeMinutes: 90,
          lieu: 'Temple du Plateau'),
      const CulteType(
          id: 'demo-ct-3',
          nom: 'Veillée de prière',
          jourSemaine: 5,
          heureDebut: '21:00',
          dureeMinutes: 180,
          lieu: 'Temple du Plateau'),
      const CulteType(
          id: 'demo-ct-4',
          nom: 'Culte des enfants',
          jourSemaine: 0,
          heureDebut: '09:00',
          dureeMinutes: 90,
          lieu: 'Salle des enfants'),
    ];

List<Culte> _buildCultes() => [
      const Culte(
        id: 'demo-culte-1',
        culteTypeId: 'demo-ct-1',
        titre: 'Culte du dimanche',
        dateHeure: '2026-11-08T09:00',
        lieu: 'Temple du Plateau',
        orateur: 'Pasteur Emmanuel Aka',
        theme: 'La foi qui déplace les montagnes',
      ),
      const Culte(
        id: 'demo-culte-2',
        culteTypeId: 'demo-ct-2',
        titre: 'Culte d’enseignement',
        dateHeure: '2026-11-11T18:30',
        lieu: 'Temple du Plateau',
        orateur: 'Pasteur Emmanuel Aka',
        theme: 'Grandir dans la prière',
      ),
      const Culte(
        id: 'demo-culte-3',
        culteTypeId: 'demo-ct-3',
        titre: 'Veillée de prière',
        dateHeure: '2026-11-13T21:00',
        lieu: 'Temple du Plateau',
        orateur: 'Diacre Serge Kouassi',
        theme: 'Une nuit de prière pour la Côte d’Ivoire',
      ),
      const Culte(
        id: 'demo-culte-4',
        culteTypeId: 'demo-ct-1',
        titre: 'Culte du dimanche — action de grâce',
        dateHeure: '2026-11-15T09:00',
        lieu: 'Temple du Plateau',
        orateur: 'Pasteur Emmanuel Aka',
        theme: 'L’église sans frontière',
      ),
      const Culte(
        id: 'demo-culte-5',
        culteTypeId: 'demo-ct-2',
        titre: 'Culte d’enseignement',
        dateHeure: '2026-11-18T18:30',
        lieu: 'Temple du Plateau',
        orateur: 'Pasteur Emmanuel Aka',
        theme: 'Le pardon',
      ),
      const Culte(
        id: 'demo-culte-6',
        culteTypeId: 'demo-ct-1',
        titre: 'Culte du dimanche',
        dateHeure: '2026-11-22T09:00',
        lieu: 'Temple du Plateau',
        orateur: 'Pasteur Emmanuel Aka',
        theme: 'Servir avec joie',
      ),
    ];

List<OrdreCulteItem> _buildOrdreCulte() => [
      const OrdreCulteItem(
          id: 'demo-oc-1', culteId: 'demo-culte-1', ordre: 1, titre: 'Louange', intervenant: 'Chorale', dureeMinutes: 30),
      const OrdreCulteItem(
          id: 'demo-oc-2', culteId: 'demo-culte-1', ordre: 2, titre: 'Prière d’ouverture', intervenant: 'Diacre Serge Kouassi', dureeMinutes: 10),
      const OrdreCulteItem(
          id: 'demo-oc-3', culteId: 'demo-culte-1', ordre: 3, titre: 'Prédication', intervenant: 'Pasteur Emmanuel Aka', dureeMinutes: 45),
      const OrdreCulteItem(
          id: 'demo-oc-4', culteId: 'demo-culte-1', ordre: 4, titre: 'Offrandes', dureeMinutes: 10),
      const OrdreCulteItem(
          id: 'demo-oc-5', culteId: 'demo-culte-1', ordre: 5, titre: 'Annonces', dureeMinutes: 10),
      const OrdreCulteItem(
          id: 'demo-oc-6', culteId: 'demo-culte-1', ordre: 6, titre: 'Bénédiction', intervenant: 'Pasteur Emmanuel Aka', dureeMinutes: 5),
    ];

List<EvenementSpecial> _buildEvenements() => [
      const EvenementSpecial(
        id: 'demo-ev-1',
        type: 'campagne',
        titre: 'Campagne d’évangélisation — Yopougon',
        description: 'Trois jours de porte-à-porte et de culte en plein air.',
        dateDebut: '2026-11-20',
        dateFin: '2026-11-22',
        lieu: 'Yopougon Selmer',
        responsable: 'Koffi Yao',
      ),
      const EvenementSpecial(
        id: 'demo-ev-2',
        type: 'bapteme_eau',
        titre: 'Baptême d’eau',
        description: 'Baptême des nouveaux convertis du trimestre.',
        dateDebut: '2026-11-29',
        lieu: 'Temple du Plateau',
        responsable: 'Pasteur Emmanuel Aka',
      ),
      const EvenementSpecial(
        id: 'demo-ev-3',
        type: 'mariage',
        titre: 'Mariage Kouassi & Awa',
        dateDebut: '2026-12-05',
        lieu: 'Temple du Plateau',
        responsable: 'Pasteur Emmanuel Aka',
      ),
    ];

// -- Présences ---------------------------------------------------------------

List<Presence> _buildPresences() {
  final statuts = {
    'demo-m-001': 'present',
    'demo-m-002': 'present',
    'demo-m-003': 'present',
    'demo-m-004': 'present',
    'demo-m-005': 'present',
    'demo-m-006': 'present',
    'demo-m-007': 'excuse',
    'demo-m-008': 'present',
    'demo-m-009': 'present',
    'demo-m-010': 'absent',
    'demo-m-011': 'present',
    'demo-m-012': 'present',
  };
  final noms = {
    'demo-m-001': 'Awa Koné',
    'demo-m-002': 'Koffi Yao',
    'demo-m-003': 'Mariam Traoré',
    'demo-m-004': 'Jean-Marc N’Guessan',
    'demo-m-005': 'Fatou Diabaté',
    'demo-m-006': 'Serge Kouassi',
    'demo-m-007': 'Aïcha Bamba',
    'demo-m-008': 'Emmanuel Aka',
    'demo-m-009': 'Nadia Touré',
    'demo-m-010': 'Paul Yao',
    'demo-m-011': 'Grâce Adjoua',
    'demo-m-012': 'David Konan',
  };
  var i = 0;
  return statuts.entries.map((e) {
    i++;
    return Presence(
      id: 'demo-p-$i',
      culteId: 'demo-culte-1',
      memberId: e.key,
      statut: e.value,
      mode: i % 3 == 0 ? 'manuel' : 'scan_qr',
      pointeAt: DateTime.parse('2026-11-08T09:0${i % 10}:00'),
      membreNom: noms[e.key],
    );
  }).toList();
}

// -- Annonces ----------------------------------------------------------------

List<Announcement> _buildAnnonces() => [
      Announcement(
        id: 'demo-a-1',
        title: 'Culte d’action de grâce — dimanche 15 novembre',
        body:
            'Dimanche prochain, culte spécial d’action de grâce pour les un an du réseau. Apportez un plat à partager après le culte.',
        broadcast: false,
        createdAt: DateTime.parse('2026-11-09T08:00:00'),
        churchId: DemoIds.plateau,
        egliseNom: 'Grâce Divine — Plateau',
      ),
      Announcement(
        id: 'demo-a-2',
        title: 'Campagne d’évangélisation à Yopougon',
        body:
            'Du 20 au 22 novembre, toute l’église est mobilisée à Yopougon Selmer. Les serviteurs s’inscrivent auprès de Koffi Yao.',
        broadcast: true,
        createdAt: DateTime.parse('2026-11-08T12:00:00'),
        churchId: DemoIds.plateau,
        egliseNom: 'Grâce Divine — Plateau',
      ),
      Announcement(
        id: 'demo-a-3',
        title: 'Réunion des serviteurs — samedi 14 novembre',
        body:
            'Tous les serviteurs sont attendus samedi à 10 h en salle principale pour préparer la campagne.',
        broadcast: false,
        createdAt: DateTime.parse('2026-11-07T17:00:00'),
        churchId: DemoIds.plateau,
        egliseNom: 'Grâce Divine — Plateau',
      ),
      Announcement(
        id: 'demo-a-4',
        title: 'Collecte pour la toiture du temple',
        body:
            'Objectif : 500 000 FCFA pour refaire la toiture avant la saison des pluies. Chaque don compte, par Wave, Orange Money ou MTN.',
        broadcast: true,
        createdAt: DateTime.parse('2026-11-05T09:00:00'),
        churchId: DemoIds.plateau,
        egliseNom: 'Grâce Divine — Plateau',
      ),
    ];

// -- Membres (complément) ----------------------------------------------------

List<Famille> _buildFamilles() => [
      const Famille(
          id: 'demo-fam-1',
          nom: 'Famille Koné',
          chefFamilleId: 'demo-m-001',
          adresse: 'Cocody, Abidjan',
          telephone: '+225 07 47 12 34 01'),
      const Famille(
          id: 'demo-fam-2',
          nom: 'Famille Yao',
          chefFamilleId: 'demo-m-002',
          adresse: 'Cocody, Abidjan',
          telephone: '+225 07 47 12 34 02'),
      const Famille(
          id: 'demo-fam-3',
          nom: 'Famille Traoré',
          chefFamilleId: 'demo-m-003',
          adresse: 'Plateau, Abidjan',
          telephone: '+225 07 47 12 34 03'),
    ];

List<Poste> _buildPostesOrganisation() => postesParDefaut
    .map((nom) => Poste(id: 'demo-poste-$nom', nom: nom))
    .toList();

List<Fonction> _buildFonctions() => fonctionsParDefaut
    .map((nom) => Fonction(id: 'demo-fonction-$nom', nom: nom))
    .toList();

List<Departement> _buildDepartements() => [
      const Departement(
          id: 'demo-dep-1',
          nom: 'Louange',
          description: 'Chorale et musiciens.',
          responsableMemberId: 'demo-m-001'),
      const Departement(
          id: 'demo-dep-2',
          nom: 'Intercession',
          description: 'Prière et jeûne.',
          responsableMemberId: 'demo-m-002'),
      const Departement(
          id: 'demo-dep-3',
          nom: 'Protocole',
          description: 'Accueil et organisation des cultes.',
          responsableMemberId: 'demo-m-003'),
      const Departement(
          id: 'demo-dep-4',
          nom: 'Médias',
          description: 'Son, vidéo et réseaux sociaux.',
          responsableMemberId: 'demo-m-004'),
      const Departement(
          id: 'demo-dep-5',
          nom: 'Enfants',
          description: 'École du dimanche.',
          responsableMemberId: 'demo-m-005'),
    ];

List<Cellule> _buildCellules() => [
      const Cellule(
          id: 'demo-cel-1',
          nom: 'Cellule Cocody',
          quartier: 'Cocody',
          responsableMemberId: 'demo-m-001',
          jourReunion: 'Mercredi',
          heureReunion: '18:00'),
      const Cellule(
          id: 'demo-cel-2',
          nom: 'Cellule Yopougon Selmer',
          quartier: 'Yopougon Selmer',
          responsableMemberId: 'demo-m-009',
          jourReunion: 'Jeudi',
          heureReunion: '18:30'),
      const Cellule(
          id: 'demo-cel-3',
          nom: 'Cellule Plateau',
          quartier: 'Plateau',
          responsableMemberId: 'demo-m-012',
          jourReunion: 'Vendredi',
          heureReunion: '19:00'),
    ];

List<Bapteme> _buildBaptemes() => [
      const Bapteme(
          id: 'demo-bap-1',
          memberId: 'demo-m-006',
          dateBapteme: '2026-06-14',
          lieu: 'Temple du Plateau',
          pasteur: 'Pasteur Emmanuel Aka',
          certificatNumero: 'BAP-2026-014'),
      const Bapteme(
          id: 'demo-bap-2',
          memberId: 'demo-m-011',
          dateBapteme: '2026-09-06',
          lieu: 'Temple du Plateau',
          pasteur: 'Pasteur Emmanuel Aka',
          certificatNumero: 'BAP-2026-027'),
    ];

List<LienParentEnfant> _buildLiens() => [
      const LienParentEnfant(
          id: 'demo-lien-1',
          parentMemberId: 'demo-m-002',
          enfantMemberId: 'demo-m-010',
          lien: 'pere',
          statut: 'valide'),
      const LienParentEnfant(
          id: 'demo-lien-2',
          parentMemberId: 'demo-m-001',
          enfantMemberId: 'demo-m-011',
          lien: 'mere',
          statut: 'valide'),
    ];

List<MembreStatut> _buildStatuts() => [
      MembreStatut(
          id: 'demo-st-1',
          memberId: 'demo-m-006',
          statut: 'nouveau_converti',
          motif: 'Nouveau converti — parcours en cours',
          createdAt: DateTime.parse('2026-05-10T10:00:00')),
      MembreStatut(
          id: 'demo-st-2',
          memberId: 'demo-m-011',
          statut: 'nouveau_converti',
          motif: 'Nouvelle convertie — parcours en cours',
          createdAt: DateTime.parse('2026-08-20T10:00:00')),
      MembreStatut(
          id: 'demo-st-3',
          memberId: 'demo-m-010',
          statut: 'inactif',
          ancienStatut: 'membre',
          motif: 'Absent depuis deux mois',
          createdAt: DateTime.parse('2026-10-01T10:00:00')),
    ];

// -- Finances (module 4) -----------------------------------------------------

List<PosteBudgetaire> _buildPostes() => [
      const PosteBudgetaire(
          id: 'demo-poste-1', nom: 'Dîmes et offrandes', categorie: 'recette'),
      const PosteBudgetaire(
          id: 'demo-poste-2', nom: 'Dons', categorie: 'recette'),
      const PosteBudgetaire(
          id: 'demo-poste-3',
          nom: 'Loyer du temple',
          categorie: 'depense',
          description: 'Loyer mensuel du temple du Plateau.'),
      const PosteBudgetaire(
          id: 'demo-poste-4', nom: 'Électricité et eau', categorie: 'depense'),
      const PosteBudgetaire(
          id: 'demo-poste-5',
          nom: 'Missions et évangélisation',
          categorie: 'depense'),
      const PosteBudgetaire(
          id: 'demo-poste-6', nom: 'Entretien du temple', categorie: 'depense'),
    ];

List<Budget> _buildBudgets() => [
      const Budget(
          id: 'demo-bud-1',
          posteId: 'demo-poste-3',
          annee: 2026,
          montantPrevu: 1200000),
      const Budget(
          id: 'demo-bud-2',
          posteId: 'demo-poste-4',
          annee: 2026,
          montantPrevu: 360000),
      const Budget(
          id: 'demo-bud-3',
          posteId: 'demo-poste-5',
          annee: 2026,
          montantPrevu: 600000),
      const Budget(
          id: 'demo-bud-4',
          posteId: 'demo-poste-6',
          annee: 2026,
          montantPrevu: 240000),
    ];

List<Depense> _buildDepenses() => [
      Depense(
          id: 'demo-dep-1',
          posteId: 'demo-poste-3',
          montantFcfa: 100000,
          motif: 'Loyer du temple — novembre 2026',
          statut: 'payee',
          dateDepense: '2026-11-01',
          createdAt: DateTime.parse('2026-11-01T08:00:00')),
      Depense(
          id: 'demo-dep-2',
          posteId: 'demo-poste-4',
          montantFcfa: 28500,
          motif: 'Facture d’électricité — octobre 2026',
          justificatifRef: 'CIE-2026-10-4471',
          statut: 'validee_pasteur',
          dateDepense: '2026-11-05',
          createdAt: DateTime.parse('2026-11-05T09:00:00')),
      Depense(
          id: 'demo-dep-3',
          posteId: 'demo-poste-6',
          montantFcfa: 75000,
          motif: 'Réparation de la sono',
          statut: 'soumise',
          dateDepense: '2026-11-09',
          createdAt: DateTime.parse('2026-11-09T11:00:00')),
    ];

List<CaisseMouvement> _buildCaisseMouvements() => [
      CaisseMouvement(
          id: 'demo-caisse-1',
          type: 'entree',
          montantFcfa: 50000,
          motif: 'Offrande du dimanche 8 novembre',
          createdAt: DateTime.parse('2026-11-08T12:00:00')),
      CaisseMouvement(
          id: 'demo-caisse-2',
          type: 'sortie',
          montantFcfa: 28500,
          motif: 'Facture d’électricité — octobre',
          reference: 'CIE-2026-10-4471',
          createdAt: DateTime.parse('2026-11-05T09:30:00')),
      CaisseMouvement(
          id: 'demo-caisse-3',
          type: 'entree',
          montantFcfa: 25000,
          motif: 'Dons du mercredi 4 novembre',
          createdAt: DateTime.parse('2026-11-04T19:30:00')),
    ];

// -- Communication et suivi pastoral ----------------------------------------

List<DemandePriere> _buildPrieres() => [
      DemandePriere(
          id: 'demo-pr-1',
          memberId: 'demo-m-001',
          demandeurNom: 'Awa Koné',
          sujet: 'Guérison de ma mère',
          details: 'Ma mère est hospitalisée depuis lundi.',
          statut: 'en_cours',
          createdAt: DateTime.parse('2026-11-07T10:00:00')),
      DemandePriere(
          id: 'demo-pr-2',
          memberId: 'demo-m-002',
          demandeurNom: 'Koffi Yao',
          sujet: 'Emploi pour mon frère',
          statut: 'nouvelle',
          createdAt: DateTime.parse('2026-11-09T08:00:00')),
      DemandePriere(
          id: 'demo-pr-3',
          memberId: 'demo-m-009',
          demandeurNom: 'Nadia Touré',
          sujet: 'Réussite aux examens',
          statut: 'terminee',
          createdAt: DateTime.parse('2026-10-20T10:00:00')),
    ];

List<MessageInterne> _buildMessages() => [
      MessageInterne(
          id: 'demo-msg-1',
          expediteurId: 'demo-user-admin',
          sujet: 'Bienvenue aux nouveaux serviteurs',
          corps:
              'Bienvenue à Serge et Grâce dans l’équipe des serviteurs. La réunion de samedi à 10 h est obligatoire.',
          lu: false,
          createdAt: DateTime.parse('2026-11-09T09:00:00')),
      MessageInterne(
          id: 'demo-msg-2',
          expediteurId: 'demo-user-admin',
          sujet: 'Préparation de la campagne de Yopougon',
          corps:
              'Les équipes de porte-à-porte sont affichées au tableau de la salle principale.',
          lu: true,
          createdAt: DateTime.parse('2026-11-06T16:00:00')),
    ];

List<ParcoursNouveau> _buildParcours() => [
      ParcoursNouveau(
          id: 'demo-parc-1',
          memberId: 'demo-m-006',
          etape: 'formation',
          note: 'Suit le cours des nouveaux convertis.',
          createdAt: DateTime.parse('2026-05-12T10:00:00')),
      ParcoursNouveau(
          id: 'demo-parc-2',
          memberId: 'demo-m-011',
          etape: 'accueil',
          note: 'Premier contact le 20 août.',
          createdAt: DateTime.parse('2026-08-22T10:00:00')),
    ];

List<VisitePastorale> _buildVisites() => [
      const VisitePastorale(
          id: 'demo-vis-1',
          memberId: 'demo-m-001',
          dateVisite: '2026-11-12',
          motif: 'Visite de suivi — mère hospitalisée',
          statut: 'planifiee'),
      const VisitePastorale(
          id: 'demo-vis-2',
          memberId: 'demo-m-010',
          dateVisite: '2026-11-05',
          motif: 'Encourager Paul à revenir au culte',
          compteRendu: 'Paul est encouragé, il promet de revenir dimanche.',
          statut: 'realisee'),
    ];

List<Accompagnement> _buildAccompagnements() => [
      const Accompagnement(
          id: 'demo-acc-1',
          memberId: 'demo-m-002',
          type: 'couple',
          description: 'Accompagnement du couple Yao avant le mariage.',
          statut: 'en_cours'),
      const Accompagnement(
          id: 'demo-acc-2',
          memberId: 'demo-m-001',
          type: 'malade',
          description: 'Soutien pour la mère d’Awa, hospitalisée.',
          statut: 'en_cours'),
    ];

// -- Serviteurs, enfants, médias, biens --------------------------------------

List<Serviteur> _buildServiteurs() => [
      const Serviteur(
          id: 'demo-serv-1',
          memberId: 'demo-m-001',
          departementId: 'demo-dep-1',
          role: 'responsable',
          disponibilite: 'Dimanche et mercredi'),
      const Serviteur(
          id: 'demo-serv-2',
          memberId: 'demo-m-002',
          departementId: 'demo-dep-2',
          role: 'serviteur',
          disponibilite: 'Vendredi soir'),
      const Serviteur(
          id: 'demo-serv-3',
          memberId: 'demo-m-003',
          departementId: 'demo-dep-3',
          role: 'responsable',
          disponibilite: 'Dimanche'),
      const Serviteur(
          id: 'demo-serv-4',
          memberId: 'demo-m-004',
          departementId: 'demo-dep-4',
          role: 'serviteur',
          disponibilite: 'Dimanche et mercredi'),
      const Serviteur(
          id: 'demo-serv-5',
          memberId: 'demo-m-005',
          departementId: 'demo-dep-5',
          role: 'serviteur',
          disponibilite: 'Dimanche matin'),
    ];

List<PlanningServiteur> _buildPlanning() => [
      const PlanningServiteur(
          id: 'demo-plan-1',
          serviteurId: 'demo-serv-1',
          culteId: 'demo-culte-4',
          dateService: '2026-11-15',
          roleService: 'Louange',
          statut: 'confirme'),
      const PlanningServiteur(
          id: 'demo-plan-2',
          serviteurId: 'demo-serv-2',
          culteId: 'demo-culte-4',
          dateService: '2026-11-15',
          roleService: 'Intercession',
          statut: 'prevu'),
    ];

List<ClasseEnfant> _buildClassesEnfants() => [
      const ClasseEnfant(
          id: 'demo-classe-1',
          nom: 'Les Petits',
          ageMin: 3,
          ageMax: 5,
          salle: 'Salle des enfants'),
      const ClasseEnfant(
          id: 'demo-classe-2',
          nom: 'Les Étoiles',
          ageMin: 6,
          ageMax: 9,
          salle: 'Salle des enfants'),
      const ClasseEnfant(
          id: 'demo-classe-3',
          nom: 'Les Ados',
          ageMin: 10,
          ageMax: 13,
          salle: 'Salle principale'),
    ];

List<AutorisationSortie> _buildAutorisations() => [
      const AutorisationSortie(
          id: 'demo-aut-1',
          enfantMemberId: 'demo-m-011',
          parentMemberId: 'demo-m-001',
          activite: 'Sortie au parc — samedi 14 novembre',
          dateSortie: '2026-11-14',
          statut: 'en_attente'),
    ];

List<ActiviteJeunesse> _buildActivitesJeunesse() => [
      ActiviteJeunesse(
          id: 'demo-aj-1',
          titre: 'Soirée louange jeunesse',
          description: 'Louange, témoignages et jeux.',
          dateActivite: '2026-11-14',
          lieu: 'Temple du Plateau',
          responsableMemberId: 'demo-m-009',
          createdAt: DateTime.parse('2026-11-02T10:00:00')),
      ActiviteJeunesse(
          id: 'demo-aj-2',
          titre: 'Tournoi de football inter-cellules',
          dateActivite: '2026-11-21',
          lieu: 'Terrain de Yopougon',
          responsableMemberId: 'demo-m-012',
          createdAt: DateTime.parse('2026-11-03T10:00:00')),
    ];

List<Predication> _buildPredications() => [
      const Predication(
          id: 'demo-pred-1',
          titre: 'La foi qui déplace les montagnes',
          orateur: 'Pasteur Emmanuel Aka',
          datePredication: '2026-11-08',
          serie: 'Foi',
          dureeMinutes: 45),
      const Predication(
          id: 'demo-pred-2',
          titre: 'Grandir dans la prière',
          orateur: 'Pasteur Emmanuel Aka',
          datePredication: '2026-11-04',
          serie: 'Prière',
          dureeMinutes: 40),
      const Predication(
          id: 'demo-pred-3',
          titre: 'L’amour du prochain',
          orateur: 'Pasteur Emmanuel Aka',
          datePredication: '2026-11-01',
          serie: 'Amour',
          dureeMinutes: 42),
    ];

List<PlanLecture> _buildPlansLecture() => [
      const PlanLecture(
          id: 'demo-plan-lec-1',
          nom: 'Lecture de l’Évangile de Jean',
          description: 'Un chapitre par jour pendant 21 jours.',
          dureeJours: 21),
      const PlanLecture(
          id: 'demo-plan-lec-2',
          nom: 'Psaumes de louange',
          description: 'Un psaume par jour pendant 30 jours.',
          dureeJours: 30),
    ];

/// Cours de l'école biblique (démo).
List<CoursEcole> _buildCoursEcole() => [
      const CoursEcole(
          id: 'demo-cours-1',
          titre: 'Fondements de la foi',
          description:
              'Les bases de la foi chrétienne : Dieu, Jésus-Christ, le Saint-Esprit et la prière.',
          niveau: 'debutant'),
      const CoursEcole(
          id: 'demo-cours-2',
          titre: 'Étude des Psaumes',
          description: 'Lire et méditer les Psaumes, un par un.',
          niveau: 'intermediaire'),
    ];

/// Leçons de l'école biblique (démo).
List<LeconEcole> _buildLeconsEcole() => [
      const LeconEcole(
          id: 'demo-lecon-1',
          coursId: 'demo-cours-1',
          ordre: 1,
          titre: 'Dieu créateur',
          contenu:
              'Au commencement, Dieu créa les cieux et la terre. Tout ce qui existe vient de lui.',
          referenceBiblique: 'Genèse 1:1'),
      const LeconEcole(
          id: 'demo-lecon-2',
          coursId: 'demo-cours-1',
          ordre: 2,
          titre: 'La foi qui sauve',
          contenu:
              'Dieu a tant aimé le monde qu’il a donné son Fils unique, afin que quiconque croit en lui ne périsse point, mais qu’il ait la vie éternelle.',
          referenceBiblique: 'Jean 3:16'),
      const LeconEcole(
          id: 'demo-lecon-3',
          coursId: 'demo-cours-2',
          ordre: 1,
          titre: 'Le berger et ses brebis',
          contenu:
              'L’Éternel est mon berger : je ne manquerai de rien. Il me fait reposer dans de verts pâturages.',
          referenceBiblique: 'Psaume 23:1-2'),
    ];

/// Inscriptions de l'école biblique (démo) : Awa Koné suit le cours 1.
List<InscriptionEcole> _buildInscriptionsEcole() => [
      const InscriptionEcole(
          id: 'demo-insc-1',
          coursId: 'demo-cours-1',
          memberId: 'demo-m-001',
          statut: 'inscrit',
          dateInscription: '2026-11-10'),
    ];

List<Livre> _buildLivres() => [
      const Livre(id: 'demo-livre-1', titre: 'La Bible', exemplaires: 5),
      const Livre(
          id: 'demo-livre-2',
          titre: 'Le chrétien et la prière',
          auteur: 'Pasteur Emmanuel Aka',
          categorie: 'Prière',
          exemplaires: 2),
      const Livre(
          id: 'demo-livre-3',
          titre: 'Grandir dans la foi',
          categorie: 'Formation',
          exemplaires: 3),
      const Livre(
          id: 'demo-livre-4',
          titre: 'Histoire de l’Église en Côte d’Ivoire',
          categorie: 'Histoire',
          exemplaires: 1),
    ];

List<PretLivre> _buildPretsLivres() => [
      const PretLivre(
          id: 'demo-pret-1',
          livreId: 'demo-livre-2',
          memberId: 'demo-m-006',
          datePret: '2026-11-02',
          dateRetourPrevue: '2026-11-20',
          statut: 'en_cours'),
      const PretLivre(
          id: 'demo-pret-2',
          livreId: 'demo-livre-3',
          memberId: 'demo-m-011',
          datePret: '2026-10-10',
          dateRetourPrevue: '2026-10-24',
          dateRetour: '2026-10-22',
          statut: 'rendu'),
    ];

List<Salle> _buildSalles() => [
      const Salle(
          id: 'demo-salle-1',
          nom: 'Temple principal',
          capacite: 300,
          description: 'Salle de culte principale.'),
      const Salle(
          id: 'demo-salle-2',
          nom: 'Salle des enfants',
          capacite: 60,
          description: 'École du dimanche.'),
      const Salle(
          id: 'demo-salle-3',
          nom: 'Bureau du pasteur',
          capacite: 10,
          description: 'Entretiens pastoraux.'),
    ];

List<ReservationSalle> _buildReservationsSalles() => [
      const ReservationSalle(
          id: 'demo-res-1',
          salleId: 'demo-salle-2',
          titre: 'Répétition chorale enfants',
          debut: '2026-11-14T09:00',
          fin: '2026-11-14T11:00',
          reservePar: 'Fatou Diabaté',
          statut: 'confirmee'),
      const ReservationSalle(
          id: 'demo-res-2',
          salleId: 'demo-salle-1',
          titre: 'Mariage Kouassi & Awa',
          debut: '2026-12-05T10:00',
          fin: '2026-12-05T13:00',
          reservePar: 'Koffi Yao',
          statut: 'confirmee'),
    ];

List<Materiel> _buildMateriel() => [
      const Materiel(
          id: 'demo-mat-1',
          nom: 'Sono',
          categorie: 'Audio',
          quantite: 1,
          etat: 'bon'),
      const Materiel(
          id: 'demo-mat-2',
          nom: 'Vidéoprojecteur',
          categorie: 'Vidéo',
          quantite: 1,
          etat: 'bon'),
      const Materiel(
          id: 'demo-mat-3',
          nom: 'Chaises',
          categorie: 'Mobilier',
          quantite: 150,
          etat: 'bon'),
      const Materiel(
          id: 'demo-mat-4',
          nom: 'Clavier',
          categorie: 'Musique',
          quantite: 1,
          etat: 'a_reparer'),
    ];

List<MaintenanceMateriel> _buildMaintenances() => [
      const MaintenanceMateriel(
          id: 'demo-maint-1',
          materielId: 'demo-mat-4',
          dateMaintenance: '2026-11-03',
          description: 'Touche défectueuse — réparation chez le technicien.',
          coutFcfa: 15000,
          realisePar: 'Technicien Sono Abidjan'),
    ];

// -- Administration, rattachements, transferts -------------------------------

List<RoleEglise> _buildRoles() => [
      const RoleEglise(
          userId: 'demo-user-admin',
          role: 'admin_eglise',
          fullName: 'Admin Grâce Divine',
          email: 'admin@gracedivine.ci'),
      const RoleEglise(
          userId: 'demo-user-tresorier',
          role: 'tresorier',
          fullName: 'Mariam Traoré',
          email: 'mariam.traore@demo.ci'),
      const RoleEglise(
          userId: 'demo-user-culte',
          role: 'responsable_culte',
          fullName: 'Awa Koné',
          email: 'awa.kone@demo.ci'),
      const RoleEglise(
          userId: 'demo-user-membre',
          role: 'membre',
          fullName: 'Koffi Yao',
          email: 'koffi.yao@demo.ci'),
    ];

List<AuditEntree> _buildAudit() => [
      AuditEntree(
          id: 'demo-audit-1',
          action: 'connexion',
          details: {'email': 'admin@gracedivine.ci'},
          createdAt: DateTime.parse('2026-11-10T08:00:00'),
          utilisateur: 'Admin Grâce Divine'),
      AuditEntree(
          id: 'demo-audit-2',
          action: 'contribution creee',
          details: {'montant_fcfa': 35000, 'type': 'dime'},
          createdAt: DateTime.parse('2026-11-10T08:05:00'),
          utilisateur: 'Admin Grâce Divine'),
      AuditEntree(
          id: 'demo-audit-3',
          action: 'membre cree',
          details: {'matricule': 'GD-012', 'nom': 'David Konan'},
          createdAt: DateTime.parse('2026-11-09T11:00:00'),
          utilisateur: 'Admin Grâce Divine'),
    ];

List<Rattachement> _buildRattachementsRecus() => [
      Rattachement(
          id: 'demo-ratt-1',
          status: 'en_attente',
          egliseId: DemoIds.marcory,
          egliseCode: 'NA-MAR',
          egliseNom: 'Nouvelle Alliance — Marcory',
          egliseVille: 'Abidjan',
          createdAt: DateTime.parse('2026-11-08T14:00:00')),
    ];

List<TransfertMembre> _buildTransferts() => [
      TransfertMembre(
          id: 'demo-tr-1',
          membreId: 'demo-m-007',
          membreNom: 'Aïcha Bamba',
          ancienMatricule: 'GD-007',
          egliseDepartId: DemoIds.plateau,
          egliseDepartCode: 'GD-PLAT',
          egliseDepartNom: 'Grâce Divine — Plateau',
          egliseDepartVille: 'Abidjan',
          egliseArriveeId: DemoIds.yopougon,
          egliseArriveeCode: 'GD-YOP',
          egliseArriveeNom: 'Grâce Divine — Yopougon',
          egliseArriveeVille: 'Abidjan',
          motif: 'Déménagement à Yopougon',
          status: 'en_attente',
          decisionDepart: 'en_attente',
          decisionArrivee: 'en_attente',
          createdAt: DateTime.parse('2026-11-09T10:00:00')),
      // Historique : David Konan, arrivé de Bouaké, matricule GD-012.
      TransfertMembre(
          id: 'demo-tr-2',
          membreId: 'demo-m-012',
          membreNom: 'David Konan',
          ancienMatricule: 'GB-009',
          nouveauMatricule: 'GD-012',
          egliseDepartId: DemoIds.bouake,
          egliseDepartCode: 'GD-BKE',
          egliseDepartNom: 'Grâce Divine — Bouaké',
          egliseDepartVille: 'Bouaké',
          egliseArriveeId: DemoIds.plateau,
          egliseArriveeCode: 'GD-PLAT',
          egliseArriveeNom: 'Grâce Divine — Plateau',
          egliseArriveeVille: 'Abidjan',
          status: 'accepte',
          decisionDepart: 'accepte',
          decisionArrivee: 'accepte',
          createdAt: DateTime.parse('2026-09-15T10:00:00')),
    ];

List<DemandeLiaison> _buildDemandesLiaison() => [
      DemandeLiaison(
          id: 'demo-dem-1',
          status: 'en_attente',
          memberId: 'demo-m-002',
          matricule: 'GD-002',
          membreNom: 'Koffi Yao',
          membreEmail: 'koffi.yao@demo.ci',
          userId: 'demo-user-membre',
          userEmail: 'koffi.yao@demo.ci',
          userNom: 'Koffi Yao',
          createdAt: DateTime.parse('2026-11-09T09:00:00')),
    ];

List<EglisePaiement> _buildPaiements() => [
      const EglisePaiement(
        id: 'demo-pay-1',
        fournisseurCode: 'wave',
        fournisseurNom: 'Wave',
        type: 'mobile_money',
        pays: 'CI',
        libelle: 'Wave — compte de l’église',
        apercu: '•••• 0701',
        actif: true,
        champs: [
          ChampPaiementConfigure(
              nom: 'api_key', label: 'Clé API', secret: true, configure: true),
          ChampPaiementConfigure(
              nom: 'marchand',
              label: 'Identifiant marchand',
              secret: false,
              configure: true),
        ],
      ),
    ];

EgliseParametres _buildParametres() => const EgliseParametres(
      adresse: 'Rue du Commerce, Le Plateau',
      ville: 'Abidjan',
      telephone: '+225 27 22 00 00 00',
      email: 'contact@gracedivine.ci',
      waveNumero: '+225 07 47 00 01',
      orangeNumero: '+225 07 47 00 02',
      mtnNumero: '+225 05 47 00 03',
      devise: 'FCFA',
      fuseauHoraire: 'Africa/Abidjan',
      egliseNom: 'Grâce Divine — Plateau',
      egliseCode: 'GD-PLAT',
    );
