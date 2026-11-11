import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cultes.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 2 — Cultes et programmes : types de culte, cultes (avec ordre
/// du culte en détail) et événements spéciaux.
class CultesScreen extends StatefulWidget {
  const CultesScreen({super.key});

  @override
  State<CultesScreen> createState() => _CultesScreenState();
}

class _CultesScreenState extends State<CultesScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<Culte>> _cultesFuture;
  late Future<List<CulteType>> _typesFuture;
  late Future<List<EvenementSpecial>> _evenementsFuture;

  @override
  void initState() {
    super.initState();
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
      _cultesFuture = api.getCultes();
      _typesFuture = api.getCulteTypes();
      _evenementsFuture = api.getEvenementsSpeciaux();
    });
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _cultesFuture = api.getCultes();
      if (_tab == 1) _typesFuture = api.getCulteTypes();
      if (_tab == 2) _evenementsFuture = api.getEvenementsSpeciaux();
    });
  }

  Future<void> _deleteCulte(Culte culte) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le culte « ${culte.titre} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteCulte(culte.id);
      if (mounted) showSuccess(context, 'Culte supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createType() async {
    final nomController = TextEditingController();
    final jourController = TextEditingController();
    final heureController = TextEditingController();
    final dureeController = TextEditingController();
    final lieuController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau type de culte',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom'),
        dialogTextField(
          controller: jourController,
          label: 'Jour de la semaine',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: heureController, label: 'Heure de début'),
        dialogTextField(
          controller: dureeController,
          label: 'Durée en minutes',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: lieuController, label: 'Lieu'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCulteType(
                nom: nomController.text.trim(),
                jourSemaine: int.tryParse(jourController.text.trim()),
                heureDebut: _opt(heureController),
                dureeMinutes: int.tryParse(dureeController.text.trim()),
                lieu: _opt(lieuController),
              );
          if (mounted) showSuccess(context, 'Type de culte créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createCulte(List<CulteType> types) async {
    final titreController = TextEditingController();
    final dateController = TextEditingController();
    final lieuController = TextEditingController();
    final orateurController = TextEditingController();
    final themeController = TextEditingController();
    String? typeId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau culte',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: typeId,
          label: 'Type de culte',
          options: {
            null: 'Aucun',
            for (final t in types) t.id: t.nom,
          },
          onChanged: (v) => typeId = v,
        ),
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(controller: dateController, label: 'Date et heure'),
        dialogTextField(controller: lieuController, label: 'Lieu'),
        dialogTextField(controller: orateurController, label: 'Orateur'),
        dialogTextField(controller: themeController, label: 'Thème'),
      ],
      isValid: () =>
          titreController.text.trim().isNotEmpty &&
          dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCulte(
                culteTypeId: typeId,
                titre: titreController.text.trim(),
                dateHeure: dateController.text.trim(),
                lieu: _opt(lieuController),
                orateur: _opt(orateurController),
                theme: _opt(themeController),
              );
          if (mounted) showSuccess(context, 'Culte créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createEvenement() async {
    final titreController = TextEditingController();
    final debutController = TextEditingController();
    final finController = TextEditingController();
    final descriptionController = TextEditingController();
    final lieuController = TextEditingController();
    final responsableController = TextEditingController();
    String type = 'autre';
    await showCreateDialog(
      context: context,
      title: 'Nouvel événement spécial',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String>(
          value: type,
          label: 'Type',
          options: const {
            'mariage': 'Mariage',
            'bapteme_eau': 'Baptême d’eau',
            'dedicace_enfant': 'Dédicace d’enfant',
            'funerailles': 'Funérailles',
            'conference': 'Conférence',
            'campagne': 'Campagne',
            'jeune': 'Jeûne',
            'autre': 'Autre',
          },
          onChanged: (v) => type = v ?? 'autre',
        ),
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogDateField(
            context: context, controller: debutController, label: 'Date de début'),
        dialogDateField(
            context: context, controller: finController, label: 'Date de fin'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogTextField(controller: lieuController, label: 'Lieu'),
        dialogTextField(
            controller: responsableController, label: 'Responsable'),
      ],
      isValid: () =>
          titreController.text.trim().isNotEmpty &&
          debutController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createEvenementSpecial(
                type: type,
                titre: titreController.text.trim(),
                dateDebut: debutController.text.trim(),
                dateFin: finController.text.trim().isEmpty
                    ? null
                    : finController.text.trim(),
                description: _opt(descriptionController),
                lieu: _opt(lieuController),
                responsable: _opt(responsableController),
              );
          if (mounted) showSuccess(context, 'Événement créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _cultesTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un culte',
        ),
        Expanded(
          child: FutureBuilder<List<Culte>>(
            future: _cultesFuture,
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
                  .where((c) => _matches(c.titre))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.event_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun culte planifié pour l’instant.'
                      : 'Aucun culte ne correspond à la recherche.',
                  actionLabel: 'Planifier un culte',
                  onAction: () async {
                    final types = await _typesFuture;
                    if (mounted) await _createCulte(types);
                  },
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final culte = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.event_outlined),
                      ),
                      title: Text(culte.titre),
                      subtitle: Text(
                        '${afficherDateTime(culte.dateHeure)}'
                        '${culte.lieu != null ? ' · ${culte.lieu}' : ''}'
                        '${culte.orateur != null ? ' · ${culte.orateur}' : ''}'
                        '${culte.theme != null ? ' · ${culte.theme}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _deleteCulte(culte),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CulteDetailScreen(culte: culte),
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

  Widget _typesTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un type de culte',
        ),
        Expanded(
          child: FutureBuilder<List<CulteType>>(
            future: _typesFuture,
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
                  .where((t) => _matches(t.nom))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.category_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun type de culte pour l’instant.'
                      : 'Aucun type ne correspond à la recherche.',
                  actionLabel: 'Créer un type de culte',
                  onAction: _createType,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final t = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.category_outlined),
                      ),
                      title: Text(t.nom),
                      subtitle: Text(
                        '${t.jourSemaine != null ? 'Jour ${t.jourSemaine}' : '—'}'
                        '${t.heureDebut != null ? ' · ${t.heureDebut}' : ''}'
                        '${t.dureeMinutes != null ? ' · ${t.dureeMinutes} min' : ''}'
                        '${t.lieu != null ? ' · ${t.lieu}' : ''}',
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

  Widget _evenementsTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un événement',
        ),
        Expanded(
          child: FutureBuilder<List<EvenementSpecial>>(
            future: _evenementsFuture,
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
                  .where((e) => _matches(e.titre))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.celebration_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun événement spécial pour l’instant.'
                      : 'Aucun événement ne correspond à la recherche.',
                  actionLabel: 'Créer un événement',
                  onAction: _createEvenement,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final e = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.celebration_outlined),
                      ),
                      title: Text(e.titre),
                      subtitle: Text(
                        '${e.type} · ${afficherDate(e.dateDebut)}'
                        '${e.lieu != null ? ' · ${e.lieu}' : ''}'
                        '${e.responsable != null ? ' · ${e.responsable}' : ''}',
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
          title: const Text('Cultes'),
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Cultes'),
              Tab(text: 'Types'),
              Tab(text: 'Événements'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_cultesTab(), _typesTab(), _evenementsTab()],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            if (_tab == 0) {
              try {
                final types = await _typesFuture;
                if (mounted) await _createCulte(types);
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              }
            } else if (_tab == 1) {
              await _createType();
            } else {
              await _createEvenement();
            }
          },
          icon: const Icon(Icons.add),
          label: Text(
              _tab == 0 ? 'Culte' : _tab == 1 ? 'Type' : 'Événement'),
        ),
      ),
    );
  }
}

