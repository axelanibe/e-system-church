import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/church.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Arborescence de mon réseau (`GET /eglises/arbre`) : vue dépliable
/// et ajout d'une sous-église (admin seulement). Ancien écran « Réseau »
/// (10), fusionné dans Mes annexes (12) : il n'existe plus d'écran
/// Réseau séparé, cet arbre s'affiche directement dans Mes annexes.
/// Les demandes de rattachement se traitent dans leur écran (11),
/// pas ici : une seule entrée par fonction.
class ArbreReseau extends StatefulWidget {
  const ArbreReseau({super.key});

  @override
  State<ArbreReseau> createState() => _ArbreReseauState();
}

class _ArbreReseauState extends State<ArbreReseau> {
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder<TreeResult>(
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: _TreeNodeTile(
                node: result.arbre,
                isRoot: true,
                canEdit: state.isAdmin,
                onRenamed: _refresh,
              ),
            ),
            // Le bouton reste visible pour une mère même quand
            // le réseau n'est plus vide : c'est le seul moyen
            // de créer une autre sous-église (plus de FAB).
            if (reseauVide || result.arbre.isMere) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!result.arbre.isMere)
                        const Text(
                          'Une annexe ne peut pas avoir de '
                          'sous-église.',
                        ),
                      // Le bouton n'existe que pour une mère.
                      if (result.arbre.isMere) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _addSubChurch,
                          icon: const Icon(Icons.add),
                          label: const Text('Créer une sous-église'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
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
  // La tuile est dépliée au départ ; suit l'état de l'ExpansionTile
  // pour orienter la flèche du trailing.
  bool _ouvert = true;
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
                : const Icon(Icons.check, color: AppTheme.violetProfond),
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
        // Flèche de dépliage : le trailing remplace celle par défaut
        // de l'ExpansionTile, il faut la remettre à côté du compteur.
        if (widget.node.children.isNotEmpty)
          Icon(_ouvert
              ? Icons.keyboard_arrow_up
              : Icons.keyboard_arrow_down),
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
      onExpansionChanged: (ouvert) => setState(() => _ouvert = ouvert),
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
