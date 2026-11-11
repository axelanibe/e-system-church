import 'package:flutter/material.dart';
import '../config/app_theme.dart';
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
          // Réseau vide (une seule église, aucune sous-église) : la page
          // ne reste pas vide et confuse (photo 2). Une carte explique
          // ce qu'est le réseau et ce qu'il faut faire ensuite, avec un
          // bouton bien visible, au lieu du seul petit bouton flottant.
          final reseauVide = result.arbre.totalEglises <= 1 &&
              result.arbre.children.isEmpty &&
              result.demandesRattachement.isEmpty;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (result.demandesRattachement.isNotEmpty) ...[
                          const SectionTitle(title: 'Demandes de rattachement'),
                          ...result.demandesRattachement.map(
                            (d) => Card(
                              child: ListTile(
                                leading:
                                    const Icon(Icons.group_add_outlined),
                                title: Text(
                                  d.egliseNom,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                    '${d.egliseCode} · ${d.egliseVille ?? ''}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check,
                                          color: AppTheme.saugeFonce),
                                      tooltip: 'Accepter',
                                      onPressed: () => _decide(d.id, true),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: AppTheme.rougeErreur),
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
                          child:
                              _TreeNodeTile(node: result.arbre, isRoot: true),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${result.arbre.totalEglises} église${result.arbre.totalEglises > 1 ? 's' : ''} · ${result.arbre.totalMembresActifs} membre${result.arbre.totalMembresActifs > 1 ? 's' : ''} actif${result.arbre.totalMembresActifs > 1 ? 's' : ''} dans le réseau.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        if (reseauVide) ...[
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Votre réseau, c’est votre église et ses sous-églises.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Pour l’instant, vous n’avez qu’une seule église. '
                                    'Créez une sous-église pour une nouvelle antenne : '
                                    'elle aura son propre code, ses membres et ses finances, '
                                    'et vous verrez ici ses chiffres avec les vôtres.',
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _addSubChurch,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Créer une sous-église'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: state.isAdmin
          ? FloatingActionButton.extended(
              // Bleu nuit et blanc, bien lisible : l'or du thème sur fond
              // papier paraissait effacé sur la photo 2.
              backgroundColor: AppTheme.saugeFonce,
              foregroundColor: Colors.white,
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: isRoot ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text(
        '${node.code} · ${node.city ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: isRoot ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text(
        '${node.code} · ${node.city ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${node.membresActifs} membre(s)'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.only(left: 24),
      children: node.children
          .map((child) => _TreeNodeTile(node: child))
          .toList(),
    );
  }
}
