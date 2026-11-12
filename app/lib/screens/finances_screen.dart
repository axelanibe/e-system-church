import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'campagnes_screen.dart';
import 'contribution_form_screen.dart';
import 'attestations_screen.dart';
import 'receipt_screen.dart';

/// Finances de mon église : totaux par type, liste avec filtres, ajout
/// d'une contribution, reçu avec confirmation / annulation.
/// Le rôle « membre » simple n'a pas accès à cet écran.
class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  String? _typeFilter;
  String? _statusFilter;
  late Future<ContributionPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ContributionPage> _load() {
    return context.read<AppState>().api.getContributions(
          type: _typeFilter,
          status: _statusFilter,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _openForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ContributionFormScreen()),
    );
    if (created == true && mounted) {
      showSuccess(context, 'Contribution enregistrée (en attente).');
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirme':
        return AppTheme.cypress;
      case 'en_attente':
        return Colors.orange;
      case 'annule':
        return AppTheme.rougeErreur;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.canReadFinances) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message:
            'Votre rôle ne donne pas accès aux finances de l’église.',
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in <String, String?>{
                    'Tous types': null,
                    'Dîmes': 'dime',
                    'Offrandes': 'offrande',
                    'Dons': 'don',
                    'Dépenses': 'depense',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.key),
                        selected: _typeFilter == entry.value,
                        onSelected: (_) {
                          setState(() {
                            _typeFilter = entry.value;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  const SizedBox(width: 8),
                  for (final entry in <String, String?>{
                    'Tous statuts': null,
                    'En attente': 'en_attente',
                    'Confirmées': 'confirme',
                    'Annulées': 'annule',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.key),
                        selected: _statusFilter == entry.value,
                        onSelected: (_) {
                          setState(() {
                            _statusFilter = entry.value;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<ContributionPage>(
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
                final page = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.volunteer_activism_outlined),
                          title: const Text('Campagnes de collecte'),
                          subtitle: const Text(
                              'Objectif, période et progression des collectes.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CampagnesScreen(),
                              ),
                            );
                            _refresh();
                          },
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AttestationsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Attestations annuelles'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth > 600 ? 4 : 2;
                          final totaux = page.totaux;
                          return GridView.count(
                            crossAxisCount: crossAxisCount,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.6,
                            children: [
                              for (final type in [
                                'dime',
                                'offrande',
                                'don',
                                'depense'
                              ])
                                StatCard(
                                  label:
                                      '${Contribution.labelForType(type)} confirmées',
                                  value: formatFcfa(
                                      totaux[type]?.totalFcfa ?? 0),
                                  icon: type == 'depense'
                                      ? Icons.trending_down
                                      : Icons.trending_up,
                                  color: type == 'depense'
                                      ? AppTheme.rougeErreur
                                      : AppTheme.cypress,
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (page.contributions.isEmpty)
                        const EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          message: 'Aucune contribution trouvée.',
                        )
                      else
                        ...page.contributions.map(
                          (c) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  c.type == 'depense'
                                      ? Icons.remove
                                      : Icons.add,
                                ),
                              ),
                              title: Text(
                                  '${c.typeLabel} — ${formatFcfa(c.amountFcfa)}'),
                              subtitle: Text(
                                  '${c.paymentLabel}${c.membreNom != null ? ' · ${c.membreNom}' : ''} · ${formatDate(c.createdAt)}'),
                              trailing: StatusChip(
                                label: c.statusLabel,
                                color: _statusColor(c.status),
                              ),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ReceiptScreen(contributionId: c.id),
                                  ),
                                );
                                _refresh();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Contribution'),
            )
          : null,
    );
  }
}
