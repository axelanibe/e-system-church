import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../models/cultes.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'annonces_screen.dart';
import 'cultes_screen.dart';
import 'member_form_screen.dart';
import 'plateforme_screen.dart';
import 'rapports_mere_screen.dart';
import 'rapports_recus_screen.dart';

class _DashboardData {
  final int membresTotal;
  final int presencesJour;
  final int nouveauxMembres;
  final int cotisationsMois;
  final RapportConsolide? rapport;
  final List<Announcement> annonces;
  final List<Culte> cultes;

  const _DashboardData({
    required this.membresTotal,
    required this.presencesJour,
    required this.nouveauxMembres,
    required this.cotisationsMois,
    required this.rapport,
    required this.annonces,
    required this.cultes,
  });
}

/// Tableau de bord (projection, captures IMG_4027 à IMG_4031) :
/// carte bleu nuit « Aujourd'hui » avec le prochain culte dedans,
/// 4 chiffres réels, « Mon réseau », annonces récentes, actions
/// rapides, puis les rapports (mère ou annexes).
/// Chiffres de mon église + consolidé du réseau
/// (`GET /rapports/consolide`, admin de la mère seulement).
/// Rien d'inventé : que des données réelles, et des états vides
/// quand il n'y a rien.
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
    int presencesJour = 0;
    try {
      final maintenant = DateTime.now();
      final jour = '${maintenant.year}-${maintenant.month.toString().padLeft(2, '0')}-${maintenant.day.toString().padLeft(2, '0')}';
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
      nouveauxMembres: nouveauxMembres,
      cotisationsMois: cotisationsMois,
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
                // Aperçu multi-rôles (maquette de refonte) : remplace
                // la carte « Démonstration des deux espaces ». Même
                // accès que l'espace fidèle, en aperçu avec retour.
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.bleuNuit,
                        Color(0xFF1A355B),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'APERÇU MULTI-RÔLES',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.or,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Espace Fidèle',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Prévisualisez l’interface dédiée aux '
                                  'membres de votre assemblée.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.visibility_outlined,
                            color: AppTheme.or,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.or,
                            foregroundColor: AppTheme.bleuNuit,
                          ),
                          onPressed: () => context
                              .read<AppState>()
                              .entrerApercuFidele(),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text(
                              'Basculer vers l’espace fidèle'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (state.isSuperAdmin)
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toute la plateforme',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            'Chiffres globaux de toutes les églises mères '
                            'ensemble, sans détail nominatif.'),
                        const SizedBox(height: 12),
                        BoutonDoux(
                          label: 'Voir les chiffres de la plateforme',
                          icon: Icons.public_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PlateformeScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                if (state.isSuperAdmin) const SizedBox(height: 16),
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
                        // Aujourd'hui (projection, IMG_4027) : carte
                        // bleu nuit avec le prochain culte dedans,
                        // puis les 4 chiffres réels. Aucun chiffre
                        // inventé.
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.bleuNuit,
                                Color(0xFF1A355B),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(color: Colors.white),
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
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.bleuNuit,
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Le prochain culte s’affichera '
                                        'ici dès qu’il sera créé.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.white70),
                                      ),
                                    ] else ...[
                                      Text(
                                        prochain.titre,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatDateTime(prochain.date)}'
                                        '${prochain.lieu == null || prochain.lieu!.isEmpty ? '' : ' · ${prochain.lieu}'}'
                                        '${prochain.orateur == null || prochain.orateur!.isEmpty ? '' : ' · ${prochain.orateur}'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.white70),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
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
                                  color: AppTheme.bleuNuit,
                                  aide: 'Personnes inscrites dans votre '
                                      'église.',
                                ),
                                StatCard(
                                  label: 'Présences du jour',
                                  value: '${data.presencesJour}',
                                  icon: Icons.how_to_reg_outlined,
                                  color: AppTheme.vertFonce,
                                  aide: 'Présences pointées aujourd’hui.',
                                ),
                                StatCard(
                                  label: 'Cotisations du mois',
                                  value: formatFcfa(data.cotisationsMois),
                                  icon: Icons.savings_outlined,
                                  color: AppTheme.orFonce,
                                  aide: 'Cotisations payées ce mois-ci.',
                                ),
                                StatCard(
                                  label: 'Nouveaux membres',
                                  value: '${data.nouveauxMembres}',
                                  icon: Icons.person_add_outlined,
                                  color: AppTheme.bleuNuit,
                                  aide: 'Nouveaux convertis inscrits dans '
                                      'votre église.',
                                ),
                              ],
                            );
                          },
                        ),
                        if (data.rapport != null) ...[
                          const SectionTitle(title: 'Mon réseau'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
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
                                    title: Text(s.egliseNom),
                                    subtitle: Text(
                                        '${s.membresActifs} membres · ${formatFcfa(s.totalFcfa)}'
                                        '${s.niveau == 1 ? '' : ' · niveau ${s.niveau}'}'),
                                    trailing: Text(
                                        '${s.nombreContributions} contributions'),
                                  ),
                                ),
                                if (data.rapport!.sousEglises.isEmpty)
                                  Text(
                                    (church?.isMere ?? false)
                                        ? 'Aucune église rattachée pour l’instant. Créez-en une depuis « Mes annexes et Réseau » dans le menu.'
                                        : 'Votre église est une annexe : elle ne peut pas avoir de sous-église.',
                                  ),
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
                                const Text(
                                    'Aucune annonce pour l’instant.'),
                                if (state.isAdmin) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _ouvrir(context,
                                          const AnnoncesScreen()),
                                      icon: const Icon(
                                          Icons.campaign_outlined),
                                      label: const Text(
                                          'Nouvelle annonce'),
                                    ),
                                  ),
                                ],
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
                                    ),
                                    subtitle: Text(
                                      '${a.body}'
                                      '${a.createdAt == null ? '' : ' · ${formatDate(a.createdAt)}'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
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
                                    label: const Text('Toutes les annonces'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Actions rapides (projection, IMG_4030) : grille
                // 2 colonnes, icône or, titre et sous-titre. Les 4
                // de la projection : Ajouter un membre, Nouveau
                // culte, Nouvelle annonce, Voir les finances (onglet
                // Finances, pas un écran en double). La création
                // d'une contribution se fait depuis l'onglet Finances.
                // Seulement celles que le rôle permet ; sans aucune
                // action permise, rien ne s'affiche.
                if (state.canManageMembers ||
                    state.canReadFinances ||
                    state.isAdmin) ...[
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
                              icone: Icons.person_add_outlined,
                              titre: 'Ajouter un membre',
                              sousTitre:
                                  'Création guidée en 3 étapes',
                              onTap: () => _ouvrir(
                                  context, const MemberFormScreen()),
                            ),
                          if (state.canManageMembers)
                            _ActionRapide(
                              icone: Icons.church_outlined,
                              titre: 'Nouveau culte',
                              sousTitre: 'Conducteur et pointage QR',
                              onTap: () => _ouvrir(
                                  context, const CultesScreen()),
                            ),
                          if (state.isAdmin)
                            _ActionRapide(
                              icone: Icons.campaign_outlined,
                              titre: 'Nouvelle annonce',
                              sousTitre:
                                  'Publiée pour toute la structure',
                              onTap: () => _ouvrir(
                                  context, const AnnoncesScreen()),
                            ),
                          if (state.canReadFinances)
                            _ActionRapide(
                              icone:
                                  Icons.account_balance_wallet_outlined,
                              titre: 'Voir les finances',
                              sousTitre: 'Cotisations, caisse et reçus',
                              onTap: () => widget.onAller(2),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                // Tranche P5 : rapports à mon église mère, pour
                // une annexe ; rapports reçus, pour une mère.
                // Textes repris mot pour mot de la projection.
                if (state.isAdmin &&
                    !(church?.isMere ?? false)) ...[
                  const SectionTitle(title: 'Mon église mère'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rapports à mon église mère',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Contactez votre église mère et envoyez '
                          'vos rapports par e-mail, directement '
                          'depuis votre espace.',
                        ),
                        const SizedBox(height: 12),
                        BoutonDoux(
                          label: 'Ouvrir les rapports',
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
                if (state.isAdmin &&
                    (church?.isMere ?? false)) ...[
                  const SectionTitle(title: 'Mes églises annexes'),
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
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                sousTitre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
