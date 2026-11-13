import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/contribution.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'receipt_screen.dart';

/// Reçus numérotés (tranche T7) : contributions confirmées, chacune
/// avec son numéro REC-AAAA-NNNN et son reçu en PDF. Le reçu est émis
/// à la confirmation par le pasteur ; la numérotation est continue,
/// sans trou.
class RecusScreen extends StatefulWidget {
  const RecusScreen({super.key});

  @override
  State<RecusScreen> createState() => _RecusScreenState();
}

class _RecusScreenState extends State<RecusScreen> {
  String? _typeFilter;
  late Future<ContributionPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<ContributionPage> _charger() => context
      .read<AppState>()
      .api
      .getContributions(type: _typeFilter, status: 'confirme');

  void _refresh() => setState(() => _future = _charger());

  Future<void> _telecharger(Contribution c) async {
    try {
      final bytes =
          await context.read<AppState>().api.telechargerRecuPdf(c.id);
      final nom = 'recu-${c.recuNumero ?? c.id}.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: nom, mimeType: 'application/pdf'),
          ],
          subject: 'Reçu ${c.recuNumero ?? ''}',
        ),
      );
      if (mounted) showSuccess(context, 'Reçu partagé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message: 'Votre rôle ne donne pas accès aux finances de l’église.',
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Reçus numérotés')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in <String, String?>{
                  'Tous types': null,
                  'Dîmes': 'dime',
                  'Offrandes': 'offrande',
                  'Dons': 'don',
                  'Dépenses': 'depense',
                  'Cotisations': 'cotisation',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.key),
                    selected: _typeFilter == entry.value,
                    onSelected: (_) {
                      setState(() {
                        _typeFilter = entry.value;
                        _future = _charger();
                      });
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<ContributionPage>(
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
                final contributions = snapshot.data!.contributions;
                if (contributions.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'Aucun reçu pour le moment. Les reçus '
                        'numérotés apparaissent ici dès qu’une contribution '
                        'est confirmée par le pasteur.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: contributions.length,
                    itemBuilder: (context, index) {
                      final c = contributions[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                              Icons.receipt_long_outlined),
                          title: Text(
                            '${c.recuNumero ?? 'Sans numéro'} — ${c.typeLabel} · ${formatMontant(c.amountFcfa, state.devise)}',
                          ),
                          subtitle: Text(
                            '${c.paymentLabel}${c.membreNom != null ? ' · ${c.membreNom}' : ''} · ${formatDate(c.createdAt)}',
                          ),
                          trailing: IconButton(
                            icon:
                                const Icon(Icons.description_outlined),
                            onPressed: () => _telecharger(c),
                            tooltip: 'Télécharger le reçu (PDF)',
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReceiptScreen(contributionId: c.id),
                              ),
                            );
                            if (mounted) _refresh();
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
      ),
    );
  }
}
