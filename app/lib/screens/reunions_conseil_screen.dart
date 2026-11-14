import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/gouvernance.dart';
import '../models/parametres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// T10 — Réunions du conseil, décisions et procès-verbaux. Le
/// signataire d'un procès-verbal est prérempli depuis les paramètres
/// de l'église quand il est renseigné, sinon il reste à compléter.
class ReunionsConseilScreen extends StatefulWidget {
  final int ongletInitial;

  const ReunionsConseilScreen({super.key, this.ongletInitial = 0});

  @override
  State<ReunionsConseilScreen> createState() => _ReunionsConseilScreenState();
}

class _ReunionsConseilScreenState extends State<ReunionsConseilScreen> {
  int _tab = 0;
  late Future<List<ReunionConseil>> _reunionsFuture;
  late Future<List<Decision>> _decisionsFuture;
  late Future<List<ProcesVerbal>> _pvFuture;
  late Future<EgliseParametres> _parametresFuture;

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletInitial;
    final api = context.read<AppState>().api;
    _reunionsFuture = api.getReunionsConseil();
    _decisionsFuture = api.getDecisions();
    _pvFuture = api.getProcesVerbaux();
    _parametresFuture = api.getParametres();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _reunionsFuture = api.getReunionsConseil();
      if (_tab == 1) _decisionsFuture = api.getDecisions();
      if (_tab == 2) _pvFuture = api.getProcesVerbaux();
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

  Future<void> _createPv(
    List<ReunionConseil> reunions,
    String? signataireDefaut,
  ) async {
    String? reunionId = reunions.isEmpty ? null : reunions.first.id;
    final numeroController = TextEditingController();
    final contenuController = TextEditingController();
    final dateController = TextEditingController();
    final signataireController =
        TextEditingController(text: signataireDefaut ?? '');
    await showCreateDialog(
      context: context,
      title: 'Nouveau procès-verbal',
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
        dialogTextField(controller: numeroController, label: 'Numéro'),
        dialogTextField(
          controller: contenuController,
          label: 'Contenu',
          maxLines: 5,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date du procès-verbal',
        ),
        dialogTextField(
          controller: signataireController,
          label: 'Signataire',
        ),
      ],
      isValid: () => contenuController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createProcesVerbal(
                reunionId: reunionId,
                numero: _opt(numeroController),
                contenu: contenuController.text.trim(),
                datePv: _opt(dateController),
                signataire: _opt(signataireController),
              );
          if (mounted) showSuccess(context, 'Procès-verbal créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _signer(ProcesVerbal pv, String? signataireDefaut) async {
    final signataireController = TextEditingController(
      text: pv.signataire ?? signataireDefaut ?? '',
    );
    await showCreateDialog(
      context: context,
      title: 'Signer le procès-verbal',
      saveLabel: 'Signer',
      fields: [
        dialogTextField(
          controller: signataireController,
          label: 'Signataire',
        ),
      ],
      isValid: () => signataireController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.signerProcesVerbal(
                pv.id,
                signataire: signataireController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Procès-verbal signé.');
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

  Future<void> _supprimerPv(ProcesVerbal pv) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le procès-verbal « ${pv.numero ?? 'sans numéro'} » ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteProcesVerbal(pv.id);
      if (mounted) showSuccess(context, 'Procès-verbal supprimé.');
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
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.event_available_outlined,
            message: 'Aucune réunion du conseil pour l’instant.',
            actionLabel: 'Créer une réunion',
            onAction: _createReunion,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final r = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.event_available_outlined),
                ),
                title: Text(r.titre),
                subtitle: Text(
                  '${afficherDateTime(r.dateReunion)}'
                  '${r.lieu != null ? ' · ${r.lieu}' : ''}',
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
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.gavel_outlined,
            message: 'Aucune décision pour l’instant.',
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
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final d = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.gavel_outlined),
                ),
                title: Text(d.titre),
                subtitle: Text(
                  '${d.reunionId != null ? '${reunionsNoms[d.reunionId] ?? '—'} · ' : ''}'
                  '${d.dateDecision != null ? afficherDate(d.dateDecision) : 'Date à compléter'}',
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
        );
      },
    );
  }

  Widget _pvTab(Map<String, String> reunionsNoms, String? signataireDefaut) {
    return FutureBuilder<List<ProcesVerbal>>(
      future: _pvFuture,
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
            icon: Icons.description_outlined,
            message: 'Aucun procès-verbal pour l’instant.',
            actionLabel: 'Créer un procès-verbal',
            onAction: () async {
              try {
                final reunions = await _reunionsFuture;
                if (mounted) await _createPv(reunions, signataireDefaut);
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
              final pv = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.description_outlined),
                ),
                title: Text(pv.numero ?? 'Sans numéro'),
                subtitle: Text(
                  '${pv.reunionId != null ? '${reunionsNoms[pv.reunionId] ?? '—'} · ' : ''}'
                  '${pv.datePv != null ? afficherDate(pv.datePv) : 'Date à compléter'}'
                  '${pv.signataire != null ? ' · ${pv.signataire}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: pv.statutLabel,
                      color: pv.statut == 'signe'
                          ? AppTheme.violetProfond
                          : Colors.grey,
                    ),
                    if (pv.statut == 'brouillon')
                      IconButton(
                        icon: const Icon(Icons.draw_outlined),
                        tooltip: 'Signer',
                        onPressed: () => _signer(pv, signataireDefaut),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerPv(pv),
                    ),
                  ],
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
      length: 3,
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conseil et procès-verbaux'),
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Réunions'),
              Tab(text: 'Décisions'),
              Tab(text: 'Procès-verbaux'),
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
            return FutureBuilder<EgliseParametres>(
              future: _parametresFuture,
              builder: (context, paramsSnapshot) {
                final signataireDefaut =
                    paramsSnapshot.data?.signataireProcesVerbaux;
                return TabBarView(
                  children: [
                    _reunionsTab(),
                    _decisionsTab(reunionsNoms),
                    _pvTab(reunionsNoms, signataireDefaut),
                  ],
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final reunions = await _reunionsFuture;
              if (!mounted) return;
              if (_tab == 0) {
                await _createReunion();
              } else if (_tab == 1) {
                await _createDecision(reunions);
              } else {
                final params = await _parametresFuture;
                if (mounted) {
                  await _createPv(reunions, params.signataireProcesVerbaux);
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
