import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../models/cultes.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'annonces_screen.dart';
import 'annexes_screen.dart';
import 'cultes_screen.dart';
import 'mon_eglise_screen.dart';
import 'pastoral_screen.dart';
import 'prieres_screen.dart';
import 'rapports_mere_screen.dart';
import 'rapports_recus_screen.dart';
import 'serviteurs_screen.dart';
import 'transferts_screen.dart';

class _DashboardData {
  final int membresTotal;
  final int presencesJour;
  final int visiteursJour;
  final int nouveauxMembres;
  final int cotisationsMois;
  final int contributionsMois;
  final int entreesJour;
  final int sortiesJour;
  final int caisse;
  final int prieresEnAttente;
  final int liaisonsEnAttente;
  final int rapportsRecus;
  final int transfertsRattachements;
  final int absencesASuivre;
  final int anniversairesJour;
  final int rendezVousJour;
  final int serviteursJour;
  final int annexesTotal;
  final String? mereNom;
  final String? mereCode;
  final RapportConsolide? rapport;
  final List<Announcement> annonces;
  final List<Culte> cultes;

  const _DashboardData({
    required this.membresTotal,
    required this.presencesJour,
    required this.visiteursJour,
    required this.nouveauxMembres,
    required this.cotisationsMois,
    required this.contributionsMois,
    required this.entreesJour,
    required this.sortiesJour,
    required this.caisse,
    required this.prieresEnAttente,
    required this.liaisonsEnAttente,
    required this.rapportsRecus,
    required this.transfertsRattachements,
    required this.absencesASuivre,
    required this.anniversairesJour,
    required this.rendezVousJour,
    required this.serviteursJour,
    required this.annexesTotal,
    required this.mereNom,
    required this.mereCode,
    required this.rapport,
    required this.annonces,
    required this.cultes,
  });
}

/// Tableau de bord (maquette Membres Finances, écrans 19 et 36, le même
/// écran pour la mère et pour l'annexe) : carte violet profond
/// « Aujourd'hui » avec le prochain culte dedans, « Chiffres de mon
/// église », groupe « Contributions du jour », « Demandes en attente »
/// (mère) ou « À traiter » (annexe), « Membres à suivre », « Mes
/// annexes » (mère) ou « Mon église mère » (annexe), actions rapides
/// (Nouveau culte, Nouvelle annonce) et annonces récentes. Rien
/// d'inventé : que des données réelles, et des états vides quand il
/// n'y a rien. L'espace fidèle ne s'ouvre pas depuis l'admin
/// (périmètres étanches) : pas d'aperçu fidèle ici. La Plateforme
/// (super admin) ne s'ouvre pas depuis une église (maquette,
/// écran 33 : « Rien ici ne s'ouvre depuis une église ») : aucune
/// carte « Toute la plateforme » ici.
class DashboardScreen extends StatefulWidget {
  final ValueChanged<int> onAller;

