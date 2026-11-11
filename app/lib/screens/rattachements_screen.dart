import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/rattachement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Demandes de rattachement : reçues (je suis la mère sollicitée) et
/// émises (mon église demande à rejoindre une mère), + formulaire de
/// demande par code d'invitation.
class RattachementsScreen extends StatefulWidget {
  const RattachementsScreen({super.key});

  @override
  State<RattachementsScreen> createState() => _RattachementsScreenState();
}

class _RattachementsScreenState extends State<RattachementsScreen> {
  late Future<RattachementsResult> _future;
  final _codeController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getRattachements();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(
        () => _future = context.read<AppState>().api.getRattachements());
    await _future;
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

  Future<void> _request() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      showApiError(context, 'Saisissez le code d’invitation de l’église mère.');
      return;
    }
    setState(() => _sending = true);
    try {
      await context
          .read<AppState>()
          .api
          .requestRattachement(parentCode: code);
      if (!mounted) return;
      _codeController.clear();
      showSuccess(context,
          'Demande envoyée. Elle sera visible par l’église mère.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _rattachementTile(Rattachement r, {required bool isRecue}) {
    final color = switch (r.status) {
      'acceptee' => AppTheme.vertFonce,
      'refusee' => AppTheme.rougeErreur,
      _ => Colors.orange,
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.group_add_outlined),
        title: Text(r.egliseNom),
        subtitle: Text(
            '${r.egliseCode} · ${r.egliseVille ?? ''} · ${formatDate(r.createdAt)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(label: r.statusLabel, color: color),
            if (isRecue && r.status == 'en_attente') ...[
              IconButton(
                icon: const Icon(Icons.check, color: AppTheme.vertFonce),
                tooltip: 'Accepter',
                onPressed: () => _decide(r.id, true),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.rougeErreur),
                tooltip: 'Refuser',
                onPressed: () => _decide(r.id, false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Demandes de rattachement')),
      body: FutureBuilder<RattachementsResult>(
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
                if (state.isAdmin) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Rejoindre une église mère',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text(
                              'Saisissez le code d’invitation de l’église mère à rejoindre.'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _codeController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'Code d’invitation',
                                    hintText: 'Ex. GD-PLAT',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _sending ? null : _request,
                                child: const Text('Envoyer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SectionTitle(title: 'Demandes reçues'),
                if (result.recues.isEmpty)
                  const EmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'Aucune demande reçue.',
                  )
                else
                  ...result.recues.map(
                      (r) => _rattachementTile(r, isRecue: true)),
                const SectionTitle(title: 'Demandes émises'),
                if (result.emises.isEmpty)
                  const EmptyState(
                    icon: Icons.outbox_outlined,
                    message: 'Aucune demande émise.',
                  )
                else
                  ...result.emises.map(
                      (r) => _rattachementTile(r, isRecue: false)),
              ],
            ),
          );
        },
      ),
    );
  }
}
