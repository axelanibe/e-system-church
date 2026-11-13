import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/enfants.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import 'checkin_enfants_screen.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 8 — Enfants et jeunesse : classes d'enfants, autorisations de
/// sortie et activités jeunesse.
class EnfantsScreen extends StatefulWidget {
  const EnfantsScreen({super.key});

  @override
  State<EnfantsScreen> createState() => _EnfantsScreenState();
}

class _EnfantsScreenState extends State<EnfantsScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<ClasseEnfant>> _classesFuture;
  late Future<List<AutorisationSortie>> _autorisationsFuture;
  late Future<List<ActiviteJeunesse>> _activitesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _classesFuture = api.getClassesEnfants();
    _autorisationsFuture = api.getAutorisationsSorties();
    _activitesFuture = api.getActivitesJeunesse();
    _membresFuture = api.getMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _classesFuture = api.getClassesEnfants();
      if (_tab == 1) _autorisationsFuture = api.getAutorisationsSorties();
      if (_tab == 2) _activitesFuture = api.getActivitesJeunesse();
    });
  }

  Future<void> _deleteClasse(ClasseEnfant classe) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la classe « ${classe.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteClasseEnfant(classe.id);
      if (mounted) showSuccess(context, 'Classe supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<List<Member>> _membres() async =>
      (await _membresFuture).membres;

  Future<void> _createClasse() async {
    final nomController = TextEditingController();
    final ageMinController = TextEditingController();
    final ageMaxController = TextEditingController();
    final salleController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle classe d’enfants',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la classe'),
        dialogTextField(
          controller: ageMinController,
          label: 'Âge minimum',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
          controller: ageMaxController,
          label: 'Âge maximum',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: salleController, label: 'Salle'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createClasseEnfant(
                nom: nomController.text.trim(),
                ageMin: int.tryParse(ageMinController.text.trim()),
                ageMax: int.tryParse(ageMaxController.text.trim()),
                salle: salleController.text.trim().isEmpty
                    ? null
                    : salleController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Classe créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createAutorisation(List<Member> membres) async {
    String? enfantId = membres.isEmpty ? null : membres.first.id;
    String? parentId;
    final activiteController = TextEditingController();
    final dateController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle autorisation de sortie',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: enfantId,
          label: 'Enfant',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => enfantId = v,
        ),
        dialogTextField(controller: activiteController, label: 'Activité'),
        dialogDateField(
            context: context, controller: dateController, label: 'Date de sortie'),
        dialogDropdown<String?>(
          value: parentId,
          label: 'Parent',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => parentId = v,
        ),
      ],
      isValid: () =>
          enfantId != null &&
          activiteController.text.trim().isNotEmpty &&
          dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createAutorisationSortie(
                enfantMemberId: enfantId!,
                activite: activiteController.text.trim(),
                dateSortie: dateController.text.trim(),
                parentMemberId: parentId,
              );
          if (mounted) showSuccess(context, 'Autorisation créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _setAutorisationStatut(
      AutorisationSortie autorisation, String statut) async {
    try {
      await context
          .read<AppState>()
          .api
          .setAutorisationStatut(autorisation.id, statut);
      if (mounted) showSuccess(context, 'Autorisation mise à jour.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _createActivite(List<Member> membres) async {
    final titreController = TextEditingController();
    final dateController = TextEditingController();
    final descriptionController = TextEditingController();
    final lieuController = TextEditingController();
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle activité jeunesse',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogDateField(
            context: context, controller: dateController, label: 'Date de l’activité'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogTextField(controller: lieuController, label: 'Lieu'),
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
      isValid: () =>
          titreController.text.trim().isNotEmpty &&
          dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createActiviteJeunesse(
                titre: titreController.text.trim(),
                dateActivite: dateController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                lieu: lieuController.text.trim().isEmpty
                    ? null
                    : lieuController.text.trim(),
                responsableMemberId: responsableId,
              );
          if (mounted) showSuccess(context, 'Activité créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _classesTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une classe',
        ),
        Expanded(
          child: FutureBuilder<List<ClasseEnfant>>(
            future: _classesFuture,
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
                  .where((c) => _matches(c.nom))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.child_care_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune classe d’enfants pour l’instant.'
                      : 'Aucune classe ne correspond à la recherche.',
                  actionLabel: 'Créer une classe',
                  onAction: _createClasse,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final c = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.child_care_outlined),
                      ),
                      title: Text(c.nom),
                      subtitle: Text(
                        '${c.ageMin != null || c.ageMax != null ? '${c.ageMin ?? '—'} – ${c.ageMax ?? '—'} ans' : 'Âges non précisés'}'
                        '${c.salle != null ? ' · Salle ${c.salle}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _deleteClasse(c),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _autorisationsTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une autorisation',
        ),
        Expanded(
          child: FutureBuilder<List<AutorisationSortie>>(
            future: _autorisationsFuture,
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
                  .where((a) =>
                      _matches(a.activite) ||
                      _matches(noms[a.enfantMemberId] ?? ''))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.exit_to_app_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune autorisation de sortie pour l’instant.'
                      : 'Aucune autorisation ne correspond à la recherche.',
                  actionLabel: 'Créer une autorisation',
                  onAction: () async {
                    try {
                      final membres = await _membres();
                      if (mounted) await _createAutorisation(membres);
                    } catch (e) {
                      if (context.mounted) showApiError(context, e);
                    }
                  },
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final a = items[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.exit_to_app_outlined),
                        ),
                        title: Text(
                            '${noms[a.enfantMemberId] ?? a.enfantMemberId} — ${a.activite}'),
                        subtitle: Text(
                          '${afficherDate(a.dateSortie)}'
                          '${a.parentMemberId != null ? ' · Parent : ${noms[a.parentMemberId] ?? '—'}' : ''}',
                        ),
                        trailing: a.statut == 'en_attente'
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check,
                                        color: AppTheme.bleuNuit),
                                    tooltip: 'Autoriser',
                                    onPressed: () => _setAutorisationStatut(
                                        a, 'autorisee'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: AppTheme.rougeErreur),
                                    tooltip: 'Refuser',
                                    onPressed: () => _setAutorisationStatut(
                                        a, 'refusee'),
                                  ),
                                ],
                              )
                            : StatusChip(
                                label: a.statut == 'autorisee'
                                    ? 'Autorisée'
                                    : a.statut == 'refusee'
                                        ? 'Refusée'
                                        : a.statut,
                                color: a.statut == 'autorisee'
                                    ? AppTheme.bleuNuit
                                    : a.statut == 'refusee'
                                        ? AppTheme.rougeErreur
                                        : Colors.orange,
                              ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _activitesTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une activité',
        ),
        Expanded(
          child: FutureBuilder<List<ActiviteJeunesse>>(
            future: _activitesFuture,
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
                  .where((a) => _matches(a.titre))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.sports_soccer_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune activité jeunesse pour l’instant.'
                      : 'Aucune activité ne correspond à la recherche.',
                  actionLabel: 'Créer une activité',
                  onAction: () async {
                    try {
                      final membres = await _membres();
                      if (mounted) await _createActivite(membres);
                    } catch (e) {
                      if (context.mounted) showApiError(context, e);
                    }
                  },
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final a = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.groups_outlined),
                      ),
                      title: Text(a.titre),
                      subtitle: Text(
                        '${afficherDate(a.dateActivite)}'
                        '${a.lieu != null ? ' · ${a.lieu}' : ''}'
                        '${a.responsableMemberId != null ? ' · ${noms[a.responsableMemberId] ?? '—'}' : ''}'
                        '${a.description != null ? ' · ${a.description}' : ''}',
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Enfants & jeunesse'),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CheckinEnfantsScreen(),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Check-in enfants (double QR)',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Classes'),
              Tab(text: 'Autorisations'),
              Tab(text: 'Jeunesse'),
            ],
          ),
        ),
        body: FutureBuilder<MemberPage>(
          future: _membresFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {
                  _membresFuture =
                      context.read<AppState>().api.getMembers();
                }),
              );
            }
            final noms = {
              for (final m in snapshot.data!.membres) m.id: m.fullName
            };
            return TabBarView(
              children: [
                _classesTab(),
                _autorisationsTab(noms),
                _activitesTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                await _createClasse();
              } else {
                final membres = await _membres();
                if (!mounted) return;
                if (_tab == 1) {
                  await _createAutorisation(membres);
                } else {
                  await _createActivite(membres);
                }
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0
              ? 'Nouvelle classe'
              : _tab == 1
                  ? 'Nouvelle autorisation'
                  : 'Nouvelle activité'),
        ),
      ),
    );
  }
}
