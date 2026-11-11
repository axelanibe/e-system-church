import 'dart:async';
import '../config/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';

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
  String? _statusFilter;
  String? _departmentFilter;
  late Future<MemberPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = value.trim();
        _future = _load();
      });
    });
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

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return AppTheme.saugeFonce;
      case 'nouveau_converti':
        return AppTheme.bleuDoux;
      case 'inactif':
        return Colors.grey;
      default:
        return Colors.grey;
    }
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in <String, String?>{
                    'Tous': null,
                    'Actif': 'actif',
                    'Nouveau converti': 'nouveau_converti',
                    'Inactif': 'inactif',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.key),
                        selected: _statusFilter == entry.value,
                        onSelected: (_) {
                          setState(() {
                            _statusFilter = entry.value;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: _departmentFilter,
                    hint: const Text('Département'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tous')),
                      DropdownMenuItem(
                          value: 'Louange', child: Text('Louange')),
                      DropdownMenuItem(
                          value: 'Intercession',
                          child: Text('Intercession')),
                      DropdownMenuItem(
                          value: 'Jeunesse', child: Text('Jeunesse')),
                      DropdownMenuItem(
                          value: 'Protocole', child: Text('Protocole')),
                      DropdownMenuItem(
                          value: 'Enfants', child: Text('Enfants')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _departmentFilter = value;
                        _future = _load();
                      });
                    },
                  ),
                ],
              ),
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
                if (page.membres.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    message: 'Aucun membre trouvé.',
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
                    itemCount: page.membres.length,
                    itemBuilder: (context, index) {
                      final member = page.membres[index];
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
                              label: member.statusLabel,
                              color: _statusColor(member.status),
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
