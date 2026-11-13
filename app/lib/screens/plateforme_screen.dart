import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/plateforme.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Chiffres globaux de la plateforme e-System Church, super_admin
/// seulement (`GET /plateforme/chiffres`). Chiffres seulement : aucun
/// détail nominatif, aucune liste de membres, aucune gestion des membres
/// au jour le jour. La plateforme ne gère pas les membres, elle voit
/// seulement les chiffres de toutes les églises mères ensemble.
class PlateformeScreen extends StatefulWidget {
  const PlateformeScreen({super.key});

  @override
  State<PlateformeScreen> createState() => _PlateformeScreenState();
}

class _PlateformeScreenState extends State<PlateformeScreen> {
  late Future<ChiffresPlateforme> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getPlateforme();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plateforme')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message:
              'Seul l’admin de la plateforme voit les chiffres globaux.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Plateforme')),
      body: FutureBuilder<ChiffresPlateforme>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(
                () => _future = context.read<AppState>().api.getPlateforme(),
              ),
            );
          }
          final chiffres = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(
              () => _future = context.read<AppState>().api.getPlateforme(),
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Card(
                        color: AppTheme.orClair,
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Chiffres globaux de toutes les églises mères '
                            'ensemble. Aucun détail nominatif, aucune '
                            'gestion des membres au jour le jour : la '
                            'plateforme voit seulement les chiffres.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Églises'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth > 600 ? 3 : 2;
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
                                label: 'Églises mères',
                                value: '${chiffres.eglisesMeres}',
                                icon: Icons.account_balance_outlined,
                              ),
                              StatCard(
                                label: 'Branches',
                                value: '${chiffres.branches}',
                                icon: Icons.account_tree_outlined,
                              ),
                              StatCard(
                                label: 'Églises au total',
                                value: '${chiffres.eglisesTotal}',
                                icon: Icons.church_outlined,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Membres et contributions'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth > 600 ? 3 : 2;
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
                                label: 'Membres actifs',
                                value: '${chiffres.membresActifs}',
                                icon: Icons.people_outline,
                              ),
                              StatCard(
                                label: 'Contributions confirmées',
                                value: '${chiffres.nombreContributions}',
                                icon: Icons.receipt_long_outlined,
                              ),
                              StatCard(
                                label: 'Total des contributions',
                                value: formatFcfa(
                                    chiffres.totalContributionsFcfa),
                                icon: Icons.trending_up,
                                color: AppTheme.bleuNuit,
                              ),
                              StatCard(
                                label: 'Dépenses confirmées',
                                value:
                                    formatFcfa(chiffres.depensesFcfa),
                                icon: Icons.trending_down,
                                color: AppTheme.rougeErreur,
                              ),
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
        },
      ),
    );
  }
}
