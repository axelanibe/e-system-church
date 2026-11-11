import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/biens.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 10 — Biens de l'église : salles et réservations, matériel et
/// maintenance.
class BiensScreen extends StatefulWidget {
  const BiensScreen({super.key});

  @override
  State<BiensScreen> createState() => _BiensScreenState();
}

class _BiensScreenState extends State<BiensScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<Salle>> _sallesFuture;
  late Future<List<ReservationSalle>> _reservationsFuture;
  late Future<List<Materiel>> _materielFuture;
  late Future<List<MaintenanceMateriel>> _maintenanceFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _sallesFuture = api.getSalles();
    _reservationsFuture = api.getReservationsSalles();
    _materielFuture = api.getMateriel();
    _maintenanceFuture = api.getMaintenanceMateriel();
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
      if (_tab == 0) {
        _sallesFuture = api.getSalles();
        _reservationsFuture = api.getReservationsSalles();
      } else {
        _materielFuture = api.getMateriel();
        _maintenanceFuture = api.getMaintenanceMateriel();
      }
    });
  }

  Future<void> _deleteSalle(Salle salle) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la salle « ${salle.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteSalle(salle.id);
      if (mounted) showSuccess(context, 'Salle supprimée.');
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

  Future<List<Member>> _membres() async =>
      (await _membresFuture).membres;

  Future<void> _createSalle() async {
    final nomController = TextEditingController();
    final capaciteController = TextEditingController();
    final descriptionController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle salle',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la salle'),
        dialogTextField(
          controller: capaciteController,
          label: 'Capacité',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createSalle(
                nom: nomController.text.trim(),
                capacite: int.tryParse(capaciteController.text.trim()),
                description: _opt(descriptionController),
              );
          if (mounted) showSuccess(context, 'Salle créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createReservation(List<Salle> salles) async {
    String? salleId = salles.isEmpty ? null : salles.first.id;
    final titreController = TextEditingController();
    final debutController = TextEditingController();
    final finController = TextEditingController();
    final reserveParController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle réservation',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: salleId,
          label: 'Salle',
          options: {for (final s in salles) s.id: s.nom},
          onChanged: (v) => salleId = v,
        ),
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(controller: debutController, label: 'Début'),
        dialogTextField(controller: finController, label: 'Fin'),
        dialogTextField(controller: reserveParController, label: 'Réservé par'),
      ],
      isValid: () =>
          salleId != null && titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createReservationSalle(
                salleId: salleId!,
                titre: titreController.text.trim(),
                debut: debutController.text.trim(),
                fin: finController.text.trim(),
                reservePar: _opt(reserveParController),
              );
          if (mounted) showSuccess(context, 'Réservation créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createMateriel(List<Member> membres) async {
    final nomController = TextEditingController();
    final categorieController = TextEditingController();
    final quantiteController = TextEditingController();
    String etat = 'bon';
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau matériel',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du matériel'),
        dialogTextField(controller: categorieController, label: 'Catégorie'),
        dialogTextField(
          controller: quantiteController,
          label: 'Quantité',
          keyboardType: TextInputType.number,
        ),
        dialogDropdown<String>(
          value: etat,
          label: 'État',
          options: const {
            'bon': 'Bon',
            'a_reparer': 'À réparer',
            'hors_service': 'Hors service',
          },
          onChanged: (v) => etat = v ?? 'bon',
        ),
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
          await context.read<AppState>().api.createMateriel(
                nom: nomController.text.trim(),
                categorie: _opt(categorieController),
                quantite: int.tryParse(quantiteController.text.trim()) ?? 1,
                etat: etat,
                responsableMemberId: responsableId,
              );
          if (mounted) showSuccess(context, 'Matériel ajouté.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createMaintenance(List<Materiel> materiels) async {
    String? materielId = materiels.isEmpty ? null : materiels.first.id;
    final descriptionController = TextEditingController();
    final dateController = TextEditingController();
    final coutController = TextEditingController();
    final realiseParController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle maintenance',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: materielId,
          label: 'Matériel',
          options: {for (final m in materiels) m.id: m.nom},
          onChanged: (v) => materielId = v,
        ),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogDateField(
            context: context,
            controller: dateController,
            label: 'Date de la maintenance'),
        dialogTextField(
          controller: coutController,
          label: 'Coût',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
            controller: realiseParController, label: 'Réalisé par'),
      ],
      isValid: () => materielId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMaintenanceMateriel(
                materielId: materielId!,
                description: descriptionController.text.trim(),
                dateMaintenance: dateController.text.trim().isEmpty
                    ? null
                    : dateController.text.trim(),
                coutFcfa: int.tryParse(coutController.text.trim()),
                realisePar: _opt(realiseParController),
              );
          if (mounted) showSuccess(context, 'Maintenance enregistrée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _sallesTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une salle ou une réservation',
        ),
        Expanded(
          child: FutureBuilder<List<Salle>>(
            future: _sallesFuture,
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
              final salles = snapshot.data!
                  .where((s) => _matches(s.nom))
                  .toList();
              return FutureBuilder<List<ReservationSalle>>(
                future: _reservationsFuture,
                builder: (context, resSnapshot) {
                  if (resSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  if (resSnapshot.hasError) {
                    return AppError(
                      message: resSnapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final reservations = resSnapshot.data!
                      .where((r) => _matches(r.titre))
                      .toList();
                  final sallesNoms = {
                    for (final s in snapshot.data!) s.id: s.nom
                  };
                  if (salles.isEmpty && reservations.isEmpty) {
                    return EmptyState(
                      icon: Icons.meeting_room_outlined,
                      message: 'Aucune salle pour l’instant.',
                      actionLabel: 'Créer une salle',
                      onAction: _createSalle,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SectionTitle(title: 'Salles'),
                        if (salles.isEmpty)
                          const EmptyState(
                            icon: Icons.meeting_room_outlined,
                            message: 'Aucune salle pour l’instant.',
                          )
                        else
                          ...salles.map((s) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.meeting_room_outlined),
                                ),
                                title: Text(s.nom),
                                subtitle: Text(
                                  '${s.capacite != null ? 'Capacité : ${s.capacite}' : 'Capacité non précisée'}'
                                  '${s.description != null ? ' · ${s.description}' : ''}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Supprimer',
                                  onPressed: () => _deleteSalle(s),
                                ),
                              )),
                        const SectionTitle(title: 'Réservations'),
                        if (reservations.isEmpty)
                          const EmptyState(
                            icon: Icons.event_available_outlined,
                            message:
                                'Aucune réservation de salle pour l’instant.',
                          )
                        else
                          ...reservations.map((r) => ListTile(
                                leading: const CircleAvatar(
                                  child:
                                      Icon(Icons.event_available_outlined),
                                ),
                                title: Text(r.titre),
                                subtitle: Text(
                                  '${sallesNoms[r.salleId] ?? '—'} · ${afficherDateTime(r.debut)} — ${afficherDateTime(r.fin)}'
                                  '${r.reservePar != null ? ' · ${r.reservePar}' : ''}',
                                ),
                                trailing: StatusChip(
                                  label: r.statut,
                                  color: r.statut == 'annulee'
                                      ? AppTheme.rougeErreur
                                      : AppTheme.vertFonce,
                                ),
                              )),
                        const SizedBox(height: 80),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _materielTab(Map<String, String> noms) {
    final state = context.watch<AppState>();
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher du matériel',
        ),
        Expanded(
          child: FutureBuilder<List<Materiel>>(
            future: _materielFuture,
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
                  .where((m) => _matches(m.nom))
                  .toList();
              return FutureBuilder<List<MaintenanceMateriel>>(
                future: _maintenanceFuture,
                builder: (context, maintSnapshot) {
                  if (maintSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  if (maintSnapshot.hasError) {
                    return AppError(
                      message: maintSnapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final maintenances = maintSnapshot.data!;
                  final materielNoms = {
                    for (final m in snapshot.data!) m.id: m.nom
                  };
                  if (items.isEmpty && maintenances.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'Aucun matériel enregistré pour l’instant.',
                      actionLabel: 'Ajouter du matériel',
                      onAction: () async {
                        try {
                          final membres = await _membres();
                          if (mounted) await _createMateriel(membres);
                        } catch (e) {
                          if (context.mounted) showApiError(context, e);
                        }
                      },
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SectionTitle(title: 'Matériel'),
                        if (items.isEmpty)
                          const EmptyState(
                            icon: Icons.inventory_2_outlined,
                            message: 'Aucun matériel pour l’instant.',
                          )
                        else
                          ...items.map((m) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.inventory_2_outlined),
                                ),
                                title: Text(m.nom),
                                subtitle: Text(
                                  '${m.categorie ?? '—'} · Quantité : ${m.quantite} · État : ${m.etat}'
                                  '${m.responsableMemberId != null ? ' · ${noms[m.responsableMemberId] ?? '—'}' : ''}',
                                ),
                              )),
                        const SectionTitle(title: 'Maintenance'),
                        if (maintenances.isEmpty)
                          const EmptyState(
                            icon: Icons.build_outlined,
                            message: 'Aucune maintenance enregistrée pour l’instant.',
                          )
                        else
                          ...maintenances.map((m) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.build_outlined),
                                ),
                                title:
                                    Text(materielNoms[m.materielId] ??
                                        m.materielId),
                                subtitle: Text(
                                  '${afficherDate(m.dateMaintenance)}'
                                  '${m.coutFcfa != null ? ' · ${formatMontant(m.coutFcfa!, state.devise)}' : ''}'
                                  '${m.realisePar != null ? ' · ${m.realisePar}' : ''}',
                                ),
                              )),
                        const SizedBox(height: 80),
                      ],
                    ),
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Biens de l’église'),
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Salles & réservations'),
              Tab(text: 'Matériel & maintenance'),
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
                _sallesTab(),
                _materielTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                final choix = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Ajouter'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(ctx).pop('salle'),
                        child: const Text('Une salle'),
                      ),
                      SimpleDialogOption(
                        onPressed: () =>
                            Navigator.of(ctx).pop('reservation'),
                        child: const Text('Une réservation'),
                      ),
                    ],
                  ),
                );
                if (choix == 'salle' && mounted) {
                  await _createSalle();
                } else if (choix == 'reservation' && mounted) {
                  final salles = await _sallesFuture;
                  if (mounted) await _createReservation(salles);
                }
              } else {
                final choix = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Ajouter'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(ctx).pop('materiel'),
                        child: const Text('Du matériel'),
                      ),
                      SimpleDialogOption(
                        onPressed: () =>
                            Navigator.of(ctx).pop('maintenance'),
                        child: const Text('Une maintenance'),
                      ),
                    ],
                  ),
                );
                if (choix == 'materiel' && mounted) {
                  final membres = await _membres();
                  if (mounted) await _createMateriel(membres);
                } else if (choix == 'maintenance' && mounted) {
                  final materiels = await _materielFuture;
                  if (mounted) await _createMaintenance(materiels);
                }
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
      ),
    );
  }
}
