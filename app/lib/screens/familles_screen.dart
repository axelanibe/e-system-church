import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'member_detail_screen.dart';

/// Module 1 — Familles, départements et cellules de l'église.
/// La fiche complète d'un membre (statuts, baptême, liens) s'ouvre depuis
/// la section dédiée en bas de l'onglet Familles.
class FamillesScreen extends StatefulWidget {
  /// Onglet ouvert au départ (0 Familles, 1 Départements,
  /// 2 Cellules, 3 Fonctions, 4 Postes). La barre du bas ouvre
  /// l'onglet Départements directement.
  final int ongletInitial;

  const FamillesScreen({super.key, this.ongletInitial = 0});

  @override
  State<FamillesScreen> createState() => _FamillesScreenState();
}

class _FamillesScreenState extends State<FamillesScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<Famille>> _famillesFuture;
  late Future<List<Departement>> _departementsFuture;
  late Future<List<Cellule>> _cellulesFuture;
  late Future<List<Fonction>> _fonctionsFuture;
  late Future<List<Poste>> _postesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletInitial;
    _refreshAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    final api = context.read<AppState>().api;
    setState(() {
      _famillesFuture = api.getFamilles();
      _departementsFuture = api.getDepartements();
      _cellulesFuture = api.getCellules();
      _fonctionsFuture = api.getFonctions();
      _postesFuture = api.getPostes();
      _membresFuture = api.getMembers();
    });
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _famillesFuture = api.getFamilles();
      if (_tab == 1) _departementsFuture = api.getDepartements();
      if (_tab == 2) _cellulesFuture = api.getCellules();
      if (_tab == 3) _fonctionsFuture = api.getFonctions();
      if (_tab == 4) _postesFuture = api.getPostes();
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<void> _createFamille(List<Member> membres) async {
    final nomController = TextEditingController();
    final adresseController = TextEditingController();
    final telephoneController = TextEditingController();
    String? chefId;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle famille',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la famille'),
        dialogDropdown<String?>(
          value: chefId,
          label: 'Chef de famille',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => chefId = v,
        ),
        dialogTextField(controller: adresseController, label: 'Adresse'),
        dialogTextField(
          controller: telephoneController,
          label: 'Téléphone',
          keyboardType: TextInputType.phone,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createFamille(
                nom: nomController.text.trim(),
                chefFamilleId: chefId,
                adresse: adresseController.text.trim().isEmpty
                    ? null
                    : adresseController.text.trim(),
                telephone: telephoneController.text.trim().isEmpty
                    ? null
                    : telephoneController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Famille créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

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

  Future<void> _createCellule(List<Member> membres) async {
    final nomController = TextEditingController();
    final quartierController = TextEditingController();
    final jourController = TextEditingController();
    final heureController = TextEditingController();
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle cellule',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la cellule'),
        dialogTextField(controller: quartierController, label: 'Quartier'),
        dialogDropdown<String?>(
          value: responsableId,
          label: 'Responsable',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => responsableId = v,
        ),
        dialogTextField(controller: jourController, label: 'Jour de réunion'),
        dialogTextField(controller: heureController, label: 'Heure de réunion'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCellule(
                nom: nomController.text.trim(),
                quartier: quartierController.text.trim().isEmpty
                    ? null
                    : quartierController.text.trim(),
                responsableMemberId: responsableId,
                jourReunion: jourController.text.trim().isEmpty
                    ? null
                    : jourController.text.trim(),
                heureReunion: heureController.text.trim().isEmpty
                    ? null
                    : heureController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Cellule créée.');
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

  /// Dialogue de création / renommage d'un élément de catalogue (fonction
  /// ou poste) : un seul champ, le nom.
  Future<void> _editCatalogue({
    required String titre,
    required String label,
    String? nomActuel,
    required Future<void> Function(String nom) onSave,
  }) async {
    final nomController = TextEditingController(text: nomActuel ?? '');
    await showCreateDialog(
      context: context,
      title: titre,
      saveLabel: nomActuel == null ? 'Créer' : 'Enregistrer',
      fields: [dialogTextField(controller: nomController, label: label)],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        try {
          await onSave(nomController.text.trim());
          if (mounted) showSuccess(context, 'Enregistré.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteFamille(Famille famille) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer la famille « ${famille.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteFamille(famille.id);
      if (mounted) showSuccess(context, 'Famille supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
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

  Future<void> _deleteFonction(Fonction fonction) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer la fonction « ${fonction.nom} » ? '
      'Refusée si des membres la portent encore.',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteFonction(fonction.id);
      if (mounted) showSuccess(context, 'Fonction supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deletePoste(Poste poste) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer le poste « ${poste.nom} » ? '
      'Refusé si des membres l’occupent encore.',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deletePoste(poste.id);
      if (mounted) showSuccess(context, 'Poste supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deleteCellule(Cellule cellule) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la cellule « ${cellule.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteCellule(cellule.id);
      if (mounted) showSuccess(context, 'Cellule supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _famillesTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une famille',
        ),
        Expanded(
          child: FutureBuilder<List<Famille>>(
            future: _famillesFuture,
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
              final familles = snapshot.data!
                  .where((f) => _matches(f.nom))
                  .toList();
              if (familles.isEmpty) {
                return EmptyState(
                  icon: Icons.family_restroom_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune famille pour l’instant.'
                      : 'Aucune famille ne correspond à la recherche.',
                  actionLabel: 'Créer une famille',
                  onAction: () => _createFamille(membres),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: familles.length,
                  itemBuilder: (context, index) {
                    final famille = familles[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.family_restroom_outlined),
                      ),
                      title: Text(famille.nom),
                      subtitle: Text(
                        '${famille.chefFamilleId != null ? 'Chef : ${noms[famille.chefFamilleId] ?? '—'}' : 'Sans chef désigné'}'
                        '${famille.telephone != null ? ' · ${famille.telephone}' : ''}'
                        '${famille.adresse != null ? ' · ${famille.adresse}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _deleteFamille(famille),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Fiche d’un membre'),
              const Text(
                'Statuts, baptême, départements, cellules et liens parent-enfant.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Member>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Choisir un membre',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: membres
                    .map((m) => DropdownMenuItem<Member>(
                          value: m,
                          child: Text(
                            '${m.fullName} (${m.matricule})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (m) {
                  if (m == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberDetailScreen(member: m),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _departementsTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un département',
        ),
        Expanded(
          child: FutureBuilder<List<Departement>>(
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
                  .where((d) => _matches(d.nom))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.group_work_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun département pour l’instant.'
                      : 'Aucun département ne correspond à la recherche.',
                  actionLabel: 'Créer un département',
                  onAction: () => _createDepartement(membres),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Onglet catalogue (fonctions ou postes) : liste, ajout, renommage,
  /// suppression. Même structure pour les deux, seuls les appels changent.
  Widget _catalogueTab<T>({
    required Future<List<T>> future,
    required String rechercheLabel,
    required String videMessage,
    required String creerLabel,
    required IconData icon,
    required String Function(T item) nom,
    required Future<void> Function() onCreate,
    required Future<void> Function(T item) onRename,
    required Future<void> Function(T item) onDelete,
  }) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: rechercheLabel,
        ),
        Expanded(
          child: FutureBuilder<List<T>>(
            future: future,
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
                  .where((e) => _matches(nom(e)))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: icon,
                  message: snapshot.data!.isEmpty
                      ? videMessage
                      : 'Aucun élément ne correspond à la recherche.',
                  actionLabel: creerLabel,
                  onAction: onCreate,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: CircleAvatar(child: Icon(icon)),
                      title: Text(nom(item)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Renommer',
                            onPressed: () => onRename(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => onDelete(item),
                          ),
                        ],
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

  Widget _cellulesTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une cellule',
        ),
        Expanded(
          child: FutureBuilder<List<Cellule>>(
            future: _cellulesFuture,
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
                  icon: Icons.groups_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune cellule pour l’instant.'
                      : 'Aucune cellule ne correspond à la recherche.',
                  actionLabel: 'Créer une cellule',
                  onAction: () => _createCellule(membres),
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
                        child: Icon(Icons.groups_outlined),
                      ),
                      title: Text(c.nom),
                      subtitle: Text(
                        '${c.quartier ?? '—'}'
                        '${c.responsableMemberId != null ? ' · ${noms[c.responsableMemberId] ?? '—'}' : ''}'
                        '${c.jourReunion != null ? ' · ${c.jourReunion}' : ''}'
                        '${c.heureReunion != null ? ' à ${c.heureReunion}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _deleteCellule(c),
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
      length: 5,
      initialIndex: widget.ongletInitial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Familles'),
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Familles'),
              Tab(text: 'Départements'),
              Tab(text: 'Cellules'),
              Tab(text: 'Fonctions'),
              Tab(text: 'Postes'),
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
                onRetry: _refreshAll,
              );
            }
            final membres = snapshot.data!.membres;
            final api = context.read<AppState>().api;
            return TabBarView(
              children: [
                _famillesTab(membres),
                _departementsTab(membres),
                _cellulesTab(membres),
                _catalogueTab<Fonction>(
                  future: _fonctionsFuture,
                  rechercheLabel: 'Rechercher une fonction',
                  videMessage: 'Aucune fonction pour l’instant.',
                  creerLabel: 'Créer une fonction',
                  icon: Icons.work_outline,
                  nom: (f) => f.nom,
                  onCreate: () => _editCatalogue(
                    titre: 'Nouvelle fonction',
                    label: 'Nom de la fonction',
                    onSave: (nom) async =>
                        api.createFonction(nom: nom),
                  ),
                  onRename: (f) => _editCatalogue(
                    titre: 'Renommer la fonction',
                    label: 'Nom de la fonction',
                    nomActuel: f.nom,
                    onSave: (nom) async =>
                        api.updateFonction(f.id, nom: nom),
                  ),
                  onDelete: _deleteFonction,
                ),
                _catalogueTab<Poste>(
                  future: _postesFuture,
                  rechercheLabel: 'Rechercher un poste',
                  videMessage: 'Aucun poste pour l’instant.',
                  creerLabel: 'Créer un poste',
                  icon: Icons.badge_outlined,
                  nom: (p) => p.nom,
                  onCreate: () => _editCatalogue(
                    titre: 'Nouveau poste',
                    label: 'Nom du poste',
                    onSave: (nom) async =>
                        api.createPoste(nom: nom),
                  ),
                  onRename: (p) => _editCatalogue(
                    titre: 'Renommer le poste',
                    label: 'Nom du poste',
                    nomActuel: p.nom,
                    onSave: (nom) async =>
                        api.updatePoste(p.id, nom: nom),
                  ),
                  onDelete: _deletePoste,
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final membres = (await _membresFuture).membres;
              if (!mounted) return;
              if (_tab == 0) {
                await _createFamille(membres);
              } else if (_tab == 1) {
                await _createDepartement(membres);
              } else if (_tab == 2) {
                await _createCellule(membres);
              } else if (_tab == 3) {
                await _editCatalogue(
                  titre: 'Nouvelle fonction',
                  label: 'Nom de la fonction',
                  onSave: (nom) async => context
                      .read<AppState>()
                      .api
                      .createFonction(nom: nom),
                );
              } else {
                await _editCatalogue(
                  titre: 'Nouveau poste',
                  label: 'Nom du poste',
                  onSave: (nom) async => context
                      .read<AppState>()
                      .api
                      .createPoste(nom: nom),
                );
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0
              ? 'Famille'
              : _tab == 1
                  ? 'Département'
                  : _tab == 2
                      ? 'Cellule'
                      : _tab == 3
                          ? 'Fonction'
                          : 'Poste'),
        ),
      ),
    );
  }
}
