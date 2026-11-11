import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../models/prieres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 5 — Demandes de prière et messages internes.
class PrieresScreen extends StatefulWidget {
  const PrieresScreen({super.key});

  @override
  State<PrieresScreen> createState() => _PrieresScreenState();
}

class _PrieresScreenState extends State<PrieresScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';
  String? _statutFilter;

  late Future<List<DemandePriere>> _demandesFuture;
  late Future<List<MessageInterne>> _messagesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _demandesFuture = api.getDemandesPriere();
    _messagesFuture = api.getMessagesInternes();
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
        _demandesFuture = api.getDemandesPriere(statut: _statutFilter);
      } else {
        _messagesFuture = api.getMessagesInternes();
      }
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Color _demandeColor(String statut) {
    switch (statut) {
      case 'nouvelle':
        return Colors.orange;
      case 'en_cours':
        return Colors.blue;
      case 'terminee':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _demandeLabel(String statut) {
    switch (statut) {
      case 'nouvelle':
        return 'Nouvelle';
      case 'en_cours':
        return 'En cours';
      case 'terminee':
        return 'Terminée';
      default:
        return statut;
    }
  }

  Future<void> _createDemande(List<Member> membres) async {
    final sujetController = TextEditingController();
    final demandeurController = TextEditingController();
    final detailsController = TextEditingController();
    String? memberId;
    bool confidentiel = false;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle demande de prière',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: sujetController, label: 'Sujet'),
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre concerné',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogTextField(
            controller: demandeurController, label: 'Nom du demandeur'),
        dialogTextField(
          controller: detailsController,
          label: 'Détails',
          maxLines: 3,
        ),
        StatefulBuilder(
          builder: (context, setDialogState) => CheckboxListTile(
            title: const Text('Confidentiel'),
            value: confidentiel,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) =>
                setDialogState(() => confidentiel = v ?? false),
          ),
        ),
      ],
      isValid: () => sujetController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createDemandePriere(
                sujet: sujetController.text.trim(),
                memberId: memberId,
                demandeurNom: demandeurController.text.trim().isEmpty
                    ? null
                    : demandeurController.text.trim(),
                details: detailsController.text.trim().isEmpty
                    ? null
                    : detailsController.text.trim(),
                confidentiel: confidentiel,
              );
          if (mounted) showSuccess(context, 'Demande de prière créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _setDemandeStatut(
      DemandePriere demande, String statut) async {
    try {
      await context
          .read<AppState>()
          .api
          .setDemandePriereStatut(demande.id, statut);
      if (mounted) showSuccess(context, 'Demande mise à jour.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _createMessage(List<Member> membres) async {
    final sujetController = TextEditingController();
    final corpsController = TextEditingController();
    String? destinataireId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau message interne',
      saveLabel: 'Envoyer',
      fields: [
        dialogTextField(controller: sujetController, label: 'Sujet'),
        dialogDropdown<String?>(
          value: destinataireId,
          label: 'Destinataire',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => destinataireId = v,
        ),
        dialogTextField(
          controller: corpsController,
          label: 'Message',
          maxLines: 4,
        ),
      ],
      isValid: () =>
          sujetController.text.trim().isNotEmpty &&
          corpsController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMessageInterne(
                sujet: sujetController.text.trim(),
                corps: corpsController.text.trim(),
                destinataireId: destinataireId,
              );
          if (mounted) showSuccess(context, 'Message envoyé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Widget _demandesTab(List<Member> membres) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une demande de prière',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in <String, String?>{
                  'Toutes': null,
                  'Nouvelles': 'nouvelle',
                  'En cours': 'en_cours',
                  'Terminées': 'terminee',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(entry.key),
                      selected: _statutFilter == entry.value,
                      onSelected: (_) {
                        setState(() {
                          _statutFilter = entry.value;
                          _demandesFuture = context
                              .read<AppState>()
                              .api
                              .getDemandesPriere(statut: entry.value);
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DemandePriere>>(
            future: _demandesFuture,
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
                  .where((d) => _matches(d.sujet))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune demande de prière pour l’instant.'
                      : 'Aucune demande ne correspond à la recherche.',
                  actionLabel: 'Créer une demande',
                  onAction: () => _createDemande(membres),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final d = items[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.volunteer_activism_outlined),
                        ),
                        title: Text(d.sujet),
                        subtitle: Text(
                          '${d.demandeurNom ?? '—'}'
                          '${d.confidentiel ? ' · Confidentiel' : ''}'
                          '${d.details != null ? ' · ${d.details}' : ''}'
                          ' · ${afficherDateTime(d.createdAt)}',
                        ),
                        trailing: StatusChip(
                          label: _demandeLabel(d.statut),
                          color: _demandeColor(d.statut),
                        ),
                        onTap: () async {
                          String? choix;
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(d.sujet),
                              content: Text(
                                  'Statut actuel : ${_demandeLabel(d.statut)}'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Fermer'),
                                ),
                                if (d.statut != 'en_cours')
                                  TextButton(
                                    onPressed: () {
                                      choix = 'en_cours';
                                      Navigator.of(ctx).pop();
                                    },
                                    child: const Text('Passer en cours'),
                                  ),
                                if (d.statut != 'terminee')
                                  TextButton(
                                    onPressed: () {
                                      choix = 'terminee';
                                      Navigator.of(ctx).pop();
                                    },
                                    child: const Text('Marquer terminée'),
                                  ),
                              ],
                            ),
                          );
                          if (choix != null) {
                            await _setDemandeStatut(d, choix!);
                          }
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _messagesTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un message',
        ),
        Expanded(
          child: FutureBuilder<List<MessageInterne>>(
            future: _messagesFuture,
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
                  .where((m) => _matches(m.sujet))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.mail_outline,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun message interne pour l’instant.'
                      : 'Aucun message ne correspond à la recherche.',
                  actionLabel: 'Écrire un message',
                  onAction: () => _createMessage(membres),
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
                        child: Icon(Icons.mail_outline),
                      ),
                      title: Text(m.sujet),
                      subtitle: Text(
                        '${m.destinataireId != null ? 'À : ${noms[m.destinataireId] ?? '—'} · ' : ''}${m.corps} · ${afficherDateTime(m.createdAt)}',
                      ),
                    );
                  },
                ),
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
          title: const Text('Prières & messages'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Demandes de prière'),
              Tab(text: 'Messages internes'),
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
            final membres = snapshot.data!.membres;
            return TabBarView(
              children: [
                _demandesTab(membres),
                _messagesTab(membres),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              final membres = (await _membresFuture).membres;
              if (!mounted) return;
              if (_tab == 0) {
                await _createDemande(membres);
              } else {
                await _createMessage(membres);
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0 ? 'Demande' : 'Message'),
        ),
      ),
    );
  }
}
