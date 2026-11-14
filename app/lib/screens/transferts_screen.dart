import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/transfert.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Transferts de membre entre branches : demande par matricule, validation
/// par les deux pasteurs (départ puis arrivée), historique gardé. À la
/// double acceptation, le membre change d'église et reçoit un nouveau
/// matricule dans l'église d'arrivée ; l'ancienne branche ne le voit plus.
class TransfertsScreen extends StatefulWidget {
  const TransfertsScreen({super.key});

  @override
  State<TransfertsScreen> createState() => _TransfertsScreenState();
}

class _TransfertsScreenState extends State<TransfertsScreen> {
  late Future<TransfertsResult> _future;
  final _matriculeController = TextEditingController();
  final _codeController = TextEditingController();
  final _motifController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getTransferts();
  }

  @override
  void dispose() {
    _matriculeController.dispose();
    _codeController.dispose();
    _motifController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = context.read<AppState>().api.getTransferts());
    await _future;
  }

  Future<void> _decide(String id, bool accept) async {
    try {
      await context
          .read<AppState>()
          .api
          .decideTransfert(id, accept: accept);
      if (!mounted) return;
      showSuccess(context,
          accept ? 'Transfert accepté de votre côté.' : 'Transfert refusé.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _annuler(String id) async {
    try {
      await context.read<AppState>().api.annulerTransfert(id);
      if (!mounted) return;
      showSuccess(context, 'Demande de transfert annulée.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _request() async {
    final matricule = _matriculeController.text.trim().toUpperCase();
    final code = _codeController.text.trim().toUpperCase();
    if (matricule.isEmpty) {
      showApiError(context, 'Saisissez le matricule du membre.');
      return;
    }
    if (code.length < 4) {
      showApiError(context, 'Saisissez le code de l’église d’arrivée.');
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AppState>().api.requestTransfert(
            matricule: matricule,
            destinationCode: code,
            motif: _motifController.text.trim().isEmpty
                ? null
                : _motifController.text.trim(),
          );
      if (!mounted) return;
      _matriculeController.clear();
      _codeController.clear();
      _motifController.clear();
      showSuccess(context,
          'Demande envoyée. Le pasteur de départ doit d’abord accepter, puis celui de l’église d’arrivée.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _transfertTile(TransfertMembre t,
      {required bool aTraiter, required bool emis}) {
    final color = switch (t.status) {
      'accepte' => AppTheme.violetProfond,
      'refuse' || 'annule' => AppTheme.rougeErreur,
      _ => Colors.orange,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.membreNom,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(label: t.statusLabel, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ancien matricule : ${t.ancienMatricule}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
                '${t.egliseDepartNom} (${t.egliseDepartCode}) → ${t.egliseArriveeNom} (${t.egliseArriveeCode})'),
            if (t.nouveauMatricule != null)
              Text('Nouveau matricule : ${t.nouveauMatricule}'),
            Text(
                'Départ : ${TransfertMembre.labelForDecision(t.decisionDepart)} · Arrivée : ${TransfertMembre.labelForDecision(t.decisionArrivee)}'),
            if (t.motif != null && t.motif!.isNotEmpty)
              Text('Motif : ${t.motif}'),
            Text(formatDate(t.createdAt)),
            if (aTraiter || (emis && t.status == 'en_attente')) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (aTraiter) ...[
                    OutlinedButton.icon(
                      onPressed: () => _decide(t.id, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Accepter'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _decide(t.id, false),
                      icon: const Icon(Icons.close),
                      label: const Text('Refuser'),
                    ),
                  ],
                  if (emis && t.status == 'en_attente')
                    OutlinedButton.icon(
                      onPressed: () => _annuler(t.id),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Annuler la demande'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<TransfertMembre> items,
      {required bool aTraiter,
      required bool emis,
      required String vide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title: title),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.swap_horiz_outlined,
            message: vide,
          )
        else
          ...items.map((t) =>
              _transfertTile(t, aTraiter: aTraiter, emis: emis)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Transferts de membres')),
      body: FutureBuilder<TransfertsResult>(
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
                          Text('Demander un transfert',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text(
                              'Le membre quitte votre église pour une autre branche. La demande est validée par votre pasteur, puis par le pasteur de l’église d’arrivée.'),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _matriculeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Matricule du membre',
                              hintText: 'Ex. M-LK-150390-01',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Code de l’église d’arrivée',
                              hintText: 'Ex. GD-YOP',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _motifController,
                            decoration: const InputDecoration(
                              labelText: 'Motif (facultatif)',
                              hintText: 'Ex. Déménagement',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _sending ? null : _request,
                            child: const Text('Envoyer la demande'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                _section('À traiter par mon église', result.aTraiter,
                    aTraiter: true,
                    emis: false,
                    vide: 'Aucun transfert à traiter.'),
                _section('Demandes émises', result.emises,
                    aTraiter: false,
                    emis: true,
                    vide: 'Aucune demande émise.'),
                _section('Demandes reçues', result.recues,
                    aTraiter: false,
                    emis: false,
                    vide: 'Aucune demande reçue.'),
                _section('Historique', result.historique,
                    aTraiter: false,
                    emis: false,
                    vide: 'Aucun transfert dans l’historique.'),
              ],
            ),
          );
        },
      ),
    );
  }
}