  const DashboardScreen({super.key, required this.onAller});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final state = context.read<AppState>();
    final api = state.api;
    final membres = await api.getMembers();
    // Cotisations du mois en cours : le même suivi que l'écran
    // Finances complètes (`GET /cotisations/suivi`, mois en cours),
    // total payé, pas le total de tous les temps.
    int cotisationsMois = 0;
    if (state.canReadFinances) {
      try {
        final suivi = await api.getCotisationsSuivi();
        cotisationsMois = suivi.totaux.totalPayeFcfa;
      } catch (_) {
        cotisationsMois = 0;
      }
    }
    RapportConsolide? rapport;
    if (state.isAdmin) {
      try {
        rapport = await api.getRapport();
      } catch (_) {
        rapport = null; // Une sous-église admin n'a pas de réseau : on ignore.
      }
    }
    final maintenant = DateTime.now();
    final jour =
        '${maintenant.year}-${maintenant.month.toString().padLeft(2, '0')}-${maintenant.day.toString().padLeft(2, '0')}';
    int presencesJour = 0;
    try {
      final stats = await api.getPresenceStats(from: jour, to: jour);
      presencesJour = stats.presents;
    } catch (_) {
      presencesJour = 0; // Sans statistiques lisibles, la carte reste à 0.
    }
    int nouveauxMembres = 0;
    try {
      final page = await api.getMembers(status: 'nouveau_converti');
      nouveauxMembres = page.total;
    } catch (_) {
      nouveauxMembres = 0;
    }
    // Tableau du jour (maquette, écrans 19 et 36) : visiteurs,
    // contributions, demandes, membres à suivre, rendez-vous,
    // serviteurs, annexes, rapports reçus. Chaque compteur vient
    // d'une vraie lecture serveur ; un échec ne bloque pas le
    // tableau, le compteur reste à 0.
    int visiteursJour = 0;
    int contributionsMois = 0;
    int entreesJour = 0;
    int sortiesJour = 0;
    int caisse = 0;
    int prieresEnAttente = 0;
    int liaisonsEnAttente = 0;
    int rapportsRecus = 0;
    int transfertsRattachements = 0;
    int absencesASuivre = 0;
    int anniversairesJour = 0;
    int rendezVousJour = 0;
    int serviteursJour = 0;
    int annexesTotal = 0;
    if (state.canReadFinances) {
      try {
        // Contributions du mois, distinctes des cotisations :
        // dîmes, offrandes, dons et cotisations confirmés, créés
        // ce mois-ci (une dépense n'est pas une contribution).
        final page = await api.getContributions(status: 'confirme');
        for (final c in page.contributions) {
          final date = c.createdAt?.toLocal();
          if (date == null) continue;
          if (date.year != maintenant.year ||
              date.month != maintenant.month) {
            continue;
          }
          if (c.type == 'dime' ||
              c.type == 'offrande' ||
              c.type == 'don' ||
              c.type == 'cotisation') {
            contributionsMois += c.amountFcfa;
          }
        }
      } catch (_) {
        contributionsMois = 0;
      }
      try {
        final mouvements = await api.getCaisseMouvements();
        final aujourdHui =
            DateTime(maintenant.year, maintenant.month, maintenant.day);
        for (final m in mouvements) {
          final date = m.createdAt?.toLocal();
          if (date == null) continue;
          if (date.year == aujourdHui.year &&
              date.month == aujourdHui.month &&
              date.day == aujourdHui.day) {
            if (m.type == 'entree') {
              entreesJour += m.montantFcfa;
            } else {
              sortiesJour += m.montantFcfa;
            }
          }
        }
        caisse = (await api.getCaisseSolde()).solde;
      } catch (_) {
        entreesJour = 0;
        sortiesJour = 0;
        caisse = 0;
      }
    }
    if (state.isAdmin) {
      try {
        // Demandes d'adhésion : il n'existe pas de notion
        // d'adhésion côté serveur ; les demandes de rattachement
        // en attente sont la notion réelle la plus proche.
        final demandes = await api.getDemandesLiaison();
        liaisonsEnAttente =
            demandes.where((d) => d.status == 'en_attente').length;
      } catch (_) {
        liaisonsEnAttente = 0;
      }
      try {
        final annexes = await api.getAnnexes();
        annexesTotal = annexes.length;
      } catch (_) {
        annexesTotal = 0;
      }
    }
    if (state.canManageMembers) {
      try {
        final visiteurs = await api.getVisiteurs();
        visiteursJour =
            visiteurs.where((v) => v.dateVenue == jour).length;
      } catch (_) {
        visiteursJour = 0;
      }
      try {
        final demandes = await api.getDemandesPriere();
        prieresEnAttente = demandes
            .where((d) => d.statut == 'nouvelle' || d.statut == 'en_cours')
            .length;
      } catch (_) {
        prieresEnAttente = 0;
      }
      try {
        final radar = await api.getRadarAbsences();
        absencesASuivre = radar.length;
      } catch (_) {
        absencesASuivre = 0;
      }
      try {
        final anniversaires = await api.getAnniversaires();
        anniversairesJour =
            anniversaires.where((a) => a.joursRestants == 0).length;
      } catch (_) {
        anniversairesJour = 0;
      }
      try {
        final rendezVous = await api.getRendezVousAdmin();
        rendezVousJour = rendezVous
            .where((r) =>
                r.dateSouhaitee == jour &&
                (r.statut == 'en_attente' || r.statut == 'confirme'))
            .length;
      } catch (_) {
        rendezVousJour = 0;
      }
      try {
        // Serviteurs du jour : serviteurs affectés au culte du
        // jour, c'est-à-dire planifiés aujourd'hui (hors absents).
        final planning = await api.getPlanningServiteurs();
        serviteursJour = planning
            .where((p) => p.dateService == jour && p.statut != 'absent')
            .map((p) => p.serviteurId)
            .toSet()
            .length;
      } catch (_) {
        serviteursJour = 0;
      }
    }
    if (state.isAdmin && (state.church?.isMere ?? false)) {
      try {
        final recus = await api.getRapportsRecus();
        rapportsRecus = recus.length;
      } catch (_) {
        rapportsRecus = 0;
      }
      try {
        final transferts = await api.getTransferts();
        final rattachements = await api.getRattachements();
        transfertsRattachements = transferts.aTraiter.length +
            rattachements.recues
                .where((r) => r.status == 'en_attente')
                .length;
      } catch (_) {
        transfertsRattachements = 0;
      }
    }
    // Église mère d'une annexe (maquette, écran 36) : nom et code.
    // Le code vient des églises de l'état quand l'admin est aussi
    // membre de sa mère ; sinon, GET /moi/mere ne donne que le nom
    // (pas de route par identifiant pour retrouver le code), la
    // ligne s'affiche alors sans code, jamais inventé.
    String? mereNom;
    String? mereCode;
    if (state.isAdmin && !(state.church?.isMere ?? false)) {
      final parentId = state.church?.parentChurchId;
      if (parentId != null) {
        for (final m in state.eglises) {
          if (m.church.id == parentId) {
            mereNom = m.church.name;
            mereCode = m.church.code;
            break;
          }
        }
      }
      if (mereNom == null) {
        try {
          mereNom = (await api.getMaMere()).nom;
        } catch (_) {
          mereNom = null;
        }
      }
    }
    final annonces = await api.getAnnonces();
    List<Culte> cultes = [];
    try {
      cultes = await api.getCultes();
    } catch (_) {
      cultes = []; // Sans culte lisible, la carte « Aujourd'hui » reste vide.
    }
    return _DashboardData(
      membresTotal: membres.total,
      presencesJour: presencesJour,
      visiteursJour: visiteursJour,
      nouveauxMembres: nouveauxMembres,
      cotisationsMois: cotisationsMois,
      contributionsMois: contributionsMois,
      entreesJour: entreesJour,
      sortiesJour: sortiesJour,
      caisse: caisse,
      prieresEnAttente: prieresEnAttente,
      liaisonsEnAttente: liaisonsEnAttente,
      rapportsRecus: rapportsRecus,
      transfertsRattachements: transfertsRattachements,
      absencesASuivre: absencesASuivre,
      anniversairesJour: anniversairesJour,
      rendezVousJour: rendezVousJour,
      serviteursJour: serviteursJour,
      annexesTotal: annexesTotal,
      mereNom: mereNom,
      mereCode: mereCode,
      rapport: rapport,
      annonces: annonces,
      cultes: cultes,
    );
  }

  /// Prochain culte : le premier dont la date n'est pas passée.
  Culte? _prochainCulte(List<Culte> cultes) {
    final maintenant = DateTime.now();
    final futurs = cultes.where((c) {
      final d = c.date;
      return d != null && !d.isBefore(maintenant);
    }).toList();
    futurs.sort((a, b) => a.date!.compareTo(b.date!));
    return futurs.isEmpty ? null : futurs.first;
  }

  /// Annonces récentes : les 3 dernières, date la plus récente d'abord.
  List<Announcement> _annoncesRecentes(List<Announcement> annonces) {
    final triees = List<Announcement>.of(annonces);
    triees.sort((a, b) {
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return triees.take(3).toList();
  }

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _future = _load());
        await _future;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // En-tête de l'espace connecté : nom et logo de
                // l'église (règle d'Axel, 14 novembre 2026), pas le
                // logo e-System Church en grand. Pour une annexe,
                // l'en-tête montre aussi le rôle, le badge « Annexe »
                // et l'église mère (maquette, écran 36).
                EnteteEspace(eglise: church),
                const SizedBox(height: 16),
                FutureBuilder<_DashboardData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: AppLoading(),
                      );
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: () =>
                            setState(() => _future = _load()),
                      );
                    }
                    final data = snapshot.data!;
                    final prochain = _prochainCulte(data.cultes);
                    final recentes = _annoncesRecentes(data.annonces);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Aujourd'hui (maquette, écran 19) : carte
                        // violet profond avec le prochain culte dedans,
                        // puis les chiffres réels du tableau du jour.
                        // Aucun chiffre inventé.
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.violetProfond,
                                AppTheme.violetSecondaire,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Aujourd’hui',
                                    // Maquette, écrans 19 et 36 : 16 px.
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            color: Colors.white,
                                            fontSize: 16),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.or,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Prochain culte',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.violetProfond,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.white.withValues(
                                          alpha: 0.25)),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    if (prochain == null) ...[
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        color: AppTheme.or,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Aucun culte programmé',
                                        // Maquette, écrans 19 et 36 : 13,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                color: Colors.white,
                                                fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Le prochain culte s’affichera '
                                        'ici dès qu’il sera créé.',
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 11,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.white70,
                                                fontSize: 11.5),
                                      ),
                                    ] else ...[
                                      Text(
                                        prochain.titre,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 13,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                color: Colors.white,
                                                fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatDateTime(prochain.date)}'
                                        '${prochain.lieu == null || prochain.lieu!.isEmpty ? '' : ' · ${prochain.lieu}'}'
                                        '${prochain.orateur == null || prochain.orateur!.isEmpty ? '' : ' · ${prochain.orateur}'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 11,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.white70,
                                                fontSize: 11.5),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Chiffres de mon église (maquette, écrans 19
                        // et 36) : compteurs réels, rien d'inventé.
                        // L'aide sous un compteur est son texte vide
                        // du HTML quand il est à 0.
                        const SectionTitle(title: 'Chiffres de mon église'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount =
                                constraints.maxWidth > 600 ? 4 : 2;
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              // En 2 colonnes les cartes sont étroites :
                              // 0,85 leur donne la hauteur pour 3 lignes
                              // d'aide sans troncature (E1).
                              childAspectRatio:
                                  crossAxisCount == 2 ? 0.85 : 1.0,
                              children: [
                                StatCard(
                                  label: 'Membres',
                                  value: '${data.membresTotal}',
                                  icon: Icons.people_outline,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                ),
                                StatCard(
                                  label: 'Présences du jour',
                                  value: '${data.presencesJour}',
                                  icon: Icons.how_to_reg_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.vertFonce,
                                ),
                                StatCard(
                                  label: 'Visiteurs du jour',
                                  value: '${data.visiteursJour}',
                                  icon: Icons.person_outline,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                ),
                                StatCard(
                                  label: 'Contributions du mois',
                                  value: formatFcfa(data.contributionsMois),
                                  icon: Icons.volunteer_activism_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.orFonce,
                                ),
                                StatCard(
                                  label: 'Cotisations du mois',
                                  value: formatFcfa(data.cotisationsMois),
                                  icon: Icons.savings_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.orFonce,
                                ),
                                StatCard(
                                  label: 'Nouveaux à accueillir',
                                  value: '${data.nouveauxMembres}',
                                  icon: Icons.person_add_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  aide: data.nouveauxMembres == 0
                                      ? 'Aucun nouveau membre'
                                      : null,
                                  onTap: () => widget.onAller(1),
                                ),
                                StatCard(
                                  label: 'Rendez-vous du jour',
                                  value: '${data.rendezVousJour}',
                                  icon: Icons.event_available_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  aide: data.rendezVousJour == 0
                                      ? 'Aucun rendez-vous aujourd’hui'
                                      : null,
                                  // Écran 22 : une seule entrée, la carte
                                  // Modules. La carte n'est pas cliquable.
                                ),
                                StatCard(
                                  label: 'Serviteurs du jour',
                                  value: '${data.serviteursJour}',
                                  icon: Icons.handshake_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  aide: data.serviteursJour == 0
                                      ? 'Aucun serviteur affecté au culte du jour'
                                      : null,
                                  onTap: () => _ouvrir(
                                      context, const ServiteursScreen()),
                                ),
                                if (state.isAdmin)
                                  StatCard(
                                    label: 'Annexes',
                                    value: '${data.annexesTotal}',
                                    icon: Icons.account_tree_outlined,
                                    tailleValeur: 22,
                                    color: AppTheme.violetProfond,
                                    onTap: () => _ouvrir(
                                        context, const AnnexesScreen()),
                                  ),
                                if (state.isAdmin &&
                                    (church?.isMere ?? false))
                                  StatCard(
                                    label: 'Rapports d’annexe reçus',
                                    value: '${data.rapportsRecus}',
                                    icon: Icons.description_outlined,
                                    tailleValeur: 22,
                                    color: AppTheme.violetProfond,
                                    onTap: () => _ouvrir(context,
                                        const RapportsRecusScreen()),
                                  ),
                              ],
                            );
                          },
                        ),
                        // Contributions du jour (maquette, écran 19) :
                        // entrées, sorties et caisse du jour.
                        if (state.canReadFinances) ...[
                          const SectionTitle(
                              title: 'Contributions du jour'),
                          SoftCard(
                            child: Column(
                              children: [
                                _LigneChiffre(
                                  titre: 'Entrées du jour',
                                  valeur: formatFcfa(data.entreesJour),
                                  tailleValeur: 17,
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Sorties du jour',
                                  valeur: formatFcfa(data.sortiesJour),
                                  tailleValeur: 17,
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Caisse',
                                  valeur: formatFcfa(data.caisse),
                                  tailleValeur: 17,
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Demandes en attente (mère, écran 19) ou
                        // À traiter (annexe, écran 36) : 4 compteurs
                        // pour la mère, 2 pour l'annexe.
                        if (state.isAdmin || state.canManageMembers) ...[
                          SectionTitle(
                              title: (church?.isMere ?? false)
                                  ? 'Demandes en attente'
                                  : 'À traiter'),
                          SoftCard(
                            child: Column(
                              children: [
                                if (state.canManageMembers)
                                  _LigneChiffre(
                                    titre: 'Demandes de prière',
                                    sousTitre:
                                        'Reçues des membres, à traiter',
                                    valeur: '${data.prieresEnAttente}',
                                    onTap: () => _ouvrir(
                                        context, const PrieresScreen()),
                                  ),
                                if (state.canManageMembers &&
                                    state.isAdmin)
                                  const Divider(),
                                if (state.isAdmin)
                                  _LigneChiffre(
                                    titre: 'Demandes d’adhésion',
                                    sousTitre:
                                        'Visiteurs et nouveaux à valider',
                                    valeur: '${data.liaisonsEnAttente}',
                                    onTap: () => _ouvrir(
                                        context, const MonEgliseScreen()),
                                  ),
                                if (state.isAdmin &&
                                    (church?.isMere ?? false)) ...[
                                  const Divider(),
                                  _LigneChiffre(
                                    titre: 'Rapports d’annexe reçus',
                                    sousTitre:
                                        'Envoyés par les annexes, à lire',
                                    valeur: '${data.rapportsRecus}',
                                    onTap: () => _ouvrir(context,
                                        const RapportsRecusScreen()),
                                  ),
                                  const Divider(),
                                  _LigneChiffre(
                                    titre: 'Transferts et rattachements',
                                    sousTitre:
                                        'Entre l’église mère et ses annexes',
                                    valeur:
                                        '${data.transfertsRattachements}',
                                    onTap: () => _ouvrir(
                                        context, const TransfertsScreen()),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        // Membres à suivre (maquette, écran 19) :
                        // absences à relancer, anniversaires du jour,
                        // nouveaux à accueillir.
                        if (state.canManageMembers) ...[
                          const SectionTitle(title: 'Membres à suivre'),
                          SoftCard(
                            child: Column(
                              children: [
                                _LigneChiffre(
                                  titre: 'Absences à relancer',
                                  sousTitre: data.absencesASuivre == 0
                                      ? 'Aucune absence signalée'
                                      : 'Absents plusieurs cultes de suite',
                                  valeur: '${data.absencesASuivre}',
                                  onTap: () => _ouvrir(
                                      context, const PastoralScreen()),
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Anniversaires du jour',
                                  sousTitre: data.anniversairesJour == 0
                                      ? 'Aucun anniversaire aujourd’hui'
                                      : null,
                                  valeur: '${data.anniversairesJour}',
                                  onTap: () => widget.onAller(1),
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Nouveaux à accueillir',
                                  sousTitre: data.nouveauxMembres == 0
                                      ? 'Aucun nouveau membre'
                                      : null,
                                  valeur: '${data.nouveauxMembres}',
                                  onTap: () => widget.onAller(1),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (data.rapport != null) ...[
                          const SectionTitle(title: 'Mes annexes'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (data.rapport!.sousEglises.isEmpty) ...[
                                  if (church?.isMere ?? false) ...[
                                    // État vide de la maquette, écran 19.
                                    const Center(
                                      child: Text(
                                        'Aucun établissement relié',
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 13 px.
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Center(
                                      child: Text(
                                        'Aucune alerte d’annexe.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ] else
                                    const Text(
                                      'Votre église est une annexe : elle ne peut pas avoir de sous-église.',
                                    ),
                                ] else ...[
                                  Text(
                                    'Total de mes églises',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                      '${pluriel(data.rapport!.totauxReseau.membresActifs, 'membre actif', 'membres actifs')} · '
                                      '${pluriel(data.rapport!.totauxReseau.nombreContributions, 'contribution')} · '
                                      '${formatFcfa(data.rapport!.totauxReseau.totalFcfa)}'),
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  ...data.rapport!.sousEglises.map(
                                    (s) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                          Icons.account_tree_outlined),
                                      title: Text(
                                        s.egliseNom,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13.5),
                                      ),
                                      subtitle: Text(
                                          '${s.membresActifs} membres · ${formatFcfa(s.totalFcfa)}'
                                          '${s.niveau == 1 ? '' : ' · niveau ${s.niveau}'}',
                                          style: const TextStyle(fontSize: 11.5)),
                                      trailing: Text(
                                        '${s.nombreContributions} contributions',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SectionTitle(title: 'Annonces récentes'),
                        if (recentes.isEmpty)
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // État vide de la projection, mot pour mot.
                                Text(
                                  'Aucune annonce',
                                  // Maquette, écrans 19 et 36 : 14 px.
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Les annonces publiées par la structure apparaîtront ici.',
                                  // Maquette, écrans 19 et 36 : 11,5 px.
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ],
                            ),
                          )
                        else
                          SoftCard(
                            child: Column(
                              children: [
                                ...recentes.map(
                                  (a) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.campaign_outlined),
                                    title: Text(
                                      a.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5),
                                    ),
                                    subtitle: Text(
                                      '${a.body}'
                                      '${a.createdAt == null ? '' : ' · ${formatDate(a.createdAt)}'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AnnoncesScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _ouvrir(
                                        context, const AnnoncesScreen()),
                                    icon: const Icon(
                                        Icons.campaign_outlined),
                                    label: const Text('Toutes les annonces', style: TextStyle(fontSize: 13.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Mon église mère (annexe, maquette, écran 36) :
                        // nom et code de la mère, bouton d'envoi du
                        // rapport. Pour une mère, c'est la section
                        // « Mes annexes » ci-dessus qui s'affiche.
                        if (state.isAdmin &&
                            !(church?.isMere ?? false)) ...[
                          const SectionTitle(title: 'Mon église mère'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (data.mereNom != null) ...[
                                  Text(
                                    'Église mère ${data.mereNom}',
                                    // Maquette, écran 36 : 13 px.
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontSize: 13),
                                  ),
                                  if (data.mereCode != null) ...[
                                    const SizedBox(height: 4),
                                    // Maquette, écran 36 : 13 px.
                                    Text('Code ${data.mereCode}',
                                        style: const TextStyle(fontSize: 13)),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    'Le rapport part à ${data.mereNom}'
                                    '${data.mereCode != null ? ' · ${data.mereCode}' : ''}.',
                                    // Maquette, écran 36 : 11,5 px.
                                    style:
                                        const TextStyle(fontSize: 11.5),
                                  ),
                                ] else
                                  const Text(
                                    'Contactez votre église mère et envoyez '
                                    'vos rapports par e-mail, directement '
                                    'depuis votre espace.',
                                  ),
                                const SizedBox(height: 12),
                                BoutonDoux(
                                  label:
                                      'Envoyer un rapport à mon église mère',
                                  icon: Icons.email_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RapportsMereScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Actions rapides (maquette, écran 19) : Nouveau culte
                // et Nouvelle annonce seulement. Ajouter un membre se
                // fait depuis l'onglet Membres, les finances depuis
                // l'onglet Finances : pas de doublon. Seulement celles
                // que le rôle permet ; sans aucune action permise, rien
                // ne s'affiche.
                if (state.canManageMembers || state.isAdmin) ...[
                  const SectionTitle(title: 'Actions rapides'),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          constraints.maxWidth > 600 ? 4 : 2;
                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.1,
                        children: [
                          if (state.canManageMembers)
                            _ActionRapide(
                              icone: Icons.church_outlined,
                              titre: 'Nouveau culte',
                              sousTitre: (church?.isMere ?? false)
                                  ? 'Créer le prochain culte de l’église'
                                  : 'Créer le prochain culte de l’annexe',
                              onTap: () => ouvrirNouveauCulte(context),
                            ),
                          if (state.isAdmin)
                            _ActionRapide(
                              icone: Icons.campaign_outlined,
                              titre: 'Nouvelle annonce',
                              sousTitre: (church?.isMere ?? false)
                                  ? 'Informer les membres de l’église'
                                  : 'Informer les membres de l’annexe',
                              onTap: () => _ouvrir(
                                  context, const AnnoncesScreen()),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                // Rapports reçus, pour une mère (la carte « Mon
                // église mère » de l'annexe est dans le FutureBuilder,
                // elle a besoin des données chargées).
                if (state.isAdmin &&
                    (church?.isMere ?? false)) ...[
                  const SectionTitle(title: 'Rapports reçus'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rapports reçus',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Lisez les rapports envoyés par vos '
                          'églises annexes.',
                        ),
                        const SizedBox(height: 12),
                        BoutonDoux(
                          label: 'Ouvrir les rapports reçus',
                          icon: Icons.inbox_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RapportsRecusScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une action rapide : carte avec icône or, titre et sous-titre
/// (projection, IMG_4030). Toute la carte est cliquable.
class _ActionRapide extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _ActionRapide({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: AppTheme.orFonce, size: 28),
              const SizedBox(height: 8),
              Text(
                titre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Maquette, écrans 19 et 36 : 13,5 px.
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                        fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              Text(
                sousTitre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Maquette, écrans 19 et 36 : 11,5 px.
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne de chiffres dans un groupe du tableau de bord
/// (maquette, écrans 19 et 36) : titre, sous-titre facultatif et
/// valeur à droite, cliquable quand un écran la détaille.
class _LigneChiffre extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final String valeur;
  final VoidCallback? onTap;
  // Maquette : compteurs 11,5 px (Demandes, Membres à suivre),
  // montants 17 px (Contributions du jour).
  final double tailleValeur;

  const _LigneChiffre({
    required this.titre,
    this.sousTitre,
    required this.valeur,
    this.onTap,
    this.tailleValeur = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final sousTitre = this.sousTitre;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        titre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
      ),
      subtitle: sousTitre == null
          ? null
          : Text(
              sousTitre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
      trailing: Text(
        valeur,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.styleCode.copyWith(
          fontSize: tailleValeur,
          fontWeight: FontWeight.bold,
          color: AppTheme.violetProfond,
        ),
      ),
      onTap: onTap,
    );
  }
}
