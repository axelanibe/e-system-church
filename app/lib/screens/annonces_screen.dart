import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Annonces : les miennes + celles diffusées par mes églises mères.
/// Création (admin seulement) avec diffusion à tout le réseau.
class AnnoncesScreen extends StatefulWidget {
  const AnnoncesScreen({super.key});

  @override
  State<AnnoncesScreen> createState() => _AnnoncesScreenState();
}

class _AnnoncesScreenState extends State<AnnoncesScreen> {
  late Future<List<Announcement>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getAnnonces();
  }

  void _refresh() {
    setState(() => _future = context.read<AppState>().api.getAnnonces());
  }

  Future<void> _create() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var broadcast = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle annonce'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titre *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Titre requis.'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bodyController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Message requis.'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Diffuser à tout le réseau'),
                    subtitle: const Text(
                        'Les sous-églises verront aussi cette annonce.'),
                    value: broadcast,
                    onChanged: (v) => setDialogState(() => broadcast = v),
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
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    try {
      await context.read<AppState>().api.createAnnonce(
            title: titleController.text.trim(),
            body: bodyController.text.trim(),
            broadcast: broadcast,
          );
      if (!mounted) return;
      showSuccess(context, 'Annonce publiée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: FutureBuilder<List<Announcement>>(
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
          final annonces = snapshot.data!;
          if (annonces.isEmpty) {
            return EmptyState(
              icon: Icons.campaign_outlined,
              message: 'Aucune annonce pour l’instant.',
              actionLabel: state.isAdmin ? 'Publier une annonce' : null,
              onAction: state.isAdmin ? _create : null,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: annonces.length,
              itemBuilder: (context, index) {
                final a = annonces[index];
                final isMine = a.churchId == state.church?.id;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      a.broadcast
                          ? Icons.cell_tower_outlined
                          : Icons.campaign_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(a.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.body),
                        const SizedBox(height: 4),
                        Text(
                          '${a.egliseNom ?? ''} · ${formatDateTime(a.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    trailing: a.broadcast
                        ? const Chip(
                            label: Text('Réseau'),
                            visualDensity: VisualDensity.compact,
                          )
                        : (isMine
                            ? const Chip(
                                label: Text('Mon église'),
                                visualDensity: VisualDensity.compact,
                              )
                            : null),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: state.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Annonce'),
            )
          : null,
    );
  }
}
