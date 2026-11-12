import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'annexes_screen.dart';

/// Détail d'une annexe, vu par sa mère : chiffres, compteurs et état
/// des modules. Que des agrégats, jamais de données nominatives.
class AnnexeDetailScreen extends StatefulWidget {
  final String annexeId;

  const AnnexeDetailScreen({super.key, required this.annexeId});

  @override
  State<AnnexeDetailScreen> createState() => _AnnexeDetailScreenState();
}

class _AnnexeDetailScreenState extends State<AnnexeDetailScreen> {
  late Future _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getAnnexeDetail(widget.annexeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail de l’annexe')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = context
                  .read<AppState>()
                  .api
                  .getAnnexeDetail(widget.annexeId)),
            );
          }
          final d = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = context
                  .read<AppState>()
                  .api
                  .getAnnexeDetail(widget.annexeId));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('${d.code} · ${d.city ?? ''}'),
                        const SizedBox(height: 4),
                        Text(
                          'Modules : ${d.modules.length}, tous actifs',
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Chiffres'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    StatMini(
                      label: 'Membres actifs',
                      value: '${d.membresActifs}',
                      icon: Icons.people_outline,
                    ),
                    StatMini(
                      label: 'Entrées confirmées',
                      value: formatFcfa(d.totalFcfa),
                      icon: Icons.trending_up,
                      color: AppTheme.bleuNuit,
                    ),
                    StatMini(
                      label: 'Dépenses confirmées',
                      value: formatFcfa(d.depensesFcfa),
                      icon: Icons.trending_down,
                      color: AppTheme.rougeErreur,
                    ),
                    StatMini(
                      label: 'Contributions',
                      value: '${d.nombreContributions}',
                      icon: Icons.volunteer_activism_outlined,
                    ),
                    StatMini(
                      label: 'Cultes',
                      value: '${d.cultes}',
                      icon: Icons.event_outlined,
                    ),
                    StatMini(
                      label: 'Présences',
                      value: '${d.presences}',
                      icon: Icons.how_to_reg_outlined,
                    ),
                    StatMini(
                      label: 'Annonces',
                      value: '${d.annonces}',
                      icon: Icons.campaign_outlined,
                    ),
                  ],
                ),
                const SectionTitle(title: 'Modules de l’annexe'),
                if (d.modules.isEmpty)
                  const Text('Aucun module.')
                else
                  ...d.modules.map((m) => ListTile(
                        leading: const Icon(Icons.check_circle_outlined,
                            color: AppTheme.bleuNuit),
                        title: Text(m.label),
                        subtitle: m.noyau
                            ? const Text('Noyau, toujours actif')
                            : const Text('Toujours actif'),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}
