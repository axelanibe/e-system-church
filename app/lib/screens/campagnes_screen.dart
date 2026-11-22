import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/campagne.dart';
import '../models/finances.dart';
import '../models/membres_complement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/dialog_helpers.dart';

/// Campagne et budget (maquette, écran 28) : 2 onglets, Campagne et
/// Budget, réutilisant les formulaires existants.
///
/// Campagne : objectif, période, progression. Le total collecté ne
/// compte que les contributions confirmées affectées. Au-delà de
/// 100 % de l'objectif, l'écran l'indique explicitement (« Objectif
/// dépassé »), le pourcentage n'est jamais plafonné ni masqué. Les
/// interrupteurs « Campagne active » et « Les membres voient le total »
/// sont retirés : une campagne se crée en brouillon, puis s'active
/// depuis sa carte. Un membre simple ne voit ici que les campagnes
/// dont l'église a choisi de montrer le total (le serveur filtre le
/// reste).
///
/// Budget : département, poste du plan comptable, enveloppe mensuelle.
/// Une alerte s'affiche quand un poste dépasse son enveloppe (calcul
/// côté application, sur les chiffres déjà présents : prévu contre
/// réel du mois en cours).
class CampagnesScreen extends StatefulWidget {
  /// Onglet ouvert au départ : 0 Campagne, 1 Budget.
  final int initialTab;

  const CampagnesScreen({super.key, this.initialTab = 0});

  @override
  State<CampagnesScreen> createState() => _CampagnesScreenState();
}

class _CampagnesScreenState extends State<CampagnesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<Campagne>> _future;
  // Doublon (21 nov. 2026) : la pastille « Nouvelle campagne » ne
  // s'affiche que si la liste n'est pas vide — sinon le bouton de
  // l'état vide est le seul point d'entrée. Motif repris de
  // activites_screen.dart (`_listeVide ? null`).
  bool _campagnesVides = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                statut: 'brouillon',
                visibleMembres: false,
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

  /// Détail d'une campagne (aucun écran de détail n'existe : dialogue).
  Future<void> _afficherDetail(Campagne c) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.nom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.statutLabel),
            const SizedBox(height: 4),
            Text(
              '${formatDateSeule(c.dateDebut)} — ${formatDateSeule(c.dateFin)}',
            ),
            const SizedBox(height: 4),
            Text(formatFcfa(c.objectifFcfa)),
            Text(
              '${formatFcfa(c.totalCollecte)} (${c.pourcentage} %)',
            ),
            Text('${pluriel(c.nombreContributions, 'contribution confirmée', 'contributions confirmées')}.'),
          ],
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

  Color _statutColor(String statut) {
    switch (statut) {
      case 'active':
        return AppTheme.violetProfond;
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
      appBar: AppBar(
        title: const Text('Campagne et budget'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(child: Text('Campagne', style: TextStyle(fontSize: 12.5))),
            Tab(child: Text('Budget', style: TextStyle(fontSize: 12.5))),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CampagneTab(
            future: _future,
            onRefresh: _refresh,
            onActiver: _activer,
            onCloturer: _cloturer,
            onDetail: _afficherDetail,
            onCreate: _create,
            statutColor: _statutColor,
            canManageFinances: state.canManageFinances,
            campagnesVides: _campagnesVides,
            onVideChanged: (vide) {
              if (vide != _campagnesVides) {
                setState(() => _campagnesVides = vide);
              }
            },
          ),
          const _BudgetTab(),
        ],
      ),
      floatingActionButton:
          _tabController.index == 0 &&
                  state.canManageFinances &&
                  !_campagnesVides
              ? FloatingActionButton.extended(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle campagne', style: TextStyle(fontSize: 13.5)),
                )
              : null,
    );
  }
}

class _CampagneTab extends StatelessWidget {
  final Future<List<Campagne>> future;
  final VoidCallback onRefresh;
  final void Function(Campagne) onActiver;
  final void Function(Campagne) onCloturer;
  final void Function(Campagne) onDetail;
  final VoidCallback onCreate;
  final Color Function(String) statutColor;
  final bool canManageFinances;
  final bool campagnesVides;
  final ValueChanged<bool> onVideChanged;

