import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';

/// Budgets par département (tranche T7) : prévu contre réel, par mois,
/// avec alerte quand le réel dépasse un budget défini. Le budget se
/// crée par département, avec son enveloppe en FCFA. Le réalisé vient
/// des dépenses portées par le département (hors refusées). Saisie
/// admin et trésorier.
class BudgetsDepartementsScreen extends StatefulWidget {
  const BudgetsDepartementsScreen({super.key});

  @override
  State<BudgetsDepartementsScreen> createState() =>
      _BudgetsDepartementsScreenState();
}

class _BudgetsDepartementsScreenState
    extends State<BudgetsDepartementsScreen> {
  late Future<SuiviDepartements> _future;
  int _annee = DateTime.now().year;
  int _mois = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<SuiviDepartements> _charger() => context
      .read<AppState>()
      .api
      .getSuiviDepartements(annee: _annee, mois: _mois);

  void _refresh() => setState(() => _future = _charger());

  void _moisPrecedent() {
    setState(() {
      if (_mois == 1) {
        _mois = 12;
        _annee -= 1;
      } else {
        _mois -= 1;
      }
      _future = _charger();
    });
  }

  void _moisSuivant() {
    setState(() {
      if (_mois == 12) {
        _mois = 1;
        _annee += 1;
      } else {
        _mois += 1;
      }
      _future = _charger();
    });
  }

  Future<void> _definirBudget(LigneSuiviDepartement ligne) async {
    final montantController = TextEditingController(
        text: ligne.budgetDefini ? '${ligne.prevuFcfa}' : '');
    final formKey = GlobalKey<FormState>();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Budget · ${ligne.departement}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: montantController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Enveloppe (FCFA) *',
              hintText: 'Ex. 60000',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final montant = int.tryParse(v?.trim() ?? '');
              if (montant == null || montant < 0) {
                return 'Montant invalide.';
              }
              return null;
            },
          ),
        ),
        actions: [
          if (ligne.budgetDefini)
            TextButton(
              onPressed: () => Navigator.of(context).pop('supprimer'),
              child: const Text('Supprimer le budget'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await context.read<AppState>().api.creerBudgetDepartement(
                      departementId: ligne.departementId,
                      annee: _annee,
                      mois: _mois,
                      montantPrevu:
                          int.parse(montantController.text.trim()),
                    );
                if (context.mounted) Navigator.of(context).pop('ok');
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    montantController.dispose();
    if (action == 'supprimer' && mounted) {
      final api = context.read<AppState>().api;
      try {
        final budgets = await api.getBudgetsDepartements(
            annee: _annee,
            mois: _mois,
            departementId: ligne.departementId);
        if (budgets.isNotEmpty) {
          await api.supprimerBudgetDepartement(budgets.first.id);
        }
        if (mounted) {
          _refresh();
          showSuccess(context, 'Budget supprimé.');
        }
      } catch (e) {
        if (mounted) showApiError(context, e);
      }
    } else if (action == 'ok' && mounted) {
      _refresh();
      showSuccess(context, 'Budget enregistré.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message: 'Votre rôle ne donne pas accès aux finances de l’église.',
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets par département')),
      body: FutureBuilder<SuiviDepartements>(
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
          final suivi = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _moisPrecedent,
                      tooltip: 'Mois précédent',
                    ),
                    Text(
                      libellePeriodeMois(
                          '${suivi.annee}-${suivi.mois.toString().padLeft(2, '0')}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _moisSuivant,
                      tooltip: 'Mois suivant',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        constraints.maxWidth > 600 ? 3 : 2;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          label: 'Total prévu',
                          value: formatMontant(
                              suivi.totalPrevuFcfa, state.devise),
                          icon: Icons.calendar_month_outlined,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Total réel',
                          value: formatMontant(
                              suivi.totalReelFcfa, state.devise),
                          icon: Icons.trending_down,
                          color: AppTheme.rougeErreur,
                        ),
                      ],
                    );
                  },
                ),
                if (suivi.sansDepartement.reelFcfa > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dépenses sans département : ${formatMontant(suivi.sansDepartement.reelFcfa, state.devise)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                const SectionTitle(title: 'Par département'),
                if (suivi.parDepartements.isEmpty)
                  const EmptyState(
                    icon: Icons.calendar_month_outlined,
                    message: 'Aucun département pour le moment. Les '
                        'budgets se créent par département, avec leur '
                        'enveloppe en FCFA.',
                  )
                else
                  ...suivi.parDepartements.map(
                    (ligne) => Card(
                      child: ListTile(
                        leading: const Icon(
                            Icons.calendar_month_outlined),
                        title: Text(ligne.departement),
                        subtitle: Text(
                          'Prévu : ${formatMontant(ligne.prevuFcfa, state.devise)}'
                          ' · Réel : ${formatMontant(ligne.reelFcfa, state.devise)}'
                          ' · Écart : ${formatMontant(ligne.ecartFcfa, state.devise)}',
                        ),
                        trailing: ligne.depasse
                            ? const StatusChip(
                                label: 'Dépassement',
                                color: AppTheme.rougeErreur,
                              )
                            : ligne.budgetDefini
                                ? const StatusChip(
                                    label: 'Dans le budget',
                                    color: AppTheme.bleuNuit,
                                  )
                                : const StatusChip(
                                    label: 'Sans budget',
                                    color: Colors.grey,
                                  ),
                        onTap: state.canManageFinances
                            ? () => _definirBudget(ligne)
                            : null,
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
