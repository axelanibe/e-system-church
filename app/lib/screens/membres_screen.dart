import 'dart:async';
import '../config/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anniversaire.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'import_membres_screen.dart';

/// Liste des membres de mon église : recherche (nom / matricule) et
/// filtres (département, statut). Le trésorier ne peut pas créer de membre.
class MembresScreen extends StatefulWidget {
  const MembresScreen({super.key});

  @override
  State<MembresScreen> createState() => _MembresScreenState();
}

class _MembresScreenState extends State<MembresScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  /// Recherche tapée, appliquée tout de suite sur la page déjà chargée :
  /// l'API pagine à 50, le filtre local ne remplace donc pas l'appel
  /// serveur, il donne seulement un retour immédiat en attendant.
  String _filtreLocal = '';
  String? _statusFilter;
  String? _departmentFilter;
  List<String>? _departements;
  late Future<MemberPage> _future;
  late Future<List<Anniversaire>> _anniversairesFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _anniversairesFuture =
        context.read<AppState>().api.getAnniversaires(jours: 30);
    context.read<AppState>().api.getDepartements().then((ds) {
      if (mounted) {
        setState(() => _departements = ds.map((d) => d.nom).toList());
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<MemberPage> _load() {
    return context.read<AppState>().api.getMembers(
          q: _query.isEmpty ? null : _query,
          department: _departmentFilter,
          status: _statusFilter,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _deleteMember(Member member) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le membre « ${member.fullName} » (${member.matricule}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteMember(member.id);
      if (mounted) showSuccess(context, 'Membre supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  void _onSearchChanged(String value) {
    // Retour immédiat : on filtre d'abord la page déjà chargée, puis
    // l'appel serveur (temporisé) apporte les résultats complets.
    setState(() => _filtreLocal = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = value.trim();
        _future = _load();
      });
    });
  }

  bool _correspondRecherche(Member m) {
    final q = _filtreLocal.toLowerCase();
    if (q.isEmpty) return true;
    return m.fullName.toLowerCase().contains(q) ||
        m.matricule.toLowerCase().contains(q);
  }

  Future<void> _openForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MemberFormScreen()),
    );
    if (created == true && mounted) {
      showSuccess(context, 'Membre ajouté.');
      _refresh();
    }
  }

  Future<void> _openImport() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportMembresScreen()),
    );
    if (changed == true && mounted) {
      showSuccess(context, 'Import terminé.');
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return AppTheme.bleuNuit;
      case 'nouveau_converti':
        return AppTheme.bleuFonce;
      case 'inactif':
        return Colors.grey;
      case 'ancien':
        return AppTheme.orFonce;
      default:
        return Colors.grey;
    }
  }

  /// Carte des anniversaires proches (30 jours) : la liste seulement,
  /// aucun message envoyé. Masquée quand il n'y en a aucun.
  Widget _anniversairesCard() {
    return FutureBuilder<List<Anniversaire>>(
      future: _anniversairesFuture,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Anniversaire>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cake_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Anniversaires proches (30 jours)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...items.map((a) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(a.fullName.isNotEmpty
                              ? a.fullName[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(a.fullName),
                        subtitle: Text(
                            '${a.matricule} · ${a.ageAtteint} ans'),
                        trailing: Text(
                          a.joursRestants == 0
                              ? "Aujourd'hui"
                              : 'dans ${a.joursRestants} j',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        onTap: () async {
                          try {
                            final membre = await context
                                .read<AppState>()
                                .api
                                .getMember(a.id);
                            if (!context.mounted) return;
                            final changed =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MemberDetailScreen(member: membre),
                              ),
                            );
                            if (changed == true && mounted) _refresh();
                          } catch (e) {
                            if (context.mounted) showApiError(context, e);
                          }
                        },
                      )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Rechercher (nom ou matricule)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _anniversairesCard(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // Retour à la ligne en largeur étroite : en défilement
            // horizontal, le menu « Tous » sortait de l'écran sans indice
            // de défilement. En large, tout tient sur une seule ligne.
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in <String, String?>{
                  'Tous': null,
                  'Actif': 'actif',
                  'Nouveau converti': 'nouveau_converti',
                  'Inactif': 'inactif',
                  'Ancien': 'ancien',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.key),
                    selected: _statusFilter == entry.value,
                    onSelected: (_) {
                      setState(() {
                        _statusFilter = entry.value;
                        _future = _load();
                      });
                    },
                  ),
                DropdownButton<String?>(
                  value: _departmentFilter,
                  hint: const Text('Département'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Tous')),
                    for (final d in _departements ?? const <String>[])
                      DropdownMenuItem(value: d, child: Text(d)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _departmentFilter = value;
                      _future = _load();
                    });
                  },
                ),
                if (state.isAdmin)
                  OutlinedButton.icon(
                    onPressed: _openImport,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Importer'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<MemberPage>(
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
                final page = snapshot.data!;
                final membres =
                    page.membres.where(_correspondRecherche).toList();
                if (membres.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    message: _filtreLocal.isNotEmpty || _query.isNotEmpty
                        ? 'Aucun membre ne correspond à « ${_filtreLocal.isNotEmpty ? _filtreLocal : _query} ».'
                        : 'Aucun membre trouvé.',
                    actionLabel: state.canManageMembers
                        ? 'Ajouter un membre'
                        : null,
                    onAction:
                        state.canManageMembers ? _openForm : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: membres.length,
                    itemBuilder: (context, index) {
                      final member = membres[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(member.fullName.isNotEmpty
                              ? member.fullName[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(member.fullName),
                        subtitle: Text(
                            '${member.matricule} · ${member.department ?? '—'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(
                              label: member.statutAffiche,
                              color: _statusColor(member.estAncien
                                  ? 'ancien'
                                  : member.status),
                            ),
                            if (state.canManageMembers)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Supprimer',
                                onPressed: () => _deleteMember(member),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MemberDetailScreen(member: member),
                            ),
                          );
                          if (changed == true && mounted) _refresh();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: state.canManageMembers
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Membre'),
            )
          : null,
    );
  }
}
