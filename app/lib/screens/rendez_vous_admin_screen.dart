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

/// Périodes des créneaux du pasteur (migration 033, E-RV1), dans
/// l'ordre de la Projection : matin, après-midi, soir.
const _periodesCreneau = {
  'matin': 'Matin',
  'apres-midi': 'Après-midi',
  'soir': 'Soir',
};

class _RendezVousAdminScreenState extends State<RendezVousAdminScreen> {
  String? _statut;
  late Future<List<RendezVous>> _future;
  late Future<List<CreneauPasteur>> _creneauxFuture;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getRendezVousAdmin();
    _creneauxFuture = context.read<AppState>().api.getCreneauxPasteur();
  }

  void _refresh() {
    setState(() {
      _future = context
          .read<AppState>()
          .api
          .getRendezVousAdmin(statut: _statut);
    });
  }

  void _refreshCreneaux() {
    setState(() {
      _creneauxFuture = context.read<AppState>().api.getCreneauxPasteur();
    });
  }

  Future<void> _ajouterCreneau() async {
    String? periode;
    final libelleController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Ajouter un créneau',
      saveLabel: 'Ajouter',
      fields: [
        dialogDropdown<String>(
          value: periode,
          label: 'Période',
          options: _periodesCreneau,
          onChanged: (v) => periode = v,
        ),
        dialogTextField(
          controller: libelleController,
          label: 'Libellé du créneau',
        ),
      ],
      isValid: () =>
          periode != null &&
          libelleController.text.trim().isNotEmpty &&
          libelleController.text.trim().length <= 50,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCreneau(
                periode: periode!,
                libelle: libelleController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Créneau ajouté.');
          _refreshCreneaux();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _modifierCreneau(CreneauPasteur creneau) async {
    var periode = creneau.periode;
    final libelleController =
        TextEditingController(text: creneau.libelle);
    await showCreateDialog(
      context: context,
      title: 'Modifier le créneau',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String>(
          value: periode,
          label: 'Période',
          options: _periodesCreneau,
          onChanged: (v) => periode = v ?? periode,
        ),
        dialogTextField(
          controller: libelleController,
          label: 'Libellé du créneau',
        ),
      ],
      isValid: () =>
          libelleController.text.trim().isNotEmpty &&
          libelleController.text.trim().length <= 50,
      onSave: () async {
        try {
          await context.read<AppState>().api.updateCreneau(
                creneau.id,
                periode: periode,
                libelle: libelleController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Créneau modifié.');
          _refreshCreneaux();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _supprimerCreneau(CreneauPasteur creneau) async {
    final api = context.read<AppState>().api;
    final confirme = await confirmDelete(
      context,
      'Supprimer le créneau « ${creneau.libelle} » ?',
    );
    if (!confirme) return;
    try {
      await api.deleteCreneau(creneau.id);
      if (mounted) showSuccess(context, 'Créneau supprimé.');
      _refreshCreneaux();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _basculerCreneau(CreneauPasteur creneau) async {
    try {
      await context
          .read<AppState>()
          .api
          .updateCreneau(creneau.id, actif: !creneau.actif);
      _refreshCreneaux();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _changerStatut(RendezVous rdv, String statut) async {
    final api = context.read<AppState>().api;
    String? creneau;
    if (statut == 'confirme') {
      final creneauController =
          TextEditingController(text: rdv.creneau ?? '');
      await showCreateDialog(
        context: context,
        title: 'Confirmer le rendez-vous',
        saveLabel: 'Confirmer',
        fields: [
          dialogTextField(
            controller: creneauController,
            label: 'Créneau confirmé',
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

  Widget _sectionCreneaux() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mes créneaux',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _ajouterCreneau,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un créneau'),
                  ),
                ],
              ),
              FutureBuilder<List<CreneauPasteur>>(
                future: _creneauxFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        snapshot.error.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    );
                  }
                  final creneaux = snapshot.data!;
                  if (creneaux.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Aucun créneau défini.'),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final periode
                              in _periodesCreneau.keys)
                            if (creneaux.any(
                                (c) => c.periode == periode)) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _periodesCreneau[periode]!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall,
                                ),
                              ),
                              for (final c in creneaux.where(
                                  (c) => c.periode == periode))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(
                                    c.libelle,
                                    style: c.actif
                                        ? null
                                        : TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: c.actif
                                            ? 'Désactiver'
                                            : 'Activer',
                                        icon: Icon(
                                          c.actif
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () =>
                                            _basculerCreneau(c),
                                      ),
                                      IconButton(
                                        tooltip: 'Modifier',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            _modifierCreneau(c),
                                      ),
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        icon: const Icon(
                                            Icons.delete_outlined),
                                        onPressed: () =>
                                            _supprimerCreneau(c),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rendez-vous')),
      body: Column(
        children: [
          _sectionCreneaux(),
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
                    message: 'Aucun rendez-vous',
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
