import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/attestation.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// US3 — Mes attestations annuelles de dons (membre) : liste par année,
/// téléchargement du PDF. Le membre ne voit que les siennes.
class MesAttestationsScreen extends StatefulWidget {
  const MesAttestationsScreen({super.key});

  @override
  State<MesAttestationsScreen> createState() => _MesAttestationsScreenState();
}

class _MesAttestationsScreenState extends State<MesAttestationsScreen> {
  late Future<List<Attestation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Attestation>> _load() =>
      context.read<AppState>().api.getMesAttestations();

  void _refresh() => setState(() => _future = _load());

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes attestations')),
      body: FutureBuilder<List<Attestation>>(
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
              message: 'Aucune attestation pour l’instant.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Reçu justificatif seulement, sans valeur fiscale en Côte d’Ivoire.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                ...items.map((a) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text('${a.annee} — ${formatFcfa(a.totalFcfa)}'),
                        subtitle: Text(
                            '${a.numero} · ${pluriel(a.nbDons, 'don')} · ${formatDate(a.dateEmission)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: 'Télécharger le PDF',
                          onPressed: () => _telecharger(a),
                        ),
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
