import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/campagne.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Campagnes de collecte, US2 : objectif, période, progression.
/// Le total collecté ne compte que les contributions confirmées affectées.
/// Au-delà de 100 % de l'objectif, l'écran l'indique explicitement
/// (« Objectif dépassé »), le pourcentage n'est jamais plafonné ni masqué.
/// Si aucune campagne n'existe, l'écran affiche « Aucune campagne pour
/// l'instant ». Un membre simple ne voit ici que les campagnes dont l'église
/// a choisi de montrer le total (le serveur filtre le reste).
class CampagnesScreen extends StatefulWidget {
  const CampagnesScreen({super.key});

  @override
  State<CampagnesScreen> createState() => _CampagnesScreenState();
}

class _CampagnesScreenState extends State<CampagnesScreen> {
  late Future<List<Campagne>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Campagne>> _load() =>
      context.read<AppState>().api.getCampagnes();

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _create() async {
    final nomController = TextEditingController();
    final objectifController = TextEditingController();
    final debutController = TextEditingController();
    final finController = TextEditingController();
    var statutActive = false;
    var visibleMembres = false;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle campagne',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom *'),
        dialogTextField(
          controller: objectifController,
          label: 'Objectif en FCFA *',
          keyboardType: TextInputType.number,
        ),
        dialogDateField(
            context: context, controller: debutController, label: 'Début *'),
        dialogDateField(
            context: context, controller: finController, label: 'Fin *'),
        StatefulBuilder(
          builder: (context, setDialogState) => Column(
            children: [
              SwitchListTile(
                title: const Text('Campagne active'),
                subtitle: const Text(
                    'Une campagne active peut recevoir des contributions.'),
                value: statutActive,
                onChanged: (v) => setDialogState(() => statutActive = v),
              ),
              SwitchListTile(
                title: const Text('Les membres voient le total'),
                subtitle: const Text(
                    'Sinon, seuls les responsables voient cette campagne.'),
                value: visibleMembres,
                onChanged: (v) => setDialogState(() => visibleMembres = v),
              ),
            ],
          ),
        ),
      ],
      isValid: () {
        final objectif = int.tryParse(objectifController.text.trim());
        return nomController.text.trim().length >= 2 &&
            objectif != null &&
            objectif > 0 &&
            debutController.text.isNotEmpty &&
            finController.text.isNotEmpty &&
            finController.text.compareTo(debutController.text) > 0;
      },
      onSave: () async {
        try {
          await context.read<AppState>().api.createCampagne(
                nom: nomController.text.trim(),
                objectifFcfa: int.parse(objectifController.text.trim()),
                dateDebut: debutController.text.trim(),
                dateFin: finController.text.trim(),
                statut: statutActive ? 'active' : 'brouillon',
                visibleMembres: visibleMembres,
              );
          if (mounted) showSuccess(context, 'Campagne créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _activer(Campagne c) async {
    try {
      await context.read<AppState>().api.setCampagneStatut(c.id, 'active');
      if (mounted) showSuccess(context, 'Campagne activée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _cloturer(Campagne c) async {
    final confirmed = await confirmDelete(
      context,
      'Clôturer la campagne « ${c.nom} » ? Aucune nouvelle contribution '
      'ne pourra plus lui être affectée. Les contributions déjà '
      'enregistrées ne changent pas.',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.cloturerCampagne(c.id);
      if (mounted) showSuccess(context, 'Campagne clôturée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Color _statutColor(String statut) {
    switch (statut) {
      case 'active':
        return AppTheme.cypress;
      case 'cloturee':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: FutureBuilder<List<Campagne>>(
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
          final campagnes = snapshot.data!;
          if (campagnes.isEmpty) {
            return const EmptyState(
              icon: Icons.volunteer_activism_outlined,
              message: 'Aucune campagne pour l’instant.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final c in campagnes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.nom,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              StatusChip(
                                label: c.statutLabel,
                                color: _statutColor(c.statut),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatDate(c.dateDebut)} — ${formatDate(c.dateFin)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: (c.pourcentage / 100).clamp(0.0, 1.0),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            c.depasse
                                ? 'Objectif dépassé : ${formatFcfa(c.totalCollecte)} collectés sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).'
                                : '${formatFcfa(c.totalCollecte)} collectés sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).',
                            style: TextStyle(
                              fontWeight:
                                  c.depasse ? FontWeight.bold : FontWeight.normal,
                              color: c.depasse
                                  ? AppTheme.cypress
                                  : null,
                            ),
                          ),
                          Text(
                            '${c.nombreContributions} contribution(s) confirmée(s).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (state.canManageFinances &&
                              c.statut != 'cloturee')
                            Row(
                              children: [
                                if (c.statut == 'brouillon')
                                  TextButton.icon(
                                    onPressed: () => _activer(c),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Activer'),
                                  ),
                                TextButton.icon(
                                  onPressed: () => _cloturer(c),
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Clôturer'),
                                ),
                              ],
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
      floatingActionButton: state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Campagne'),
            )
          : null,
    );
  }
}
