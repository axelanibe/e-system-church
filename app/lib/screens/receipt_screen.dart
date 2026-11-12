import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Reçu d'une contribution (`GET /contributions/:id`) : détail complet,
/// avec confirmation / annulation quand elle est en attente (admin ou
/// trésorier seulement).
class ReceiptScreen extends StatefulWidget {
  final String contributionId;

  const ReceiptScreen({super.key, required this.contributionId});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Future<Contribution> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getReceipt(widget.contributionId);
  }

  Future<void> _setStatus(String status) async {
    setState(() => _working = true);
    try {
      final updated = await context
          .read<AppState>()
          .api
          .setContributionStatus(widget.contributionId, status);
      if (!mounted) return;
      showSuccess(
        context,
        status == 'confirme' ? 'Contribution confirmée.' : 'Contribution annulée.',
      );
      setState(() => _future = Future.value(updated));
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirme':
        return AppTheme.cypress;
      case 'en_attente':
        return Colors.orange;
      case 'annule':
        return AppTheme.rougeErreur;
      default:
        return Colors.grey;
    }
  }

  Widget _row(BuildContext context, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value ?? '—',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reçu')),
      body: FutureBuilder<Contribution>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = context
                  .read<AppState>()
                  .api
                  .getReceipt(widget.contributionId)),
            );
          }
          final c = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              c.egliseNom ?? 'e-System Church',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            if (c.egliseCode != null)
                              Text('Code : ${c.egliseCode}'),
                            const SizedBox(height: 12),
                            Text(
                              formatFcfa(c.amountFcfa),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(c.typeLabel),
                            const SizedBox(height: 8),
                            StatusChip(
                              label: c.statusLabel,
                              color: _statusColor(c.status),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _row(context, 'Moyen', c.paymentLabel),
                            _row(context, 'Référence', c.paymentRef),
                            _row(
                                context,
                                'Membre',
                                c.membreNom == null
                                    ? null
                                    : '${c.membreNom} (${c.membreMatricule ?? ''})'),
                            _row(context, 'Note', c.note),
                            _row(context, 'Date',
                                formatDateTime(c.createdAt)),
                          ],
                        ),
                      ),
                    ),
                    if (c.status == 'en_attente' &&
                        state.canManageFinances) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed:
                            _working ? null : () => _setStatus('confirme'),
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmer la contribution'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _working ? null : () => _setStatus('annule'),
                        icon: const Icon(Icons.close),
                        label: const Text('Annuler la contribution'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
