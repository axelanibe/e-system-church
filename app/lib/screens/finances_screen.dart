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
import 'finances_completes_screen.dart';
import 'finances_complement_screen.dart';
import 'finances_mere_screen.dart';
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
  /// Sous-onglet (maquette de refonte) : 0 Contributions,
  /// 1 Finances complètes.
  int _sousOnglet = 0;
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
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ContributionFormScreen()),
    );
    if (created != null && mounted) {
      showSuccess(
        context,
        created == 'depense'
            ? 'Dépense enregistrée (en attente).'
            : 'Contribution enregistrée (en attente).',
      );
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirme':
        return AppTheme.bleuNuit;
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _SousOnglets(
              index: _sousOnglet,
              onChange: (i) => setState(() {
                _sousOnglet = i;
                if (i == 0) _future = _load();
              }),
            ),
          ),
          Expanded(
            child: _sousOnglet == 1
                ? const ContenuFinancesCompletes()
                : FutureBuilder<ContributionPage>(
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
                    // Marge basse pour le bouton flottant « Contribution »,
                    // qui recouvrait sinon le badge de la dernière ligne.
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: [
                      // Filtres en tête de liste : sous les cartes, ils
                      // défilaient dans la bande du bouton flottant, qui
                      // recouvrait une pastille à chaque arrêt. En tête,
                      // ils ne descendent jamais dans cette bande.
                      _FiltresDefilants(
                        enfants: [
                          for (final entry in <String, String?>{
                            'Tous types': null,
                            'Dîmes': 'dime',
                            'Offrandes': 'offrande',
                            'Dons': 'don',
                            'Dépenses': 'depense',
                            'Cotisations': 'cotisation',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.key),
                              selected: _typeFilter == entry.value,
                              onSelected: (_) {
                                setState(() {
                                  _typeFilter = entry.value;
                                  _future = _load();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _FiltresDefilants(
                        enfants: [
                          for (final entry in <String, String?>{
                            'Tous statuts': null,
                            'En attente': 'en_attente',
                            'Confirmées': 'confirme',
                            'Annulées': 'annule',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.key),
                              selected: _statusFilter == entry.value,
                              onSelected: (_) {
                                setState(() {
                                  _statusFilter = entry.value;
                                  _future = _load();
                                });
                              },
                            ),
                        ],
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
                            childAspectRatio: 1.9,
                            children: [
                              for (final type in [
                                'dime',
                                'offrande',
                                'don',
                                'depense'
                              ])
                                StatCard(
                                  label: Contribution.labelForTypePluriel(
                                      type),
                                  value: formatFcfa(
                                      totaux[type]?.totalFcfa ?? 0),
                                  icon: type == 'depense'
                                      ? Icons.trending_down
                                      : Icons.trending_up,
                                  color: type == 'depense'
                                      ? AppTheme.rougeErreur
                                      : AppTheme.bleuNuit,
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                              Icons.account_balance_wallet_outlined),
                          title: const Text('Finances complètes'),
                          subtitle: const Text(
                              'Cotisations, banque, caisse, reçus, budgets.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              setState(() => _sousOnglet = 1),
                        ),
                      ),
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
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.account_balance_outlined),
                          title: const Text('Budget & caisse'),
                          subtitle: const Text(
                              'Postes budgétaires, budgets, dépenses et caisse.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const FinancesComplementScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      if (state.church?.isMere ?? false)
                        Card(
                          child: ListTile(
                            leading:
                                const Icon(Icons.account_tree_outlined),
                            title:
                                const Text('Finances de mon réseau'),
                            subtitle: const Text(
                                'Comparer les branches et voir le détail de chacune.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const FinancesMereScreen(),
                                ),
                              );
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
                      if (page.contributions.isEmpty)
                        EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          message: switch (_typeFilter) {
                            'depense' => 'Aucune dépense trouvée.',
                            'dime' => 'Aucune dîme trouvée.',
                            'offrande' => 'Aucune offrande trouvée.',
                            'don' => 'Aucun don trouvé.',
                            _ => 'Aucune contribution trouvée.',
                          },
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
      floatingActionButton: _sousOnglet == 0 && state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
    );
  }
}

/// Sous-onglets Contributions / Finances complètes (maquette de
/// refonte) : segment actif en carte blanche sur fond gris.
class _SousOnglets extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;

  const _SousOnglets({required this.index, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bordure.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: index == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: index == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    i == 0 ? 'Contributions' : 'Finances complètes',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight:
                          index == i ? FontWeight.bold : FontWeight.normal,
                      color: index == i
                          ? AppTheme.bleuNuit
                          : AppTheme.bleuNuit.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rangée de pastilles en défilement horizontal (maquette de refonte) :
/// fini l'empilement de boutons, les pastilles défilent.
class _FiltresDefilants extends StatelessWidget {
  final List<Widget> enfants;

  const _FiltresDefilants({required this.enfants});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < enfants.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            enfants[i],
          ],
        ],
      ),
    );
  }
}
