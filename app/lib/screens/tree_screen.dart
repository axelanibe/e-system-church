import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/church.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
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
                                    // Une annexe ne peut pas accepter de
                                    // rattachement : elle ne peut pas
                                    // devenir mère. Refuser reste possible.
                                    if (result.arbre.isMere)
                                      IconButton(
                                        icon: const Icon(Icons.check,
                                            color: AppTheme.cypress),
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
                          child: _TreeNodeTile(
                            node: result.arbre,
                            isRoot: true,
                            canEdit: state.isAdmin,
                            onRenamed: _refresh,
                          ),
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
                                    result.arbre.isMere
                                        ? 'Votre réseau, c’est votre église et ses sous-églises.'
                                        : 'Votre église est une annexe.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    result.arbre.isMere
                                        ? 'Pour l’instant, vous n’avez qu’une seule église. '
                                            'Créez une sous-église pour une nouvelle antenne : '
                                            'elle aura son propre code, ses membres et ses finances, '
                                            'et vous verrez ici ses chiffres avec les vôtres.'
                                        : 'Une annexe ne peut pas avoir de sous-église. '
                                            'Pour organiser la vie de votre église en petits groupes, '
                                            'créez des cellules dans Familles, onglet Cellules.',
                                  ),
                                  // Le bouton n'existe que pour une mère.
                                  if (result.arbre.isMere) ...[
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: _addSubChurch,
                                      icon: const Icon(Icons.add),
                                      label:
                                          const Text('Créer une sous-église'),
                                    ),
                                  ],
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
      // Le bouton n'existe que pour une église mère : une annexe ne
      // peut pas créer de sous-église (règle du 11/11/2026).
      floatingActionButton: state.isAdmin && (state.church?.isMere ?? false)
          ? FloatingActionButton.extended(
              // Bleu nuit et blanc, bien lisible : l'or du thème sur fond
              // papier paraissait effacé sur la photo 2.
              backgroundColor: AppTheme.cypress,
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
///
/// Modification directe, en place : le nom de l'église de la session
/// (la racine) se corrige ici même, sans passer par un autre écran.
/// L'admin touche le crayon, le nom devient un champ, il valide ou
/// annule sur place. Les autres nœuds restent en lecture seule.
class _TreeNodeTile extends StatefulWidget {
  final ChurchNode node;
  final bool isRoot;
  final bool canEdit;
  final Future<void> Function() onRenamed;

  const _TreeNodeTile({
    required this.node,
    this.isRoot = false,
    this.canEdit = false,
    required this.onRenamed,
  });

  @override
  State<_TreeNodeTile> createState() => _TreeNodeTileState();
}

class _TreeNodeTileState extends State<_TreeNodeTile> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.node.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      showApiError(context, 'Le nom doit avoir au moins 2 caractères.');
      return;
    }
    if (name == widget.node.name) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().api.updateProfil(
            churchId: widget.node.id,
            name: name,
          );
      if (!mounted) return;
      setState(() => _editing = false);
      showSuccess(context, 'Nom modifié.');
      await widget.onRenamed();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _title() {
    if (!_editing) {
      return Text(
        widget.node.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: widget.isRoot
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      );
    }
    return TextField(
      controller: _nameController,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Nom de l’église',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => _save(),
    );
  }

  Widget _trailing() {
    if (_editing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, color: AppTheme.cypress),
            tooltip: 'Enregistrer',
            onPressed: _saving ? null : _save,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Annuler',
            onPressed: _saving
                ? null
                : () => setState(() {
                      _editing = false;
                      _nameController.text = widget.node.name;
                    }),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(pluriel(widget.node.membresActifs, 'membre')),
        if (widget.isRoot && widget.canEdit)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Corriger le nom',
            onPressed: () => setState(() => _editing = true),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final leading = Icon(
      node.isMere ? Icons.church : Icons.account_tree_outlined,
      color: Theme.of(context).colorScheme.primary,
    );
    final subtitle = Text(
      '${node.code} · ${node.city ?? ''}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (node.children.isEmpty) {
      return ListTile(
        leading: leading,
        title: _title(),
        subtitle: subtitle,
        trailing: _trailing(),
      );
    }
    return ExpansionTile(
      leading: leading,
      title: _title(),
      subtitle: subtitle,
      trailing: _trailing(),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.only(left: 24),
      children: node.children
          .map((child) => _TreeNodeTile(
                node: child,
                onRenamed: widget.onRenamed,
              ))
          .toList(),
    );
  }
}
