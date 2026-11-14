import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/rapport_annexe.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'exemple_bilan_screen.dart';
import 'rapports_screen.dart';

/// Rapports reçus (tranche P5) : l'église mère lit ici les rapports
/// envoyés par ses églises annexes, qui arrivent aussi par e-mail.
/// Textes repris mot pour mot de la projection validée par Axel le
/// 12 novembre 2026. Les vrais rapports reçus s'affichent en premier ;
/// l'entrée d'exemple, marquée EXEMPLE, reste en bas, comme dans la
/// projection, sans jamais se présenter comme un vrai rapport reçu.
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

  void _ouvrirExemple() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExempleBilanScreen()),
    );
  }

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
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.assessment_outlined),
                          title: const Text('Statistiques et exports'),
                          subtitle: const Text(
                              'Chiffres du réseau, exports CSV et PDF.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RapportsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (rapports.isEmpty)
                        const EmptyState(
                          icon: Icons.mail_outline,
                          message: 'Aucun rapport reçu pour l’instant.',
                        )
                      else
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
                                  if (r.enAttenteEnvoi) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'En attente d’envoi par e-mail.',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Bilan annuel',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.violetProfond,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'EXEMPLE',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Envoyé par une église annexe. Rapport '
                                'd’exemple, avec des chiffres d’exemple.',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _ouvrirExemple,
                                child: const Text('Ouvrir'),
                              ),
                            ],
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
