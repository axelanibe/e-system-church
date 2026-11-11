import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/church.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Arborescence de mon réseau (`GET /eglises/arbre`) : vue dépliable,
/// ajout d'une sous-église (admin seulement) et demandes de rattachement
/// en attente (accepter / refuser).
class TreeScreen extends StatefulWidget {
  const TreeScreen({super.key});

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> {
  late Future<TreeResult> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getTree();
  }

  Future<void> _refresh() async {
    setState(() => _future = context.read<AppState>().api.getTree());
    await _future;
  }

  Future<void> _addSubChurch() async {
    final nameController = TextEditingController();
    final cityController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle sous-église'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la sous-église *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Nom requis.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'Ville *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Ville requise.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (created != true || !mounted) return;
    try {
      await context.read<AppState>().api.createSubChurch(
            name: nameController.text.trim(),
            city: cityController.text.trim(),
            phone: phoneController.text.trim().isEmpty
                ? null
                : phoneController.text.trim(),
          );
      if (!mounted) return;
      showSuccess(context, 'Sous-église créée.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _decide(String id, bool accept) async {
    try {
      await context
          .read<AppState>()
          .api
          .decideRattachement(id, accept: accept);
      if (!mounted) return;
      showSuccess(
          context, accept ? 'Demande acceptée.' : 'Demande refusée.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: FutureBuilder<TreeResult>(
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
          final result = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (result.demandesRattachement.isNotEmpty) ...[
                  const SectionTitle(title: 'Demandes de rattachement'),
                  ...result.demandesRattachement.map(
                    (d) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.group_add_outlined),
                        title: Text(d.egliseNom),
                        subtitle: Text(
                            '${d.egliseCode} · ${d.egliseVille ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check,
                                  color: Colors.green),
                              tooltip: 'Accepter',
                              onPressed: () => _decide(d.id, true),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Refuser',
                              onPressed: () => _decide(d.id, false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SectionTitle(title: 'Mon réseau'),
                Card(
                  child: _TreeNodeTile(node: result.arbre, isRoot: true),
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.arbre.totalEglises} église(s) · ${result.arbre.totalMembresActifs} membre(s) actif(s) dans le réseau.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: state.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _addSubChurch,
              icon: const Icon(Icons.add),
              label: const Text('Sous-église'),
            )
          : null,
    );
  }
}

/// Tuile dépliable d'un nœud de l'arbre.
class _TreeNodeTile extends StatelessWidget {
  final ChurchNode node;
  final bool isRoot;

  const _TreeNodeTile({required this.node, this.isRoot = false});

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(
        node.isMere ? Icons.church : Icons.account_tree_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        node.name,
        style: isRoot ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text('${node.code} · ${node.city ?? ''}'),
      trailing: Text('${node.membresActifs} membre(s)'),
    );
    if (node.children.isEmpty) return tile;
    return ExpansionTile(
      leading: Icon(
        node.isMere ? Icons.church : Icons.account_tree_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        node.name,
        style: isRoot ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text('${node.code} · ${node.city ?? ''}'),
      trailing: Text('${node.membresActifs} membre(s)'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.only(left: 24),
      children: node.children
          .map((child) => _TreeNodeTile(node: child))
          .toList(),
    );
  }
}
