import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/cultes.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../models/serviteurs.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 7 — Serviteurs par département et planning des services.
class ServiteursScreen extends StatefulWidget {
  const ServiteursScreen({super.key});

  @override
  State<ServiteursScreen> createState() => _ServiteursScreenState();
}

class _ServiteursScreenState extends State<ServiteursScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';
  String? _departementFilter;

  late Future<List<Serviteur>> _serviteursFuture;
  late Future<List<PlanningServiteur>> _planningFuture;
  late Future<List<Departement>> _departementsFuture;
  late Future<MemberPage> _membresFuture;
  late Future<List<Culte>> _cultesFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _serviteursFuture = api.getServiteurs();
    _planningFuture = api.getPlanningServiteurs();
    _departementsFuture = api.getDepartements();
    _membresFuture = api.getMembers();
    _cultesFuture = api.getCultes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) {
        _serviteursFuture =
            api.getServiteurs(departementId: _departementFilter);
      } else {
        _planningFuture = api.getPlanningServiteurs();
      }
    });
  }

  Future<void> _deleteServiteur(
      Serviteur serviteur, Map<String, String> noms) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le serviteur « ${noms[serviteur.memberId] ?? serviteur.memberId} » (${serviteur.role}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteServiteur(serviteur.id);
      if (mounted) showSuccess(context, 'Serviteur supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<void> _createServiteur(
      List<Member> membres, List<Departement> departements) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String? departementId =
        departements.isEmpty ? null : departements.first.id;
    final roleController = TextEditingController(text: '');
    final disponibiliteController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Affecter un serviteur',
      saveLabel: 'Affecter',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDropdown<String?>(
          value: departementId,
          label: 'Département',
          options: {
            for (final d in departements) d.id: d.nom,
          },
          onChanged: (v) => departementId = v,
        ),
        dialogTextField(controller: roleController, label: 'Rôle'),
        dialogTextField(
            controller: disponibiliteController, label: 'Disponibilité'),
      ],
      isValid: () => memberId != null && departementId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createServiteur(
                memberId: memberId!,
                departementId: departementId!,
                role: roleController.text.trim().isEmpty
                    ? 'serviteur'
                    : roleController.text.trim(),
                disponibilite: disponibiliteController.text.trim().isEmpty
                    ? null
                    : disponibiliteController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Serviteur affecté.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createPlanning(
      List<Serviteur> serviteurs, List<Culte> cultes, Map<String, String> noms) async {
    String? serviteurId = serviteurs.isEmpty ? null : serviteurs.first.id;
    String? culteId;
    final dateController = TextEditingController();
    final roleController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Planifier un service',
      saveLabel: 'Planifier',
      fields: [
        dialogDropdown<String?>(
          value: serviteurId,
          label: 'Serviteur',
          options: {
            for (final s in serviteurs)
              s.id: noms[s.memberId] ?? s.memberId,
          },
          onChanged: (v) => serviteurId = v,
        ),
        dialogDropdown<String?>(
          value: culteId,
          label: 'Culte',
          options: {
            null: 'Aucun',
            for (final c in cultes) c.id: c.titre,
          },
          onChanged: (v) => culteId = v,
        ),
        dialogDateField(
            context: context, controller: dateController, label: 'Date du service'),
        dialogTextField(controller: roleController, label: 'Rôle du service'),
      ],
      isValid: () =>
          serviteurId != null && dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createPlanningServiteur(
                serviteurId: serviteurId!,
                dateService: dateController.text.trim(),
                culteId: culteId,
                roleService: roleController.text.trim().isEmpty
                    ? null
                    : roleController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Service planifié.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _serviteursTab(Map<String, String> noms,
      Map<String, String> departementsNoms, List<Departement> departements) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un serviteur',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String?>(
            initialValue: _departementFilter,
            decoration: const InputDecoration(
              labelText: 'Département',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Tous les départements')),
              for (final d in departements)
                DropdownMenuItem<String?>(value: d.id, child: Text(d.nom)),
            ],
            onChanged: (value) {
              setState(() {
                _departementFilter = value;
                _serviteursFuture = context
                    .read<AppState>()
                    .api
                    .getServiteurs(departementId: value);
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<Serviteur>>(
            future: _serviteursFuture,
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
                  .where((s) => _matches(noms[s.memberId] ?? s.memberId))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun serviteur affecté pour l’instant.'
                      : 'Aucun serviteur ne correspond à la recherche.',
                  actionLabel: 'Affecter un serviteur',
                  onAction: () async {
                    try {
                      final membres =
                          (await _membresFuture).membres;
                      if (mounted) {
                        await _createServiteur(membres, departements);
                      }
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
                    final s = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.volunteer_activism_outlined),
                      ),
                      title: Text(noms[s.memberId] ?? s.memberId),
                      subtitle: Text(
                        '${departementsNoms[s.departementId] ?? '—'} · ${s.role}'
                        '${s.disponibilite != null ? ' · ${s.disponibilite}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _deleteServiteur(s, noms),
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

  Widget _planningTab(Map<String, String> noms, List<Culte> cultes) {
    final cultesTitres = {for (final c in cultes) c.id: c.titre};
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher dans le planning',
        ),
        Expanded(
          child: FutureBuilder<List<PlanningServiteur>>(
            future: _planningFuture,
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
                  .where((p) => _matches(
                      '${noms[p.serviteurId] ?? ''} ${p.roleService ?? ''}'))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.calendar_month_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun service planifié pour l’instant.'
                      : 'Aucun service ne correspond à la recherche.',
                  actionLabel: 'Planifier un service',
                  onAction: () async {
                    try {
                      final serviteurs = await _serviteursFuture;
                      final cultesList = await _cultesFuture;
                      final membres =
                          (await _membresFuture).membres;
                      if (!mounted) return;
                      final nomsMembres = {
                        for (final m in membres) m.id: m.fullName
                      };
                      await _createPlanning(
                          serviteurs, cultesList, nomsMembres);
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
                        child: Icon(Icons.calendar_month_outlined),
                      ),
                      title: Text(noms[p.serviteurId] ?? p.serviteurId),
                      subtitle: Text(
                        '${afficherDate(p.dateService)}'
                        '${p.culteId != null ? ' · ${cultesTitres[p.culteId] ?? '—'}' : ''}'
                        '${p.roleService != null ? ' · ${p.roleService}' : ''}',
                      ),
                      trailing: StatusChip(
                        label: p.statut,
                        color: p.statut == 'confirme'
                            ? AppTheme.saugeFonce
                            : p.statut == 'absent'
                                ? AppTheme.rougeErreur
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Serviteurs'),
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Serviteurs'),
              Tab(text: 'Planning'),
            ],
          ),
        ),
        body: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            _membresFuture,
            _departementsFuture,
            _cultesFuture,
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {
                  final api = context.read<AppState>().api;
                  _membresFuture = api.getMembers();
                  _departementsFuture = api.getDepartements();
                  _cultesFuture = api.getCultes();
                }),
              );
            }
            final membres =
                (snapshot.data![0] as MemberPage).membres;
            final departements =
                snapshot.data![1] as List<Departement>;
            final cultes = snapshot.data![2] as List<Culte>;
            final noms = {for (final m in membres) m.id: m.fullName};
            final departementsNoms = {
              for (final d in departements) d.id: d.nom
            };
            // Noms des serviteurs : id serviteur -> nom du membre.
            return FutureBuilder<List<Serviteur>>(
              future: _serviteursFuture,
              builder: (context, servSnapshot) {
                final serviteurs = servSnapshot.data ?? const <Serviteur>[];
                final serviteurNoms = {
                  for (final s in serviteurs) s.id: noms[s.memberId] ?? s.memberId
                };
                return TabBarView(
                  children: [
                    _serviteursTab(noms, departementsNoms, departements),
                    _planningTab(serviteurNoms, cultes),
                  ],
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final membres = (await _membresFuture).membres;
              if (!mounted) return;
              if (_tab == 0) {
                final departements = await _departementsFuture;
                if (mounted) {
                  await _createServiteur(membres, departements);
                }
              } else {
                final serviteurs = await _serviteursFuture;
                final cultes = await _cultesFuture;
                if (!mounted) return;
                final noms = {for (final m in membres) m.id: m.fullName};
                await _createPlanning(serviteurs, cultes, noms);
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0 ? 'Serviteur' : 'Service'),
        ),
      ),
    );
  }
}
