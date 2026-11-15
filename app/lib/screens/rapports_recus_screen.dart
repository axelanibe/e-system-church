import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rapport_annexe.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

/// Rapports reçus (tranche P5) : l'église mère lit ici les rapports
/// envoyés par ses églises annexes, qui arrivent aussi par e-mail.
/// Textes repris mot pour mot de la projection validée par Axel le
/// 12 novembre 2026. Les vrais rapports reçus s'affichent en premier.
class RapportsRecusScreen extends StatefulWidget {
  const RapportsRecusScreen({super.key});

  @override
  State<RapportsRecusScreen> createState() => _RapportsRecusScreenState();
}

class _RapportsRecusScreenState extends State<RapportsRecusScreen> {
  late Future<List<RapportAnnexe>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getRapportsRecus();
  }

  void _refresh() =>
      setState(() => _future = context.read<AppState>().api.getRapportsRecus());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapports reçus')),
      body: FutureBuilder<List<RapportAnnexe>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Impossible de charger les rapports reçus.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          final rapports = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Les rapports envoyés par vos églises annexes '
                        'arrivent ici, et aussi par e-mail.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      if (rapports.isNotEmpty)
                        ...rapports.map(
                          (r) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.typeLibelle,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (r.egliseNom != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      r.egliseNom!,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                  if (r.creeLe != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      formatDate(r.creeLe),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    'Membres ${r.membres} · Recettes '
                                    '${formatFcfa(r.recettesFcfa)} · Dépenses '
                                    '${formatFcfa(r.depensesFcfa)} · Solde '
                                    '${formatFcfa(r.soldeFcfa)}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  if (r.message != null &&
                                      r.message!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      r.message!,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
