import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/cultes.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'qr_scan_screen.dart';

/// Module 3 — Feuille de présence : choix du culte, pointage par
/// matricule, liste des présents et statistiques.
class PresencesScreen extends StatefulWidget {
  const PresencesScreen({super.key});

  @override
  State<PresencesScreen> createState() => _PresencesScreenState();
}

class _PresencesScreenState extends State<PresencesScreen> {
  final _matriculeController = TextEditingController();
  final _searchController = TextEditingController();
  String _query = '';
  String? _culteId;

  late Future<PresenceStats> _statsFuture;
  late Future<List<Culte>> _cultesFuture;
  Future<List<Presence>>? _presencesFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = context.read<AppState>().api.getPresenceStats();
    _cultesFuture = context.read<AppState>().api.getCultes();
  }

  @override
  void dispose() {
    _matriculeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _statsFuture = context.read<AppState>().api.getPresenceStats();
      if (_culteId != null) {
        _presencesFuture =
            context.read<AppState>().api.getPresences(culteId: _culteId);
      }
    });
  }

  Future<void> _pointer() async {
    final matricule = _matriculeController.text.trim();
    if (matricule.isEmpty || _culteId == null) {
      showApiError(context, 'Choisissez un culte et saisissez un matricule.');
      return;
    }
    try {
      await context.read<AppState>().api.pointerPresence(
            matricule: matricule,
            culteId: _culteId,
            statut: 'present',
            mode: 'manuel',
          );
      if (mounted) showSuccess(context, 'Présence pointée.');
      _matriculeController.clear();
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _scanner() async {
    if (_culteId == null) {
      showApiError(context, 'Choisissez d’abord un culte.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => QrScanScreen(culteId: _culteId!),
      ),
    );
    if (mounted) _refresh();
  }

  Color _statutColor(String statut) {
    switch (statut) {
      case 'present':
        return AppTheme.vertFonce;
      case 'absent':
        return AppTheme.rougeErreur;
      case 'excuse':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _statutLabel(String statut) {
    switch (statut) {
      case 'present':
        return 'Présent';
      case 'absent':
        return 'Absent';
      case 'excuse':
        return 'Excusé';
      default:
        return statut;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Présences'),
      ),
      body: Column(
        children: [
          FutureBuilder<PresenceStats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: AppLoading(),
                );
              }
              if (snapshot.hasError) {
                return AppError(
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                );
              }
              final stats = snapshot.data!;
              final total = stats.total;
              final taux = total > 0
                  ? '${((stats.presents / total) * 100).round()} %'
                  : '—';
              return Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        constraints.maxWidth > 600 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          label: 'Pointages',
                          value: '$total',
                          icon: Icons.how_to_reg_outlined,
                        ),
                        StatCard(
                          label: 'Présents',
                          value: '${stats.presents}',
                          icon: Icons.check_circle_outline,
                          color: AppTheme.vertFonce,
                        ),
                        StatCard(
                          label: 'Absents',
                          value: '${stats.absents}',
                          icon: Icons.cancel_outlined,
                          color: AppTheme.rougeErreur,
                        ),
                        StatCard(
                          label: 'Taux de présence',
                          value: taux,
                          icon: Icons.percent_outlined,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FutureBuilder<List<Culte>>(
              future: _cultesFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppError(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                final cultes = snapshot.data ?? const <Culte>[];
                return DropdownButtonFormField<String>(
                  initialValue: _culteId,
                  decoration: const InputDecoration(
                    labelText: 'Culte',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: cultes
                      .map((c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(
                                '${c.titre} — ${afficherDateTime(c.dateHeure)}'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _culteId = value;
                      _presencesFuture = value == null
                          ? null
                          : context
                              .read<AppState>()
                              .api
                              .getPresences(culteId: value);
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            // En largeur étroite, champ seul sur une ligne, boutons QR et
            // « Pointer » sur la suivante : la rangée rigide coupait le
            // bouton QR pris entre le champ et « Pointer ».
            child: LayoutBuilder(
              builder: (context, constraints) {
                final field = TextField(
                  controller: _matriculeController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _pointer(),
                  decoration: const InputDecoration(
                    labelText: 'Matricule du membre',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                );
                final qrButton = IconButton.outlined(
                  onPressed: _scanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scanner une carte',
                );
                final pointerButton = FilledButton(
                  onPressed: _pointer,
                  child: const Text('Pointer'),
                );
                if (constraints.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          qrButton,
                          const SizedBox(width: 8),
                          Expanded(child: pointerButton),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 8),
                    qrButton,
                    const SizedBox(width: 8),
                    pointerButton,
                  ],
                );
              },
            ),
          ),
          searchField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim()),
            label: 'Rechercher un présent',
          ),
          Expanded(
            child: _presencesFuture == null
                ? const EmptyState(
                    icon: Icons.how_to_reg_outlined,
                    message: 'Choisissez un culte pour voir sa feuille de présence.',
                  )
                : FutureBuilder<List<Presence>>(
                    future: _presencesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const AppLoading();
                      }
                      if (snapshot.hasError) {
                        return AppError(
                          message: snapshot.error.toString(),
                          onRetry: _refresh,
                        );
                      }
                      final items = snapshot.data!
                          .where((p) =>
                              _query.isEmpty ||
                              (p.membreNom ?? '')
                                  .toLowerCase()
                                  .contains(_query.toLowerCase()) ||
                              p.memberId
                                  .toLowerCase()
                                  .contains(_query.toLowerCase()))
                          .toList();
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.how_to_reg_outlined,
                          message: snapshot.data!.isEmpty
                              ? 'Aucune présence pointée pour ce culte pour l’instant.'
                              : 'Aucune présence ne correspond à la recherche.',
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
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(p.membreNom ?? p.memberId),
                              subtitle: Text(
                                afficherDateTime(p.pointeAt),
                              ),
                              trailing: StatusChip(
                                label: _statutLabel(p.statut),
                                color: _statutColor(p.statut),
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
    );
  }
}