  const _CampagneTab({
    required this.future,
    required this.onRefresh,
    required this.onActiver,
    required this.onCloturer,
    required this.onDetail,
    required this.onCreate,
    required this.statutColor,
    required this.canManageFinances,
    required this.campagnesVides,
    required this.onVideChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Campagne>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: onRefresh,
          );
        }
        final campagnes = snapshot.data!;
        // Doublon (21 nov. 2026) : signale au parent que la liste est
        // vide pour masquer la pastille. Motif repris de
        // activites_screen.dart (mise à jour hors build).
        if (campagnes.isEmpty != campagnesVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onVideChanged(campagnes.isEmpty);
          });
        }
        if (campagnes.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Créer une campagne de collecte ou un budget.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              Expanded(
                child: EmptyState(
                  icon: Icons.campaign_outlined,
                  message: 'Aucune campagne — 0 FCFA collecté.',
                  actionLabel:
                      canManageFinances ? 'Nouvelle campagne' : null,
                  onAction: canManageFinances ? onCreate : null,
                ),
              ),
            ],
          );
        }
        return ListeAvecFab(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Créer une campagne de collecte ou un budget.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                for (final c in campagnes)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onDetail(c),
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
                                        .titleMedium?.copyWith(fontSize: 13.5),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                StatusChip(
                                  label: c.statutLabel,
                                  color: statutColor(c.statut),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatDateSeule(c.dateDebut)} — ${formatDateSeule(c.dateFin)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
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
                                    ? AppTheme.violetProfond
                                    : null,
                              ),
                            ),
                            Text(
                              pluriel(c.nombreContributions,
                                  'contribution confirmée',
                                  'contributions confirmées'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                            ),
                            if (canManageFinances &&
                                c.statut != 'cloturee')
                              Row(
                                children: [
                                  if (c.statut == 'brouillon')
                                    TextButton.icon(
                                      onPressed: () => onActiver(c),
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('Activer'),
                                    ),
                                  TextButton.icon(
                                    onPressed: () => onCloturer(c),
                                    icon: const Icon(Icons.lock_outline),
                                    label: const Text('Clôturer'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Onglet Budget de l'écran 28 : département, poste du plan
/// comptable, enveloppe mensuelle (mois en cours). Sans département,
/// l'enveloppe est celle du poste ; avec département, celle du
/// département. L'alerte de dépassement est calculée côté application
/// (réel contre prévu du mois en cours, postes et départements).
class _BudgetTab extends StatefulWidget {
  const _BudgetTab();

  @override
  State<_BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends State<_BudgetTab> {
  late Future<_DonneesBudget> _future;
  String? _departementId;
  String? _posteId;
  final _enveloppeController = TextEditingController();
  bool _saving = false;

  int get _annee => DateTime.now().year;
  int get _mois => DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _enveloppeController.dispose();
    super.dispose();
  }

  Future<_DonneesBudget> _load() async {
    final api = context.read<AppState>().api;
    final results = await Future.wait([
      api.getPostesBudgetaires(),
      api.getDepartements(),
      api.getBudgetsMensuels(annee: _annee, mois: _mois),
      api.getBudgetsDepartements(annee: _annee, mois: _mois),
      api.getSuiviMensuel(annee: _annee, mois: _mois),
      api.getSuiviDepartements(annee: _annee, mois: _mois),
    ]);
    return _DonneesBudget(
      postes: results[0] as List<PosteBudgetaire>,
      departements: results[1] as List<Departement>,
      budgetsMensuels: results[2] as List<BudgetMensuel>,
      budgetsDepartements: results[3] as List<BudgetDepartement>,
      suivi: results[4] as SuiviMensuel,
      suiviDepartements: results[5] as SuiviDepartements,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _creer() async {
    final enveloppe = int.tryParse(_enveloppeController.text.trim());
    if (_posteId == null && _departementId == null) {
      showApiError(context, 'Choisissez un poste ou un département.');
      return;
    }
    if (enveloppe == null || enveloppe <= 0) {
      showApiError(context, 'Enveloppe mensuelle invalide.');
      return;
    }
    setState(() => _saving = true);
    try {
      final api = context.read<AppState>().api;
      if (_departementId != null) {
        await api.creerBudgetDepartement(
          departementId: _departementId!,
          annee: _annee,
          mois: _mois,
          montantPrevu: enveloppe,
        );
      } else {
        await api.creerBudgetMensuel(
          posteId: _posteId!,
          annee: _annee,
          mois: _mois,
          montantPrevu: enveloppe,
        );
      }
      if (mounted) {
        showSuccess(context, 'Budget créé.');
        _enveloppeController.clear();
        _refresh();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _supprimerMensuel(BudgetMensuel b, String? nom) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le budget mensuel ${nom ?? '—'} ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.supprimerBudgetMensuel(b.id);
      if (mounted) showSuccess(context, 'Budget mensuel supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerDepartement(
      BudgetDepartement b, String? nom) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le budget mensuel du département ${nom ?? '—'} ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.supprimerBudgetDepartement(b.id);
      if (mounted) showSuccess(context, 'Budget supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<_DonneesBudget>(
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
        final d = snapshot.data!;
        // Alertes de dépassement, calculées côté application : réel
        // supérieur au prévu, pour un poste ou un département du mois.
        final depassements = <String>[
          for (final ligne in d.suivi.parPostes)
            if (ligne.budgetDefini && ligne.reelFcfa > ligne.prevuFcfa)
              '${ligne.libelle} : ${formatMontant(ligne.reelFcfa, state.devise)} dépensés sur ${formatMontant(ligne.prevuFcfa, state.devise)} prévus',
          for (final ligne in d.suiviDepartements.parDepartements)
            if (ligne.depasse)
              '${ligne.departement} : ${formatMontant(ligne.reelFcfa, state.devise)} dépensés sur ${formatMontant(ligne.prevuFcfa, state.devise)} prévus',
        ];
        String? nomPoste(String id) =>
            d.postes.where((p) => p.id == id).firstOrNull?.nom;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Créer une campagne de collecte ou un budget.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (depassements.isNotEmpty)
                Card(
                  color: AppTheme.rougeErreur.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Alerte : enveloppe dépassée',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.rougeErreur,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final depassement in depassements)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(depassement),
                          ),
                      ],
                    ),
                  ),
                ),
              if (depassements.isNotEmpty) const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _departementId,
                decoration: const InputDecoration(
                  labelText: 'Département',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Aucun pour l’instant')),
                  for (final dep in d.departements)
                    DropdownMenuItem(value: dep.id, child: Text(dep.nom)),
                ],
                onChanged: (v) => setState(() => _departementId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _posteId,
                decoration: const InputDecoration(
                  labelText: 'Poste *',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Choisir dans le plan comptable'),
                items: [
                  for (final p in d.postes)
                    DropdownMenuItem(value: p.id, child: Text(p.nom)),
                ],
                onChanged: (v) => setState(() => _posteId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _enveloppeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Enveloppe mensuelle (${state.devise}) *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le réalisé se suit dans Finances ; une alerte part quand un poste dépasse son enveloppe.',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _creer,
                child: const Text('Créer le budget', style: TextStyle(fontSize: 13.5)),
              ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Budgets du mois'),
              if (d.budgetsMensuels.isEmpty &&
                  d.budgetsDepartements.isEmpty)
                const EmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'Aucun budget défini.',
                )
              else ...[
                for (final b in d.budgetsMensuels)
                  ListTile(
                    leading: const Icon(Icons.pie_chart_outline),
                    title: Text(nomPoste(b.posteId) ?? 'Poste inconnu', style: const TextStyle(fontSize: 13.5)),
                    subtitle: const Text('Enveloppe mensuelle', style: TextStyle(fontSize: 11.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMontant(b.montantPrevu, state.devise),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              _supprimerMensuel(b, nomPoste(b.posteId)),
                        ),
                      ],
                    ),
                  ),
                for (final b in d.budgetsDepartements)
                  ListTile(
                    leading: const Icon(Icons.pie_chart_outline),
                    title: Text(b.departementNom ?? 'Département inconnu', style: const TextStyle(fontSize: 13.5)),
                    subtitle: const Text('Enveloppe mensuelle', style: TextStyle(fontSize: 11.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMontant(b.montantPrevu, state.devise),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () => _supprimerDepartement(
                              b, b.departementNom),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DonneesBudget {
  final List<PosteBudgetaire> postes;
  final List<Departement> departements;
  final List<BudgetMensuel> budgetsMensuels;
  final List<BudgetDepartement> budgetsDepartements;
  final SuiviMensuel suivi;
  final SuiviDepartements suiviDepartements;

  const _DonneesBudget({
    required this.postes,
    required this.departements,
    required this.budgetsMensuels,
    required this.budgetsDepartements,
    required this.suivi,
    required this.suiviDepartements,
  });
}
