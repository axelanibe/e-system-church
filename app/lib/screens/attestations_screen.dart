import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/attestation.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// US3 — Attestations annuelles de dons, côté trésorier / admin :
/// choix de l'année, génération pour tous les donateurs, liste,
/// PDF, correction avec motif (nouvelle attestation, ancienne annulée).
class AttestationsScreen extends StatefulWidget {
  const AttestationsScreen({super.key});

  @override
  State<AttestationsScreen> createState() => _AttestationsScreenState();
}

class _AttestationsScreenState extends State<AttestationsScreen> {
  late int _annee;
  late Future<List<Attestation>> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _annee = DateTime.now().year;
    _future = _load();
  }

  Future<List<Attestation>> _load() =>
      context.read<AppState>().api.getAttestations(annee: _annee);

  void _refresh() => setState(() => _future = _load());

  Future<void> _generer() async {
    setState(() => _working = true);
    try {
      final creees = await context
          .read<AppState>()
          .api
          .genererAttestations(annee: _annee);
      if (!mounted) return;
      showSuccess(
        context,
        creees.isEmpty
            ? 'Aucune nouvelle attestation pour $_annee.'
            : '${creees.length} attestation(s) créée(s) pour $_annee.',
      );
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _telecharger(Attestation a) async {
    try {
      final bytes =
          await context.read<AppState>().api.telechargerAttestationPdf(a.id);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: '${a.numero}.pdf', mimeType: 'application/pdf'),
          ],
          subject: 'Attestation ${a.numero}',
        ),
      );
      if (mounted) {
        showSuccess(context, 'Attestation ${a.numero} partagée.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _corriger(Attestation a) async {
    final motifCtrl = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corriger l’attestation'),
        content: TextField(
          controller: motifCtrl,
          decoration: const InputDecoration(
            labelText: 'Motif de la correction',
            hintText: 'Ex. don oublié ajouté',
          ),
          maxLength: 500,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(motifCtrl.text.trim()),
            child: const Text('Corriger'),
          ),
        ],
      ),
    );
    if (motif == null || motif.length < 2) return;
    if (!mounted) return;
    setState(() => _working = true);
    try {
      final nouvelle = await context
          .read<AppState>()
          .api
          .corrigerAttestation(a.id, motif: motif);
      if (!mounted) return;
      showSuccess(context, 'Nouvelle attestation ${nouvelle.numero} créée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final annees = [for (var i = 0; i < 3; i++) DateTime.now().year - i];
    return Scaffold(
      appBar: AppBar(title: const Text('Attestations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: _annee,
                  items: annees
                      .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                      .toList(),
                  onChanged: (a) {
                    if (a == null) return;
                    setState(() {
                      _annee = a;
                      _future = _load();
                    });
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _working ? null : _generer,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Générer'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Reçu justificatif seulement, sans valeur fiscale en Côte d’Ivoire.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Attestation>>(
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
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.description_outlined,
                    message: 'Aucune attestation pour cette année.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: items
                        .map((a) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(
                                    '${a.membreNom ?? 'Donateur'} — ${formatFcfa(a.totalFcfa)}'),
                                subtitle: Text(
                                    '${a.numero} · ${pluriel(a.nbDons, 'don')} · ${formatDate(a.dateEmission)}${a.estEmise ? '' : ' · annulée'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (a.estEmise)
                                      IconButton(
                                        icon: const Icon(Icons.download_outlined),
                                        tooltip: 'Voir le PDF',
                                        onPressed: () => _telecharger(a),
                                      ),
                                    if (a.estEmise)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Corriger',
                                        onPressed: () => _corriger(a),
                                      ),
                                    if (!a.estEmise)
                                      const Icon(Icons.cancel_outlined,
                                          color: AppTheme.rougeErreur),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
