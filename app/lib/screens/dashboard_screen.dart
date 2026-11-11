import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/mere_badge.dart';
import 'annexes_screen.dart';
import 'finances_mere_screen.dart';
import 'mes_eglises_screen.dart';
import 'plateforme_screen.dart';

class _DashboardData {
  final int membresTotal;
  final Map<String, ContributionTotals> totaux;
  final RapportConsolide? rapport;
  final int annoncesCount;

  const _DashboardData({
    required this.membresTotal,
    required this.totaux,
    required this.rapport,
    required this.annoncesCount,
  });
}

/// Tableau de bord : chiffres de mon église + consolidé du réseau
/// (`GET /rapports/consolide`, admin de la mère seulement).
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
    return _DashboardData(
      membresTotal: membres.total,
      totaux: totaux,
      rapport: rapport,
      annoncesCount: annonces.length,
    );
  }

  int _totalEntrees(Map<String, ContributionTotals> totaux) {
    var sum = 0;
    for (final entry in totaux.entries) {
      if (entry.key != 'depense') sum += entry.value.totalFcfa;
    }
    return sum;
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
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                        .headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold),
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
                                            overflow:
                                                TextOverflow.ellipsis,
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
                ),
                const SizedBox(height: 16),
                if (state.isSuperAdmin)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plateforme',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                              'Chiffres globaux de toutes les églises mères '
                              'ensemble, sans détail nominatif.'),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PlateformeScreen(),
                                  ),
                                );
                              },
                              icon:
                                  const Icon(Icons.public_outlined),
                              label: const Text(
                                  'Voir les chiffres de la plateforme'),
                            ),
                          ),
                        ],
                      ),
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
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              childAspectRatio: 1.6,
                              children: [
                                StatCard(
                                  label: 'Membres',
                                  value: '${data.membresTotal}',
                                  icon: Icons.people_outline,
                                ),
                                StatCard(
                                  label: 'Entrées confirmées',
                                  value: formatFcfa(entrees),
                                  icon: Icons.trending_up,
                                  color: AppTheme.vertFonce,
                                ),
                                StatCard(
                                  label: 'Dépenses confirmées',
                                  value: formatFcfa(depenses),
                                  icon: Icons.trending_down,
                                  color: AppTheme.rougeErreur,
                                ),
                                StatCard(
                                  label: 'Annonces',
                                  value: '${data.annoncesCount}',
                                  icon: Icons.campaign_outlined,
                                ),
                              ],
                            );
                          },
                        ),
                        if (data.rapport != null) ...[
                          const SectionTitle(title: 'Mon réseau'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Totaux du réseau',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                      '${data.rapport!.totauxReseau.membresActifs} membres actifs · '
                                      '${data.rapport!.totauxReseau.nombreContributions} contributions · '
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
                                    const Text(
                                        'Aucune sous-église pour l’instant. Créez-en une depuis l’arborescence.'),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FinancesMereScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                          Icons.account_balance_outlined),
                                      label: const Text(
                                          'Voir les finances en détail'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AnnexesScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.hub_outlined),
                                      label: const Text('Voir mes annexes'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
