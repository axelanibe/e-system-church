import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parametres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 12 — Administration : paramètres de l'église, rôles et journal
/// d'audit.
class ParametresScreen extends StatefulWidget {
  const ParametresScreen({super.key});

  @override
  State<ParametresScreen> createState() => _ParametresScreenState();
}

class _ParametresScreenState extends State<ParametresScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<EgliseParametres> _parametresFuture;
  late Future<List<RoleEglise>> _rolesFuture;
  late Future<List<AuditEntree>> _auditFuture;

  final _adresseController = TextEditingController();
  final _villeController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _waveController = TextEditingController();
  final _orangeController = TextEditingController();
  final _mtnController = TextEditingController();
  final _deviseController = TextEditingController();
  final _fuseauController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parametresFuture = context.read<AppState>().api.getParametres();
    _rolesFuture = context.read<AppState>().api.getRoles();
    _auditFuture = context.read<AppState>().api.getAudit();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adresseController.dispose();
    _villeController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _logoUrlController.dispose();
    _waveController.dispose();
    _orangeController.dispose();
    _mtnController.dispose();
    _deviseController.dispose();
    _fuseauController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _parametresFuture = api.getParametres();
      if (_tab == 1) _rolesFuture = api.getRoles();
      if (_tab == 2) _auditFuture = api.getAudit();
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().api.saveParametres(
            adresse: _opt(_adresseController),
            ville: _opt(_villeController),
            telephone: _opt(_telephoneController),
            email: _opt(_emailController),
            logoUrl: _opt(_logoUrlController),
            waveNumero: _opt(_waveController),
            orangeNumero: _opt(_orangeController),
            mtnNumero: _opt(_mtnController),
            devise: _opt(_deviseController),
            fuseauHoraire: _opt(_fuseauController),
          );
      if (mounted) showSuccess(context, 'Paramètres enregistrés.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _parametresTab() {
    return FutureBuilder<EgliseParametres>(
      future: _parametresFuture,
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
        final p = snapshot.data!;
        _adresseController.text = p.adresse ?? '';
        _villeController.text = p.ville ?? '';
        _telephoneController.text = p.telephone ?? '';
        _emailController.text = p.email ?? '';
        _logoUrlController.text = p.logoUrl ?? '';
        _waveController.text = p.waveNumero ?? '';
        _orangeController.text = p.orangeNumero ?? '';
        _mtnController.text = p.mtnNumero ?? '';
        _deviseController.text = p.devise ?? '';
        _fuseauController.text = p.fuseauHoraire ?? '';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle(title: 'Coordonnées'),
            dialogTextField(controller: _adresseController, label: 'Adresse'),
            dialogTextField(controller: _villeController, label: 'Ville'),
            dialogTextField(
              controller: _telephoneController,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _emailController,
              label: 'E-mail',
              keyboardType: TextInputType.emailAddress,
            ),
            dialogTextField(controller: _logoUrlController, label: 'URL du logo'),
            const SectionTitle(title: 'Paiements mobiles'),
            dialogTextField(
              controller: _waveController,
              label: 'Numéro Wave',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _orangeController,
              label: 'Numéro Orange Money',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _mtnController,
              label: 'Numéro MTN Mobile Money',
              keyboardType: TextInputType.phone,
            ),
            const SectionTitle(title: 'Préférences'),
            dialogTextField(controller: _deviseController, label: 'Devise'),
            dialogTextField(
                controller: _fuseauController, label: 'Fuseau horaire'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Enregistrer les paramètres'),
            ),
          ],
        );
      },
    );
  }

  Widget _rolesTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un utilisateur',
        ),
        Expanded(
          child: FutureBuilder<List<RoleEglise>>(
            future: _rolesFuture,
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
                  .where((r) =>
                      _matches(r.fullName ?? '') || _matches(r.email ?? ''))
                  .toList();
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.manage_accounts_outlined,
                  message: 'Aucun utilisateur dans cette église pour l’instant.',
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
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(r.fullName ?? 'Utilisateur sans nom'),
                      subtitle: Text(r.email ?? ''),
                      trailing: DropdownButton<String>(
                        value: r.role,
                        items: const [
                          DropdownMenuItem(
                              value: 'admin_eglise',
                              child: Text('Admin d’église')),
                          DropdownMenuItem(
                              value: 'tresorier',
                              child: Text('Trésorier')),
                          DropdownMenuItem(
                              value: 'responsable_culte',
                              child: Text('Responsable de culte')),
                          DropdownMenuItem(
                              value: 'membre', child: Text('Membre')),
                        ],
                        onChanged: (value) async {
                          if (value == null || value == r.role) return;
                          try {
                            await context
                                .read<AppState>()
                                .api
                                .setRole(r.userId, value);
                            if (context.mounted) {
                              showSuccess(context, 'Rôle mis à jour.');
                            }
                            _refresh();
                          } catch (e) {
                            if (context.mounted) showApiError(context, e);
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

  Widget _auditTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher dans le journal',
        ),
        Expanded(
          child: FutureBuilder<List<AuditEntree>>(
            future: _auditFuture,
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
                  .where((a) =>
                      _matches(a.action) ||
                      _matches(a.utilisateur ?? ''))
                  .toList();
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.history,
                  message: 'Aucune entrée dans le journal d’audit pour l’instant.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final a = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.history),
                      ),
                      title: Text(a.action),
                      subtitle: Text(
                        '${a.utilisateur ?? '—'} · ${afficherDateTime(a.createdAt)}'
                        '${a.details != null ? ' · ${a.details}' : ''}',
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Paramètres de l’église'),
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Paramètres'),
              Tab(text: 'Rôles'),
              Tab(text: 'Journal d’audit'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _parametresTab(),
            _rolesTab(),
            _auditTab(),
          ],
        ),
      ),
    );
  }
}
