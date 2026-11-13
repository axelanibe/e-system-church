import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/paiements.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'receipt_screen.dart';

/// Mes cotisations (tranche P1) : total cotisé réel du serveur,
/// historique avec reçus, et paiement par les moyens configurés de
/// l'église. Le paiement lui-même passe par le parcours existant :
/// le fidèle paie par Wave, Orange Money ou MTN sur le numéro de son
/// église, la cotisation apparaît ici une fois confirmée par la
/// structure. Aucun paiement n'est créé depuis cet écran (la création
/// de contribution reste admin et trésorier).
class CotisationsScreen extends StatefulWidget {
  const CotisationsScreen({super.key});

  @override
  State<CotisationsScreen> createState() => _CotisationsScreenState();
}

class _CotisationsScreenState extends State<CotisationsScreen> {
  late Future<List<Contribution>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMesContributions();
  }

  void _refresh() =>
      setState(() => _future = context.read<AppState>().api.getMesContributions());

  Future<void> _payer() async {
    final state = context.read<AppState>();
    final egliseId = state.church?.id;
    if (egliseId == null) return;
    List<EglisePaiement> moyens = [];
    try {
      moyens = (await state.api.getMesPaiements(egliseId))
          .where((m) => m.actif)
          .toList();
    } catch (e) {
      if (mounted) showApiError(context, e);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payer ma cotisation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (moyens.isEmpty)
                const Text(
                  'Aucun moyen de paiement configuré pour l’instant. '
                  'Contactez votre église pour payer votre cotisation.',
                )
              else ...[
                const Text(
                  'Payez sur le numéro de votre église, avec le moyen '
                  'de votre choix :',
                ),
                const SizedBox(height: 12),
                ...moyens.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(m.fournisseurNom),
                      subtitle: Text(
                        [
                          if ((m.libelle ?? '').isNotEmpty) m.libelle!,
                          if ((m.apercu ?? '').isNotEmpty) m.apercu!,
                        ].join(' · '),
                      ),
                    )),
                const SizedBox(height: 8),
                const Text(
                  'Après votre paiement, votre cotisation apparaîtra '
                  'ici une fois confirmée par votre église, avec son reçu.',
                ),
              ],
            ],
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
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes cotisations')),
      body: FutureBuilder<List<Contribution>>(
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
          final dons = snapshot.data ?? [];
          final confirme = dons
              .where((c) => c.status == 'confirme')
              .fold<int>(0, (s, c) => s + c.amountFcfa);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total cotisé',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                                Text(
                                  formatMontant(confirme, state.devise),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                Text(
                                  pluriel(dons.length, 'cotisation'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SectionTitle(title: 'Historique'),
                        if (dons.isEmpty)
                          const EmptyState(
                            icon: Icons.account_balance_wallet_outlined,
                            message: 'Aucune cotisation pour le moment. Vos '
                                'cotisations apparaîtront ici dès le premier '
                                'paiement, avec leur reçu.',
                          )
                        else
                          Card(
                            child: Column(
                              children: dons
                                  .map((c) => ListTile(
                                        leading: const Icon(
                                          Icons.volunteer_activism_outlined,
                                        ),
                                        title: Text(
                                          '${Contribution.labelForType(c.type)} — ${formatMontant(c.amountFcfa, state.devise)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${formatDate(c.createdAt)} · ${c.statusLabel}',
                                        ),
                                        trailing: const Icon(
                                          Icons.receipt_long_outlined,
                                        ),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => ReceiptScreen(
                                                contributionId: c.id,
                                              ),
                                            ),
                                          );
                                        },
                                      ))
                                  .toList(),
                            ),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _payer,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Payer ma cotisation'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
