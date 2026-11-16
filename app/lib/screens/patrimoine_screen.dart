import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../models/gouvernance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';

/// T10 — Patrimoine : bâtiments et biens avec valeur, assurance, photo
/// et code d'inventaire ; maintenance reliée aux dépenses.
class PatrimoineScreen extends StatefulWidget {
  const PatrimoineScreen({super.key});

  @override
  State<PatrimoineScreen> createState() => _PatrimoineScreenState();
}

/// Types de maintenance (maquette, écran 8). L'API n'a pas de champ
/// type : le type choisi est envoyé comme description.
const _typesMaintenance = {
  'entretien': 'Entretien',
  'reparation': 'Réparation',
  'controle': 'Contrôle',
  'renovation': 'Rénovation',
  'autre': 'Autre',
};

class _PatrimoineScreenState extends State<PatrimoineScreen> {
  int _tab = 0;
  late Future<List<BienPatrimoine>> _biensFuture;
  late Future<List<MaintenancePatrimoine>> _maintenanceFuture;
  late Future<List<Depense>> _depensesFuture;

  // L'onglet actif est-il vide ? Sert à masquer le FAB quand l'état
  // vide affiche déjà le bouton de création (motif Serviteurs : un
  // seul bouton, pas deux).
  bool _biensVides = false;
  bool _maintenanceVides = false;

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
    final codeController = TextEditingController();
    String categorie = 'batiment';
    // Photo du bien (maquette, écran 8) : sélecteur appareil photo
    // ou galerie, motif FilePicker avec lecture des octets sur le
    // web. Il n'existe pas de route serveur de téléversement pour
    // les photos de biens : la photo choisie est enregistrée en
    // data URI dans `photo_url`, en attendant une route dédiée.
    Uint8List? photoBytes;
    String? photoNom;
    String? photoMime;
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
        StatefulBuilder(
          builder: (dialogContext, setDialogState) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final result =
                          await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        withData: true,
                      );
                      final file = result?.files.single;
                      if (file == null) return;
                      if (file.size > 2 * 1024 * 1024) {
                        if (mounted) {
                          showApiError(context,
                              'La photo doit peser 2 Mo au maximum.');
                        }
                        return;
                      }
                      final bytes = file.bytes;
                      if (bytes == null) {
                        if (mounted) {
                          showApiError(
                              context, 'Impossible de lire cette photo.');
                        }
                        return;
                      }
                      final ext =
                          (file.extension ?? 'jpg').toLowerCase();
                      setDialogState(() {
                        photoBytes = bytes;
                        photoNom = file.name;
                        photoMime =
                            ext == 'png' ? 'image/png' : 'image/jpeg';
                      });
                    } catch (e) {
                      if (mounted) showApiError(context, e);
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(photoNom ?? 'Ajouter une photo', style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Appareil photo ou galerie',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
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
                photoUrl: photoBytes == null
                    ? null
                    : 'data:${photoMime ?? 'image/jpeg'};base64,${base64Encode(photoBytes!)}',
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
    String type = 'entretien';
    final dateController = TextEditingController();
    final coutController = TextEditingController();
    final prestataireController = TextEditingController();
    // Maquette, écran 8 : quand aucun bien n'existe, le champ Bien
    // affiche « Aucun bien — ajoutez d'abord un bien ».
    final champBien = biens.isEmpty
        ? const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Aucun bien — ajoutez d’abord un bien', style: TextStyle(fontSize: 12.5)),
          )
        : dialogDropdown<String?>(
            value: bienId,
            label: 'Bien *',
            options: {for (final b in biens) b.id: b.nom},
            onChanged: (v) => bienId = v,
          );
    await showCreateDialog(
      context: context,
      title: 'Enregistrer une maintenance',
      saveLabel: 'Créer',
      fields: [
        champBien,
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date de la maintenance',
        ),
        dialogDropdown<String>(
          value: type,
          label: 'Type *',
          options: _typesMaintenance,
          onChanged: (v) => type = v ?? 'entretien',
        ),
        dialogTextField(
          controller: coutController,
          label: 'Coût (FCFA)',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
            controller: prestataireController,
            label: 'Prestataire (facultatif)'),
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
      isValid: () => bienId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMaintenancePatrimoine(
                bienId: bienId!,
                // L'API n'a pas de champ type ni prestataire : le
                // type part comme description, le prestataire comme
                // « réalisé par ».
                description: _typesMaintenance[type] ?? 'Entretien',
                dateMaintenance: _opt(dateController),
                coutFcfa: int.tryParse(coutController.text.trim()),
                realisePar: _opt(prestataireController),
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
        if (items.isEmpty != _biensVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _biensVides != items.isEmpty) {
              setState(() => _biensVides = items.isEmpty);
            }
          });
        }
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.domain_outlined,
            // État vide de la maquette, écran 8.
            message: 'Aucun bien\nLes biens de l’église s’enregistreront ici.',
            actionLabel: 'Ajouter un bien',
            onAction: _createBien,
          );
        }
        return ListeAvecFab(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final b = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.domain_outlined),
                ),
                title: Text(b.nom, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${b.categorieLabel}'
                  '${b.valeurFcfa != null ? ' · ${formatMontant(b.valeurFcfa!, state.devise)}' : ''}'
                  '${b.codeInventaire != null ? ' · ${b.codeInventaire}' : ''}'
                  '${b.assurance != null ? ' · ${b.assurance}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: () => _supprimerBien(b),
                ),
              );
            },
          ),
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
        if (items.isEmpty != _maintenanceVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _maintenanceVides != items.isEmpty) {
              setState(() => _maintenanceVides = items.isEmpty);
            }
          });
        }
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.build_outlined,
            // État vide de la maquette, écran 8.
            message: 'Aucune maintenance\nLes maintenances enregistrées s’afficheront ici.',
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
        return ListeAvecFab(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final m = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.build_outlined),
                ),
                title: Text(biensNoms[m.bienId] ?? 'Bien', style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${m.dateMaintenance != null ? '${afficherDate(m.dateMaintenance)} · ' : ''}'
                  '${m.description}'
                  '${m.coutFcfa != null ? ' · ${formatMontant(m.coutFcfa!, state.devise)}' : ''}'
                  '${m.realisePar != null ? ' · ${m.realisePar}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              );
            },
          ),
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
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Biens'),
              Tab(text: 'Maintenance'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Maquette, écran 8 : sous-titre 12,5 px.
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Biens de l’église et maintenance.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<BienPatrimoine>>(
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
            ),
          ],
        ),
        floatingActionButton: ((_tab == 0 && _biensVides) ||
                (_tab == 1 && _maintenanceVides))
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    if (_tab == 0) {
                      await _createBien();
                    } else {
                      final biens = await _biensFuture;
                      final depenses = await _depensesFuture;
                      if (mounted) {
                        await _createMaintenance(biens, depenses);
                      }
                    }
                  } catch (e) {
                    if (context.mounted) showApiError(context, e);
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(_tab == 0
                    ? 'Ajouter un bien'
                    : 'Enregistrer une maintenance',
                    style: const TextStyle(fontSize: 13.5)),
              ),
      ),
    );
  }
}
