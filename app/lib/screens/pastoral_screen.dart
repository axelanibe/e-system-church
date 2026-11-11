import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../models/pastoral.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 6 — Suivi pastoral : parcours des nouveaux convertis, visites
/// pastorales et accompagnements.
class PastoralScreen extends StatefulWidget {
  const PastoralScreen({super.key});

  @override
  State<PastoralScreen> createState() => _PastoralScreenState();
}

const _etapes = {
  'accueil': 'Accueil',
  'formation': 'Formation',
  'bapteme': 'Baptême',
  'integration_cellule': 'Intégration en cellule',
  'integre': 'Intégré',
};

const _etapesOrdre = [
  'accueil',
  'formation',
  'bapteme',
  'integration_cellule',
  'integre',
];

class _PastoralScreenState extends State<PastoralScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<ParcoursNouveau>> _parcoursFuture;
  late Future<List<VisitePastorale>> _visitesFuture;
  late Future<List<Accompagnement>> _accompagnementsFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _parcoursFuture = api.getParcoursNouveaux();
    _visitesFuture = api.getVisitesPastorales();
    _accompagnementsFuture = api.getAccompagnements();
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
      if (_tab == 0) _parcoursFuture = api.getParcoursNouveaux();
      if (_tab == 1) _visitesFuture = api.getVisitesPastorales();
      if (_tab == 2) _accompagnementsFuture = api.getAccompagnements();
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<List<Member>> _membres() async =>
      (await _membresFuture).membres;

  Future<void> _createParcours(List<Member> membres) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String etape = 'accueil';
    final noteController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau parcours',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Nouveau converti',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDropdown<String>(
          value: etape,
          label: 'Étape',
          options: _etapes,
          onChanged: (v) => etape = v ?? 'accueil',
        ),
        dialogTextField(controller: noteController, label: 'Note'),
      ],
      isValid: () => memberId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createParcoursNouveau(
                memberId: memberId!,
                etape: etape,
                note: _opt(noteController),
              );
          if (mounted) showSuccess(context, 'Parcours créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _avancerEtape(ParcoursNouveau parcours) async {
    final index = _etapesOrdre.indexOf(parcours.etape);
    final suivante = index >= 0 && index + 1 < _etapesOrdre.length
        ? _etapesOrdre[index + 1]
        : null;
    String etape = suivante ?? parcours.etape;
    await showCreateDialog(
      context: context,
      title: 'Avancement du parcours',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String>(
          value: etape,
          label: 'Étape',
          options: _etapes,
          onChanged: (v) => etape = v ?? parcours.etape,
        ),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          await context
              .read<AppState>()
              .api
              .setParcoursEtape(parcours.id, etape);
          if (mounted) showSuccess(context, 'Étape mise à jour.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createVisite(List<Member> membres) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    final dateController = TextEditingController();
    final motifController = TextEditingController();
    final compteRenduController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle visite pastorale',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre visité',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDateField(
            context: context, controller: dateController, label: 'Date de la visite'),
        dialogTextField(controller: motifController, label: 'Motif'),
        dialogTextField(
          controller: compteRenduController,
          label: 'Compte rendu',
          maxLines: 3,
        ),
      ],
      isValid: () =>
          memberId != null && dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createVisitePastorale(
                memberId: memberId!,
                dateVisite: dateController.text.trim(),
                motif: motifController.text.trim(),
                compteRendu: _opt(compteRenduController),
              );
          if (mounted) showSuccess(context, 'Visite enregistrée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createAccompagnement(List<Member> membres) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String type = 'autre';
    final descriptionController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvel accompagnement',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre accompagné',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDropdown<String>(
          value: type,
          label: 'Type',
          options: const {
            'couple': 'Couple',
            'famille': 'Famille',
            'malade': 'Malade',
            'difficulte': 'En difficulté',
            'autre': 'Autre',
          },
          onChanged: (v) => type = v ?? 'autre',
        ),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
      ],
      isValid: () => memberId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createAccompagnement(
                memberId: memberId!,
                type: type,
                description: descriptionController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Accompagnement créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _parcoursTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un parcours',
        ),
        Expanded(
          child: FutureBuilder<List<ParcoursNouveau>>(
            future: _parcoursFuture,
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
                  .where((p) => _matches(noms[p.memberId] ?? p.memberId))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.route_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun parcours de nouveau converti pour l’instant.'
                      : 'Aucun parcours ne correspond à la recherche.',
                  actionLabel: 'Créer un parcours',
                  onAction: () async {
                    try {
                      final membres = await _membres();
                      if (mounted) await _createParcours(membres);
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
                    final p = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.route_outlined),
                      ),
                      title: Text(noms[p.memberId] ?? p.memberId),
                      subtitle: Text(
                        'Étape : ${_etapes[p.etape] ?? p.etape}'
                        '${p.note != null ? ' · ${p.note}' : ''}',
                      ),
                      trailing: TextButton(
                        onPressed: () => _avancerEtape(p),
                        child: const Text('Avancer'),
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

  Widget _visitesTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une visite',
        ),
        Expanded(
          child: FutureBuilder<List<VisitePastorale>>(
            future: _visitesFuture,
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
                  .where((v) => _matches(noms[v.memberId] ?? v.memberId))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.home_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune visite pastorale pour l’instant.'
                      : 'Aucune visite ne correspond à la recherche.',
                  actionLabel: 'Planifier une visite',
                  onAction: () async {
                    try {
                      final membres = await _membres();
                      if (mounted) await _createVisite(membres);
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
                    final v = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.home_outlined),
                      ),
                      title: Text(noms[v.memberId] ?? v.memberId),
                      subtitle: Text(
                        '${afficherDate(v.dateVisite)} · ${v.motif ?? '—'}'
                        '${v.compteRendu != null ? ' · ${v.compteRendu}' : ''}',
                      ),
                      trailing: StatusChip(
                        label: v.statut,
                        color: v.statut == 'realisee'
                            ? Colors.green
                            : v.statut == 'annulee'
                                ? Colors.red
                                : Colors.orange,
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

  Widget _accompagnementsTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un accompagnement',
        ),
        Expanded(
          child: FutureBuilder<List<Accompagnement>>(
            future: _accompagnementsFuture,
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
                  .where((a) => _matches(noms[a.memberId] ?? a.memberId))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.handshake_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun accompagnement pour l’instant.'
                      : 'Aucun accompagnement ne correspond à la recherche.',
                  actionLabel: 'Créer un accompagnement',
                  onAction: () async {
                    try {
                      final membres = await _membres();
                      if (mounted) await _createAccompagnement(membres);
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
                        child: Icon(Icons.handshake_outlined),
                      ),
                      title: Text(noms[a.memberId] ?? a.memberId),
                      subtitle: Text('${a.type} · ${a.description ?? '—'}'),
                      trailing: StatusChip(
                        label: a.statut,
                        color: a.statut == 'termine'
                            ? Colors.green
                            : Colors.blue,
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
          title: const Text('Suivi pastoral'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Parcours'),
              Tab(text: 'Visites'),
              Tab(text: 'Accompagnements'),
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
                _parcoursTab(noms),
                _visitesTab(noms),
                _accompagnementsTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final membres = await _membres();
              if (!mounted) return;
              if (_tab == 0) {
                await _createParcours(membres);
              } else if (_tab == 1) {
                await _createVisite(membres);
              } else {
                await _createAccompagnement(membres);
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0
              ? 'Parcours'
              : _tab == 1
                  ? 'Visite'
                  : 'Accompagnement'),
        ),
      ),
    );
  }
}
