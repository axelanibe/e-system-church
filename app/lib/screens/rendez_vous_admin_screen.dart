import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Rendez-vous côté admin (extrait du Suivi pastoral, tranche T6) :
/// les demandes des membres et les créneaux pastoraux, avec
/// confirmation, refus ou annulation. Une seule entrée par fonction :
/// le tiroir ouvre cet écran, le Suivi pastoral garde le radar, les
/// parcours, les visites et les accompagnements.
class RendezVousAdminScreen extends StatefulWidget {
  const RendezVousAdminScreen({super.key});

  @override
  State<RendezVousAdminScreen> createState() =>
      _RendezVousAdminScreenState();
}

const _rdvStatuts = {
  'en_attente': 'En attente',
  'confirme': 'Confirmé',
  'refuse': 'Refusé',
  'annule': 'Annulé',
};

class _RendezVousAdminScreenState extends State<RendezVousAdminScreen> {
  String? _statut;
  late Future<List<RendezVous>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getRendezVousAdmin();
  }

  void _refresh() {
    setState(() {
      _future = context
          .read<AppState>()
          .api
          .getRendezVousAdmin(statut: _statut);
    });
  }

  Future<void> _changerStatut(RendezVous rdv, String statut) async {
    final api = context.read<AppState>().api;
    String? creneau;
    if (statut == 'confirme') {
      final creneauController = TextEditingController();
      await showCreateDialog(
        context: context,
        title: 'Confirmer le rendez-vous',
        saveLabel: 'Confirmer',
        fields: [
          dialogTextField(
            controller: creneauController,
            label: 'Créneau confirmé',
            hintText: 'Ex. Samedi 10 h',
          ),
        ],
        isValid: () => creneauController.text.trim().isNotEmpty,
        onSave: () async {
          creneau = creneauController.text.trim();
        },
      );
      if (creneau == null) return;
    }
    try {
      await api.setRendezVousStatut(
        rdv.id,
        statut,
        creneau: creneau,
      );
      if (mounted) {
        showSuccess(
            context, 'Rendez-vous ${_rdvStatuts[statut]!.toLowerCase()}.');
      }
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _showRendezVous(RendezVous rdv) async {
    final nom = rdv.membreNom ?? rdv.memberId ?? '—';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(nom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date souhaitée : ${afficherDate(rdv.dateSouhaitee)}'),
            if (rdv.creneau != null) Text('Créneau : ${rdv.creneau}'),
            Text('Motif : ${rdv.motif}'),
            Text('Statut : ${_rdvStatuts[rdv.statut] ?? rdv.statut}'),
          ],
        ),
        actions: [
          if (rdv.statut == 'en_attente') ...[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _changerStatut(rdv, 'confirme');
              },
              child: const Text('Confirmer'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _changerStatut(rdv, 'refuse');
              },
              child: const Text('Refuser'),
            ),
          ],
          if (rdv.statut == 'confirme')
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _changerStatut(rdv, 'annule');
              },
              child: const Text('Annuler'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rendez-vous')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in <(String?, String)>[
                    (null, 'Tous'),
                    for (final e in _rdvStatuts.entries) (e.key, e.value),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _statut == entry.$1,
                        onSelected: (_) {
                          setState(() => _statut = entry.$1);
                          _refresh();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RendezVous>>(
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
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.calendar_month_outlined,
                    message: 'Aucun rendez-vous pour l’instant.',
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
                          child: Icon(Icons.calendar_month_outlined),
                        ),
                        title: Text(r.membreNom ?? r.memberId ?? '—'),
                        subtitle: Text(
                          '${afficherDate(r.dateSouhaitee)}'
                          '${r.creneau != null ? ' · ${r.creneau}' : ''} · ${r.motif}',
                        ),
                        trailing: StatusChip(
                          label: _rdvStatuts[r.statut] ?? r.statut,
                          color: r.statut == 'confirme'
                              ? AppTheme.violetProfond
                              : r.statut == 'en_attente'
                                  ? Colors.orange
                                  : AppTheme.rougeErreur,
                        ),
                        onTap: () => _showRendezVous(r),
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
