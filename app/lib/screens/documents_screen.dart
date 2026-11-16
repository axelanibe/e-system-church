import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/gouvernance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';

/// T10 — Documents classés : statuts, règlements, modèles et courriers
/// entrants / sortants, avec recherche et filtres. Un modèle est un
/// document de catégorie « Modèle ».
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _contenuKey = GlobalKey<ContenuDocumentsState>();

  // La liste est-elle vide ? Sert à masquer le FAB quand l'état vide
  // affiche déjà le bouton de création (un seul bouton, pas deux).
  bool _listeVide = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: ContenuDocuments(
        key: _contenuKey,
        onVideChange: (vide) {
          if (vide != _listeVide) {
            setState(() => _listeVide = vide);
          }
        },
      ),
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _contenuKey.currentState?.creer(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter', style: TextStyle(fontSize: 13.5)),
            ),
    );
  }
}

/// Contenu de l'écran Documents, sans Scaffold ni barre : le même
/// contenu sert à DocumentsScreen et à l'onglet Documents du hub
/// Mandats (maquette, écran 7). La création se déclenche depuis le
/// FAB du parent, par `creer()` ; le vide se signale par
/// [onVideChange] pour masquer ce FAB quand l'état vide a déjà son
/// bouton.
class ContenuDocuments extends StatefulWidget {
  final ValueChanged<bool>? onVideChange;

  const ContenuDocuments({super.key, this.onVideChange});

  @override
  State<ContenuDocuments> createState() => ContenuDocumentsState();
}

const _categories = {
  null: 'Toutes catégories',
  'statuts': 'Statuts',
  'reglement': 'Règlement',
  'decision': 'Décision',
  'courrier': 'Courrier',
  'modele': 'Modèle',
  'autre': 'Autre',
};

const _sensOptions = {
  null: 'Tous sens',
  'entrant': 'Entrant',
  'sortant': 'Sortant',
  'interne': 'Interne',
};

class ContenuDocumentsState extends State<ContenuDocuments> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categorie;
  String? _sens;
  late Future<List<GouvernanceDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getDocuments(
            q: _query.isEmpty ? null : _query,
            categorie: _categorie,
            sens: _sens,
          );
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Ouvre le dialogue de création (appelé par le FAB du parent).
  Future<void> creer() async {
    final titreController = TextEditingController();
    final referenceController = TextEditingController();
    final descriptionController = TextEditingController();
    final dateController = TextEditingController();
    String categorie = 'autre';
    String? sens;
    await showCreateDialog(
      context: context,
      title: 'Nouveau document',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogDropdown<String>(
          value: categorie,
          label: 'Catégorie',
          options: const {
            'statuts': 'Statuts',
            'reglement': 'Règlement',
            'decision': 'Décision',
            'courrier': 'Courrier',
            'modele': 'Modèle',
            'autre': 'Autre',
          },
          onChanged: (v) => categorie = v ?? 'autre',
        ),
        dialogDropdown<String?>(
          value: sens,
          label: 'Sens (courriers)',
          options: const {
            null: 'Non précisé',
            'entrant': 'Entrant',
            'sortant': 'Sortant',
            'interne': 'Interne',
          },
          onChanged: (v) => sens = v,
        ),
        dialogTextField(controller: referenceController, label: 'Référence'),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date du document',
        ),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createDocument(
                titre: titreController.text.trim(),
                categorie: categorie,
                sens: sens,
                reference: _opt(referenceController),
                description: _opt(descriptionController),
                dateDocument: _opt(dateController),
              );
          if (mounted) showSuccess(context, 'Document créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _supprimer(GouvernanceDocument document) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le document « ${document.titre} » ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteDocument(document.id);
      if (mounted) showSuccess(context, 'Document supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) {
            _query = v.trim();
            _refresh();
          },
          label: 'Rechercher un document',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String?>(
                  value: _categorie,
                  isExpanded: true,
                  items: _categories.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, style: const TextStyle(fontSize: 13.5)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    _categorie = v;
                    _refresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String?>(
                  value: _sens,
                  isExpanded: true,
                  items: _sensOptions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, style: const TextStyle(fontSize: 13.5)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    _sens = v;
                    _refresh();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<GouvernanceDocument>>(
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
              final items = snapshot.data!;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onVideChange?.call(items.isEmpty);
              });
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.folder_outlined,
                  // État vide de la maquette, écran 7.
                  message: 'Aucun document classé\nStatuts, règlements et décisions officielles se classent ici.',
                  actionLabel: 'Ajouter un document',
                  onAction: creer,
                );
              }
              return ListeAvecFab(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final d = items[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.folder_outlined),
                        ),
                        title: Text(d.titre, style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                          '${d.categorieLabel}'
                          '${d.sens != null ? ' · ${d.sensLabel}' : ''}'
                          '${d.reference != null ? ' · ${d.reference}' : ''}'
                          '${d.dateDocument != null ? ' · ${afficherDate(d.dateDocument)}' : ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () => _supprimer(d),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