/// Détail d'un culte : ordre du culte avec ajout d'item.
class CulteDetailScreen extends StatefulWidget {
  final Culte culte;

  const CulteDetailScreen({super.key, required this.culte});

  @override
  State<CulteDetailScreen> createState() => _CulteDetailScreenState();
}

class _CulteDetailScreenState extends State<CulteDetailScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  late Future<List<OrdreCulteItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<OrdreCulteItem>> _load() {
    return context.read<AppState>().api.getOrdreCulte(widget.culte.id);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _addItem() async {
    final titreController = TextEditingController();
    final ordreController = TextEditingController();
    final descriptionController = TextEditingController();
    final intervenantController = TextEditingController();
    final dureeController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Ajouter un élément à l’ordre du culte',
      saveLabel: 'Ajouter',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(
          controller: ordreController,
          label: 'Ordre',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogTextField(
            controller: intervenantController, label: 'Intervenant'),
        dialogTextField(
          controller: dureeController,
          label: 'Durée en minutes',
          keyboardType: TextInputType.number,
        ),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createOrdreCulteItem(
                culteId: widget.culte.id,
                titre: titreController.text.trim(),
                ordre: int.tryParse(ordreController.text.trim()) ?? 0,
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                intervenant: intervenantController.text.trim().isEmpty
                    ? null
                    : intervenantController.text.trim(),
                dureeMinutes: int.tryParse(dureeController.text.trim()),
              );
          if (mounted) showSuccess(context, 'Élément ajouté à l’ordre du culte.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final culte = widget.culte;
    return Scaffold(
      appBar: AppBar(title: Text(culte.titre)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${afficherDateTime(culte.dateHeure)}'
                  '${culte.lieu != null ? ' · ${culte.lieu}' : ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (culte.orateur != null) Text('Orateur : ${culte.orateur}'),
                if (culte.theme != null) Text('Thème : ${culte.theme}'),
              ],
            ),
          ),
          const Divider(height: 1),
          const SectionTitle(title: 'Ordre du culte'),
          searchField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim()),
            label: 'Rechercher un élément',
          ),
          Expanded(
            child: FutureBuilder<List<OrdreCulteItem>>(
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
                final items = snapshot.data!
                    .where((i) =>
                        _query.isEmpty ||
                        i.titre.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.list_outlined,
                    message: snapshot.data!.isEmpty
                        ? 'Aucun élément dans l’ordre du culte pour l’instant.'
                        : 'Aucun élément ne correspond à la recherche.',
                    actionLabel: 'Ajouter un élément',
                    onAction: _addItem,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${item.ordre}'),
                        ),
                        title: Text(item.titre),
                        subtitle: Text(
                          '${item.intervenant ?? '—'}'
                          '${item.dureeMinutes != null ? ' · ${item.dureeMinutes} min' : ''}'
                          '${item.description != null ? ' · ${item.description}' : ''}',
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Élément'),
      ),
    );
  }
}
