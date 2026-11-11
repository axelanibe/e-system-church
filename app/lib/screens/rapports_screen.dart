import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stats.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Module 11 — Rapports : statistiques globales et export CSV.
class RapportsScreen extends StatefulWidget {
  const RapportsScreen({super.key});

  @override
  State<RapportsScreen> createState() => _RapportsScreenState();
}

class _RapportsScreenState extends State<RapportsScreen> {
  late Future<StatsGlobales> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<StatsGlobales> _load() {
    return context.read<AppState>().api.getStatsGlobales();
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _export(String type) async {
    try {
      final csv = await context.read<AppState>().api.exportCsv(type);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(type == 'membres'
              ? 'Export CSV — Membres'
              : 'Export CSV — Contributions'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(csv),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<StatsGlobales>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final stats = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          label: 'Membres actifs',
                          value: '${stats.membresActifs}',
                          icon: Icons.people_outlined,
                        ),
                        StatCard(
                          label: 'Nouveaux convertis',
                          value: '${stats.nouveauxConvertis}',
                          icon: Icons.person_add_outlined,
                        ),
                        StatCard(
                          label: 'Baptêmes',
                          value: '${stats.baptemes}',
                          icon: Icons.water_drop_outlined,
                        ),
                        StatCard(
                          label: 'Cultes ce mois-ci',
                          value: '${stats.cultesMois}',
                          icon: Icons.event_outlined,
                        ),
                        StatCard(
                          label: 'Présences ce mois-ci',
                          value: '${stats.presencesMois}',
                          icon: Icons.how_to_reg_outlined,
                        ),
                        StatCard(
                          label: 'Recettes ce mois-ci',
                          value: formatMontant(
                              stats.recettesMoisFcfa, state.devise),
                          icon: Icons.trending_up,
                          color: Colors.green,
                        ),
                        StatCard(
                          label: 'Dépenses ce mois-ci',
                          value: formatMontant(
                              stats.depensesMoisFcfa, state.devise),
                          icon: Icons.trending_down,
                          color: Colors.red,
                        ),
                      ],
                    );
                  },
                ),
                const SectionTitle(title: 'Réseau'),
                if (stats.reseau.isEmpty)
                  const EmptyState(
                    icon: Icons.account_tree_outlined,
                    message: 'Aucune sous-église rattachée pour l’instant.',
                  )
                else
                  ...stats.reseau.map((b) => ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.account_tree_outlined),
                        ),
                        title: Text(b.egliseNom),
                        subtitle: Text(
                            '${b.membresActifs} membre(s) actif(s) · ${b.nombreContributions} contribution(s)'),
                        trailing: Text(
                          formatMontant(b.totalFcfa, state.devise),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )),
                const SectionTitle(title: 'Export CSV'),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _export('membres'),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Membres'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _export('contributions'),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Contributions'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
