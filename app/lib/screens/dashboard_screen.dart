import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/mere_badge.dart';
import '../widgets/screen_header.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'annonces_screen.dart';
import 'annexes_screen.dart';
import 'contribution_form_screen.dart';
import 'cultes_screen.dart';
import 'finances_mere_screen.dart';
import 'member_form_screen.dart';
import 'mes_eglises_screen.dart';
import 'plateforme_screen.dart';
import 'tree_screen.dart';

class _DashboardData {
  final int membresTotal;
  final Map<String, ContributionTotals> totaux;
  final RapportConsolide? rapport;
  final List<Announcement> annonces;
  final List<Culte> cultes;

  const _DashboardData({
    required this.membresTotal,
    required this.totaux,
    required this.rapport,
    required this.annonces,
    required this.cultes,
  });
}

/// Tableau de bord : carte « Aujourd'hui » avec le prochain culte,
/// 4 chiffres avec pastille de couleur, « Mon réseau », annonces
/// récentes et 4 actions rapides. Chiffres de mon église + consolidé
/// du réseau (`GET /rapports/consolide`, admin de la mère seulement).
/// Rien d'inventé : que des données réelles, et des états vides
/// quand il n'y a rien.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

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
    Map<String, ContributionTotals> totaux = {};
    if (state.canReadFinances) {
      final page = await api.getContributions();
      totaux = page.totaux;
    }
    RapportConsolide? rapport;
    if (state.isAdmin) {
      try {
        rapport = await api.getRapport();
      } catch (_) {
        rapport = null; // Une sous-église admin n'a pas de réseau : on ignore.
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
      totaux: totaux,
      rapport: rapport,
      annonces: annonces,
      cultes: cultes,
    );
  }

  int _totalEntrees(Map<String, ContributionTotals> totaux) {
    var sum = 0;
    for (final entry in totaux.entries) {
      if (entry.key != 'depense') sum += entry.value.totalFcfa;
    }
    return sum;
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
                const EnteteEcran(
                  titre: 'Accueil',
                  sousTitre: 'Voici votre église en un coup d’œil.',
                ),
                SoftCard(
                  color: AppTheme.orClair,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChurchAvatar(church: church, radius: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  church?.name ?? '—',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${church?.code ?? ''} · ${church?.city ?? ''} · ${state.roleLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (church?.isMere ?? false) ...[
                                  const SizedBox(height: 8),
                                  const Row(
                                    children: [
                                      MereBadge(),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Tête de votre réseau.',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Changer d'église : l'écran dédié « Mes églises »
                      // est paginé et cherchable, il remplace la liste
                      // complète qui était dans le tiroir.
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const MesEglisesScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.swap_horiz_outlined),
                          label: const Text('Changer d’église'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Tranche P1 : aperçu de l'espace fidèle, pour voir
                // l'application comme un fidèle la voit. Aperçu local
                // seulement : ni la session ni le rôle ne changent.
                SoftCard(
                  color: AppTheme.orClair,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Démonstration des deux espaces',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Le fidèle a sa propre interface, avec sa '
                        'navigation à lui. Touchez le bouton pour la voir.',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context
                              .read<AppState>()
                              .entrerApercuFidele(),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Voir l’espace fidèle'),
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
                        BoutonAvecAide(
                          label: 'Voir les chiffres de la plateforme',
                          aide: 'Le total de toutes les églises, sans '
                              'voir les noms des personnes.',
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
                    final entrees = _totalEntrees(data.totaux);
                    final depenses =
                        data.totaux['depense']?.totalFcfa ?? 0;
                    final prochain = _prochainCulte(data.cultes);
                    final recentes = _annoncesRecentes(data.annonces);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Aujourd'hui : la date du jour et le prochain culte.
                        SoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Aujourd’hui',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatDate(DateTime.now()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (prochain == null)
                                const Text('Aucun culte à venir.')
                              else
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: AppTheme.orClair,
                                    child: Icon(
                                      Icons.church_outlined,
                                      color: AppTheme.bleuNuit,
                                    ),
                                  ),
                                  title: Text(
                                    prochain.titre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${formatDateTime(prochain.date)}'
                                    '${prochain.lieu == null || prochain.lieu!.isEmpty ? '' : ' · ${prochain.lieu}'}'
                                    '${prochain.orateur == null || prochain.orateur!.isEmpty ? '' : ' · ${prochain.orateur}'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _ouvrir(
                                      context, const CultesScreen()),
                                  icon: const Icon(
                                      Icons.calendar_month_outlined),
                                  label: const Text('Voir les cultes'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SectionTitle(title: 'Mon église'),
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
                                  label: 'Argent reçu',
                                  value: formatFcfa(entrees),
                                  icon: Icons.trending_up,
                                  color: AppTheme.vertFonce,
                                  aide: 'Montants confirmés par la '
                                      'structure.',
                                ),
                                StatCard(
                                  label: 'Argent dépensé',
                                  value: formatFcfa(depenses),
                                  icon: Icons.trending_down,
                                  color: AppTheme.rougeErreur,
                                  aide: 'Dépenses confirmées par la '
                                      'structure.',
                                ),
                                StatCard(
                                  label: 'Annonces',
                                  value: '${data.annonces.length}',
                                  icon: Icons.campaign_outlined,
                                  color: AppTheme.orFonce,
                                  aide: 'Messages publiés pour votre '
                                      'église. Touchez pour les lire.',
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AnnoncesScreen(),
                                      ),
                                    );
                                  },
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
                                        ? 'Aucune église rattachée pour l’instant. Créez-en une depuis « Réseau ».'
                                        : 'Votre église est une annexe : elle ne peut pas avoir de sous-église.',
                                  ),
                                const SizedBox(height: 12),
                                BoutonAvecAide(
                                  label: 'Voir mon réseau',
                                  aide: 'Votre église et ses sous-églises, '
                                      'avec leurs chiffres.',
                                  icon: Icons.account_tree_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const TreeScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                BoutonAvecAide(
                                  label: 'Voir les finances en détail',
                                  aide: 'Chaque entrée et chaque dépense, '
                                      'église par église.',
                                  icon: Icons.account_balance_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const FinancesMereScreen(),
                                      ),
                                    );
                                  },
                                ),
                                // Une annexe n'a pas d'annexe : le bouton
                                // n'existe que pour une église mère.
                                if (church?.isMere ?? false) ...[
                                  const SizedBox(height: 12),
                                  BoutonAvecAide(
                                    label: 'Voir mes annexes',
                                    aide: 'Les églises annexes rattachées à '
                                        'la vôtre, et leurs codes.',
                                    icon: Icons.hub_outlined,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AnnexesScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SectionTitle(title: 'Annonces récentes'),
                        if (recentes.isEmpty)
                          const SoftCard(
                            child: Text(
                                'Aucune annonce pour l’instant.'),
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
                // Actions rapides : seulement celles que le rôle
                // permet, chacune ouvre directement son écran de
                // création. Sans aucune action permise, rien ne
                // s'affiche.
                if (state.canManageMembers ||
                    state.canManageFinances ||
                    state.isAdmin) ...[
                  const SectionTitle(title: 'Actions rapides'),
                  SoftCard(
                    child: Column(
                      children: [
                        if (state.canManageMembers)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                                Icons.person_add_outlined),
                            title: const Text('Nouveau membre'),
                            trailing: const Icon(
                                Icons.chevron_right_outlined),
                            onTap: () => _ouvrir(
                                context, const MemberFormScreen()),
                          ),
                        if (state.canManageFinances)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                                Icons.add_circle_outline),
                            title: const Text('Nouvelle contribution'),
                            trailing: const Icon(
                                Icons.chevron_right_outlined),
                            onTap: () => _ouvrir(context,
                                const ContributionFormScreen()),
                          ),
                        if (state.canManageMembers)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.church_outlined),
                            title: const Text('Nouveau culte'),
                            trailing: const Icon(
                                Icons.chevron_right_outlined),
                            onTap: () => _ouvrir(
                                context, const CultesScreen()),
                          ),
                        if (state.isAdmin)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                                Icons.campaign_outlined),
                            title: const Text('Nouvelle annonce'),
                            trailing: const Icon(
                                Icons.chevron_right_outlined),
                            onTap: () => _ouvrir(
                                context, const AnnoncesScreen()),
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
