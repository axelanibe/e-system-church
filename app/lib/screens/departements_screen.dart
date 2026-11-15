import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'budgets_departements_screen.dart';
import 'enfants_screen.dart';

/// Départements de l'église, en 3 onglets (maquette) : Départements,
/// Budgets, Enfants & jeunesse. La gestion (créer, renommer,
/// supprimer) reste dans le 1er onglet. Anciennement section des
/// Réglages, déplacé ici dans l'onglet Départements (tranche 3,
/// E-D1) : la section des Réglages était un doublon. Le titre
/// « Départements », le logo ESC et le bouton de menu sont déjà dans
/// l'en-tête clair de la coque (HomeScreen), on ne les duplique pas
/// ici : pas d'AppBar propre.
class DepartementsScreen extends StatefulWidget {
  const DepartementsScreen({super.key});

  @override
  State<DepartementsScreen> createState() => _DepartementsScreenState();
}

class _DepartementsScreenState extends State<DepartementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;
  final _rechercheController = TextEditingController();
  String _query = '';

  late Future<List<Departement>> _departementsFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      final i = _tabController.index;
      if (i != _tabIndex) setState(() => _tabIndex = i);
    });
    final api = context.read<AppState>().api;
    _departementsFuture = api.getDepartements();
    _membresFuture = api.getMembers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _departementsFuture = api.getDepartements();
      _membresFuture = api.getMembers();
    });
  }

  bool _matches(String text, String query) =>
      query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  /// Gestion des départements : créer, renommer, supprimer. Les
  /// départements restent aussi le filtre et le sélecteur en contexte
  /// (liste des membres, formulaire membre).
  Future<void> _createDepartement(List<Member> membres) async {
    final nomController = TextEditingController();
    final descriptionController = TextEditingController();
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau département',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du département'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogDropdown<String?>(
          value: responsableId,
          label: 'Responsable',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => responsableId = v,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createDepartement(
                nom: nomController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                responsableMemberId: responsableId,
              );
          if (mounted) showSuccess(context, 'Département créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Renomme un département (les membres rattachés gardent leur département,
  /// seul le libellé change).
  Future<void> _renameDepartement(Departement departement) async {
    final nomController = TextEditingController(text: departement.nom);
    await showCreateDialog(
      context: context,
      title: 'Renommer le département',
      saveLabel: 'Enregistrer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du département'),
      ],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        try {
          await context.read<AppState>().api.updateDepartement(
                departement.id,
                nom: nomController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Département renommé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteDepartement(Departement departement) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le département « ${departement.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteDepartement(departement.id);
      if (mounted) showSuccess(context, 'Département supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// 1er onglet : la liste des départements, recherche et gestion.
  Widget _departementsTab() {
    return Column(
      children: [
        searchField(
          controller: _rechercheController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un département',
        ),
        Expanded(
          child: FutureBuilder<MemberPage>(
            future: _membresFuture,
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
              final membres = snapshot.data!.membres;
              final noms = {for (final m in membres) m.id: m.fullName};
              return FutureBuilder<List<Departement>>(
                future: _departementsFuture,
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
                  final items = snapshot.data!
                      .where((d) => _matches(d.nom, _query))
                      .toList();
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.group_work_outlined,
                      message: snapshot.data!.isEmpty
                          ? 'Aucun département.'
                          : 'Aucun département ne correspond à la recherche.',
                      actionLabel: 'Créer un département',
                      onAction: () => _createDepartement(membres),
                    );
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final d = items[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.group_work_outlined),
                        ),
                        title: Text(d.nom),
                        subtitle: Text(
                          '${d.responsableMemberId != null ? 'Responsable : ${noms[d.responsableMemberId] ?? '—'}' : 'Sans responsable'}'
                          '${d.description != null ? ' · ${d.description}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Renommer',
                              onPressed: () => _renameDepartement(d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Supprimer',
                              onPressed: () => _deleteDepartement(d),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Bandeau violet (même style que MembresScreen) : 3 onglets,
          // indicateur or, défilant sur téléphone étroit.
          Container(
            color: AppTheme.violetProfond,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.or,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Départements'),
                Tab(text: 'Budgets'),
                Tab(text: 'Enfants & jeunesse'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _departementsTab(),
                // 2e onglet : « Budgets par département », sorti de
                // Finances complètes (maquette, un seul accès aux
                // budgets : « Budget & caisse » depuis Finances).
                const BudgetsDepartementsScreen(sansAppBar: true),
                // 3e onglet : « Enfants & jeunesse », déplacé de
                // Familles (maquette).
                const EnfantsScreen(sansAppBar: true),
              ],
            ),
          ),
        ],
      ),
      // Le FAB « Département » ne s'affiche que sur le 1er onglet :
      // l'onglet Enfants & jeunesse apporte son propre FAB.
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                try {
                  final membres = (await _membresFuture).membres;
                  if (!mounted) return;
                  await _createDepartement(membres);
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Département'),
            )
          : null,
    );
  }
}
