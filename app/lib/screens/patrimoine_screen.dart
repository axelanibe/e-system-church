import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../models/gouvernance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// T10 — Patrimoine : bâtiments et biens avec valeur, assurance, photo
/// et code d'inventaire ; maintenance reliée aux dépenses.
class PatrimoineScreen extends StatefulWidget {
  const PatrimoineScreen({super.key});

  @override
  State<PatrimoineScreen> createState() => _PatrimoineScreenState();
}

class _PatrimoineScreenState extends State<PatrimoineScreen> {
  int _tab = 0;
  late Future<List<BienPatrimoine>> _biensFuture;
  late Future<List<MaintenancePatrimoine>> _maintenanceFuture;
  late Future<List<Depense>> _depensesFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _biensFuture = api.getBiensPatrimoine();
    _maintenanceFuture = api.getMaintenancePatrimoine();
    _depensesFuture = api.getDepenses();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _biensFuture = api.getBiensPatrimoine();
      _maintenanceFuture = api.getMaintenancePatrimoine();
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createBien() async {
    final nomController = TextEditingController();
    final valeurController = TextEditingController();
    final assuranceController = TextEditingController();
    final photoController = TextEditingController();
    final codeController = TextEditingController();
    String categorie = 'batiment';
    await showCreateDialog(
      context: context,
      title: 'Nouveau bien',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du bien'),
        dialogDropdown<String>(
          value: categorie,
          label: 'Catégorie',
          options: const {
            'batiment': 'Bâtiment',
            'terrain': 'Terrain',
            'vehicule': 'Véhicule',
            'equipement': 'Équipement',
            'autre': 'Autre',
          },
          onChanged: (v) => categorie = v ?? 'batiment',
        ),
        dialogTextField(
          controller: valeurController,
          label: 'Valeur (FCFA)',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: assuranceController, label: 'Assurance'),
        dialogTextField(controller: photoController, label: 'URL de la photo'),
        dialogTextField(
            controller: codeController, label: 'Code d’inventaire'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createBienPatrimoine(
                nom: nomController.text.trim(),
                categorie: categorie,
                valeurFcfa: int.tryParse(valeurController.text.trim()),
                assurance: _opt(assuranceController),
                photoUrl: _opt(photoController),
                codeInventaire: _opt(codeController),
              );
          if (mounted) showSuccess(context, 'Bien créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createMaintenance(
    List<BienPatrimoine> biens,
    List<Depense> depenses,
  ) async {
    String? bienId = biens.isEmpty ? null : biens.first.id;
    String? depenseId;
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
          value: bienId,
          label: 'Bien',
          options: {for (final b in biens) b.id: b.nom},
          onChanged: (v) => bienId = v,
        ),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date de la maintenance',
        ),
        dialogTextField(
          controller: coutController,
          label: 'Coût (FCFA)',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
            controller: realiseParController, label: 'Réalisé par'),
        dialogDropdown<String?>(
          value: depenseId,
          label: 'Dépense liée',
          options: {
            null: 'Aucune',
            for (final d in depenses)
              d.id:
                  '${d.reference ?? d.motif} · ${formatFcfa(d.montantFcfa)}',
          },
          onChanged: (v) => depenseId = v,
        ),
      ],
      isValid: () =>
          bienId != null && descriptionController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMaintenancePatrimoine(
                bienId: bienId!,
                description: descriptionController.text.trim(),
                dateMaintenance: _opt(dateController),
                coutFcfa: int.tryParse(coutController.text.trim()),
                realisePar: _opt(realiseParController),
                depenseId: depenseId,
              );
          if (mounted) showSuccess(context, 'Maintenance enregistrée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _supprimerBien(BienPatrimoine bien) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le bien « ${bien.nom} » ? Ses maintenances seront aussi supprimées.',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteBienPatrimoine(bien.id);
      if (mounted) showSuccess(context, 'Bien supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _biensTab() {
    final state = context.watch<AppState>();
    return FutureBuilder<List<BienPatrimoine>>(
      future: _biensFuture,
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.domain_outlined,
            message: 'Aucun bien du patrimoine pour l’instant.',
            actionLabel: 'Ajouter un bien',
            onAction: _createBien,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final b = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.domain_outlined),
                ),
                title: Text(b.nom),
                subtitle: Text(
                  '${b.categorieLabel}'
                  '${b.valeurFcfa != null ? ' · ${formatMontant(b.valeurFcfa!, state.devise)}' : ''}'
                  '${b.codeInventaire != null ? ' · ${b.codeInventaire}' : ''}'
                  '${b.assurance != null ? ' · ${b.assurance}' : ''}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: () => _supprimerBien(b),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _maintenanceTab(Map<String, String> biensNoms) {
    final state = context.watch<AppState>();
    return FutureBuilder<List<MaintenancePatrimoine>>(
      future: _maintenanceFuture,
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.build_outlined,
            message: 'Aucune maintenance enregistrée pour l’instant.',
            actionLabel: 'Enregistrer une maintenance',
            onAction: () async {
              try {
                final biens = await _biensFuture;
                final depenses = await _depensesFuture;
                if (mounted) await _createMaintenance(biens, depenses);
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
              final m = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.build_outlined),
                ),
                title: Text(biensNoms[m.bienId] ?? 'Bien'),
                subtitle: Text(
                  '${m.dateMaintenance != null ? '${afficherDate(m.dateMaintenance)} · ' : ''}'
                  '${m.description}'
                  '${m.coutFcfa != null ? ' · ${formatMontant(m.coutFcfa!, state.devise)}' : ''}'
                  '${m.realisePar != null ? ' · ${m.realisePar}' : ''}',
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patrimoine'),
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Biens'),
              Tab(text: 'Maintenance'),
            ],
          ),
        ),
        body: FutureBuilder<List<BienPatrimoine>>(
          future: _biensFuture,
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
            final noms = {for (final b in snapshot.data!) b.id: b.nom};
            return TabBarView(
              children: [
                _biensTab(),
                _maintenanceTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                await _createBien();
              } else {
                final biens = await _biensFuture;
                final depenses = await _depensesFuture;
                if (mounted) await _createMaintenance(biens, depenses);
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
