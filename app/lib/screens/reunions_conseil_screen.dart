import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/gouvernance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';

/// T10 — Réunions du conseil et décisions. Les procès-verbaux ont
/// déménagé dans le hub Mandats et nominations (maquette, écran 7) :
/// cet écran ne garde que ses 2 premiers onglets. Plus aucune carte
/// de Gouvernance n'y pointe : il reste joignable par son nom, à
/// retirer si personne ne le rouvre.
class ReunionsConseilScreen extends StatefulWidget {
  final int ongletInitial;

  const ReunionsConseilScreen({super.key, this.ongletInitial = 0});

  @override
  State<ReunionsConseilScreen> createState() => _ReunionsConseilScreenState();
}

class _ReunionsConseilScreenState extends State<ReunionsConseilScreen> {
  int _tab = 0;

  // L'onglet actif est-il vide ? Sert à masquer le FAB quand l'état
  // vide affiche déjà le bouton de création (un seul bouton).
  bool _reunionsVides = false;
  bool _decisionsVides = false;
  late Future<List<ReunionConseil>> _reunionsFuture;
  late Future<List<Decision>> _decisionsFuture;

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletInitial.clamp(0, 1);
    final api = context.read<AppState>().api;
    _reunionsFuture = api.getReunionsConseil();
    _decisionsFuture = api.getDecisions();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _reunionsFuture = api.getReunionsConseil();
      if (_tab == 1) _decisionsFuture = api.getDecisions();
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createReunion() async {
    final titreController = TextEditingController();
    final dateController = TextEditingController();
    final lieuController = TextEditingController();
    final ordreController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle réunion',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(controller: dateController, label: 'Date et heure'),
        dialogTextField(controller: lieuController, label: 'Lieu'),
        dialogTextField(
          controller: ordreController,
          label: 'Ordre du jour',
          maxLines: 3,
        ),
      ],
      isValid: () =>
          titreController.text.trim().isNotEmpty &&
          dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createReunionConseil(
                titre: titreController.text.trim(),
                dateReunion: dateController.text.trim(),
                lieu: _opt(lieuController),
                ordreDuJour: _opt(ordreController),
              );
          if (mounted) showSuccess(context, 'Réunion créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createDecision(List<ReunionConseil> reunions) async {
    String? reunionId = reunions.isEmpty ? null : reunions.first.id;
    final titreController = TextEditingController();
    final descriptionController = TextEditingController();
    final dateController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle décision',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: reunionId,
          label: 'Réunion',
          options: {
            null: 'Aucune',
            for (final r in reunions) r.id: r.titre,
          },
          onChanged: (v) => reunionId = v,
        ),
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date de la décision',
        ),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createDecision(
                reunionId: reunionId,
                titre: titreController.text.trim(),
                description: _opt(descriptionController),
                dateDecision: _opt(dateController),
              );
          if (mounted) showSuccess(context, 'Décision créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }



  Future<void> _supprimerReunion(ReunionConseil reunion) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la réunion « ${reunion.titre} » ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteReunionConseil(reunion.id);
      if (mounted) showSuccess(context, 'Réunion supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerDecision(Decision decision) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la décision « ${decision.titre} » ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteDecision(decision.id);
      if (mounted) showSuccess(context, 'Décision supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }


  Widget _reunionsTab() {
    return FutureBuilder<List<ReunionConseil>>(
      future: _reunionsFuture,
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
        if (items.isEmpty != _reunionsVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _reunionsVides != items.isEmpty) {
              setState(() => _reunionsVides = items.isEmpty);
            }
          });
        }
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.event_available_outlined,
            message: 'Aucune réunion.',
            actionLabel: 'Créer une réunion',
            onAction: _createReunion,
          );
        }
        return ListeAvecFab(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final r = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.event_available_outlined),
                ),
                title: Text(r.titre, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${afficherDateTime(r.dateReunion)}'
                  '${r.lieu != null ? ' · ${r.lieu}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: r.statutLabel,
                      color: r.statut == 'annulee'
                          ? AppTheme.rougeErreur
                          : AppTheme.violetProfond,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerReunion(r),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        );
      },
    );
  }

  Widget _decisionsTab(Map<String, String> reunionsNoms) {
    return FutureBuilder<List<Decision>>(
      future: _decisionsFuture,
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
        if (items.isEmpty != _decisionsVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _decisionsVides != items.isEmpty) {
              setState(() => _decisionsVides = items.isEmpty);
            }
          });
        }
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.gavel_outlined,
            message: 'Aucune décision.',
            actionLabel: 'Créer une décision',
            onAction: () async {
              try {
                final reunions = await _reunionsFuture;
                if (mounted) await _createDecision(reunions);
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
              itemCount: items.length,
              itemBuilder: (context, index) {
                final d = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.gavel_outlined),
                ),
                title: Text(d.titre, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${d.reunionId != null ? '${reunionsNoms[d.reunionId] ?? '—'} · ' : ''}'
                  '${d.dateDecision != null ? afficherDate(d.dateDecision) : 'Date à compléter'}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: d.statutLabel,
                      color: d.statut == 'rejetee'
                          ? AppTheme.rougeErreur
                          : AppTheme.violetProfond,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerDecision(d),
                    ),
                  ],
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
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conseil et décisions'),
          bottom: TabBar(
            isScrollable: true,
            labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Réunions'),
              Tab(text: 'Décisions'),
            ],
          ),
        ),
        body: FutureBuilder<List<ReunionConseil>>(
          future: _reunionsFuture,
          builder: (context, reunionsSnapshot) {
            if (reunionsSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const AppLoading();
            }
            if (reunionsSnapshot.hasError) {
              return AppError(
                message: reunionsSnapshot.error.toString(),
                onRetry: _refresh,
              );
            }
            final reunionsNoms = {
              for (final r in reunionsSnapshot.data!) r.id: r.titre
            };
            return TabBarView(
              children: [
                _reunionsTab(),
                _decisionsTab(reunionsNoms),
              ],
            );
          },
        ),
        floatingActionButton: ((_tab == 0 && _reunionsVides) ||
                (_tab == 1 && _decisionsVides))
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    final reunions = await _reunionsFuture;
                    if (!mounted) return;
                    if (_tab == 0) {
                      await _createReunion();
                    } else {
                      await _createDecision(reunions);
                    }
                  } catch (e) {
                    if (context.mounted) showApiError(context, e);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Ajouter', style: TextStyle(fontSize: 13.5)),
              ),
      ),
    );
  }
}
