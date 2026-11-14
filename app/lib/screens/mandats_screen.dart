import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/gouvernance.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// T10 — Mandats et nominations : les mandats en cours d'un côté,
/// l'historique des nominations de l'autre. Une nomination est un
/// mandat, sa décision est gardée quand elle existe.
class MandatsScreen extends StatefulWidget {
  final int ongletInitial;

  const MandatsScreen({super.key, this.ongletInitial = 0});

  @override
  State<MandatsScreen> createState() => _MandatsScreenState();
}

class _MandatsScreenState extends State<MandatsScreen> {
  int _tab = 0;
  late Future<List<Mandat>> _enCoursFuture;
  late Future<List<Mandat>> _tousFuture;
  late Future<MemberPage> _membresFuture;
  late Future<List<Decision>> _decisionsFuture;

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletInitial;
    final api = context.read<AppState>().api;
    _enCoursFuture = api.getMandats(statut: 'en_cours');
    _tousFuture = api.getMandats();
    _membresFuture = api.getMembers();
    _decisionsFuture = api.getDecisions();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _enCoursFuture = api.getMandats(statut: 'en_cours');
      _tousFuture = api.getMandats();
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createMandat(List<Member> membres, List<Decision> decisions) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String? decisionId;
    final fonctionController = TextEditingController();
    final debutController = TextEditingController();
    final finController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau mandat',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre',
          options: {for (final m in membres) m.id: '${m.fullName} (${m.matricule})'},
          onChanged: (v) => memberId = v,
        ),
        dialogTextField(controller: fonctionController, label: 'Fonction'),
        dialogDateField(
          context: context,
          controller: debutController,
          label: 'Date de début',
        ),
        dialogDateField(
          context: context,
          controller: finController,
          label: 'Date de fin (facultative)',
        ),
        dialogDropdown<String?>(
          value: decisionId,
          label: 'Décision de nomination',
          options: {
            null: 'Aucune',
            for (final d in decisions) d.id: d.titre,
          },
          onChanged: (v) => decisionId = v,
        ),
      ],
      isValid: () =>
          memberId != null &&
          fonctionController.text.trim().isNotEmpty &&
          debutController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMandat(
                memberId: memberId!,
                fonction: fonctionController.text.trim(),
                dateDebut: debutController.text.trim(),
                dateFin: _opt(finController),
                decisionId: decisionId,
              );
          if (mounted) showSuccess(context, 'Mandat créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _terminer(Mandat mandat) async {
    try {
      await context.read<AppState>().api.terminerMandat(mandat.id);
      if (mounted) showSuccess(context, 'Mandat terminé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimer(Mandat mandat, Map<String, String> noms) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le mandat de ${noms[mandat.memberId] ?? 'ce membre'} (${mandat.fonction}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteMandat(mandat.id);
      if (mounted) showSuccess(context, 'Mandat supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _liste(Future<List<Mandat>> future, Map<String, String> noms) {
    return FutureBuilder<List<Mandat>>(
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.verified_outlined,
            message: _tab == 0
                ? 'Aucun mandat en cours.'
                : 'Aucune nomination.',
            actionLabel: 'Créer un mandat',
            onAction: () async {
              try {
                final membres = (await _membresFuture).membres;
                final decisions = await _decisionsFuture;
                if (mounted) await _createMandat(membres, decisions);
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
                  child: Icon(Icons.verified_outlined),
                ),
                title: Text(noms[m.memberId] ?? 'Membre'),
                subtitle: Text(
                  '${m.fonction} · ${afficherDate(m.dateDebut)}'
                  '${m.dateFin != null ? ' — ${afficherDate(m.dateFin)}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: m.statutLabel,
                      color: m.enCours ? AppTheme.bleuNuit : Colors.grey,
                    ),
                    if (m.enCours)
                      IconButton(
                        icon: const Icon(Icons.check_outlined),
                        tooltip: 'Terminer le mandat',
                        onPressed: () => _terminer(m),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimer(m, noms),
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
      length: 2,
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mandats et nominations'),
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Mandats en cours'),
              Tab(text: 'Nominations'),
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
                _liste(_enCoursFuture, noms),
                _liste(_tousFuture, noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final membres = (await _membresFuture).membres;
              final decisions = await _decisionsFuture;
              if (mounted) await _createMandat(membres, decisions);
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
