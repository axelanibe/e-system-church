import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/paiements.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// État des comptes marchands (maquette, écran 29) : état seulement.
/// Les 3 comptes (Wave, Orange Money, MTN) sont toujours listés, avec
/// leur état. Aucun contrôle de gestion, aucun champ de clé, pas de
/// Virement ni d'Espèces : les numéros marchands et les clés se
/// saisissent uniquement dans Réglages et confidentialité.
class EtatComptesMarchandsScreen extends StatefulWidget {
  const EtatComptesMarchandsScreen({super.key});

  @override
  State<EtatComptesMarchandsScreen> createState() =>
      _EtatComptesMarchandsScreenState();
}

/// Les 3 comptes marchands de la maquette, dans cet ordre.
const _comptes = [
  ('wave', 'Wave', 'Compte Wave'),
  ('orange_money', 'Orange Money', 'Compte Orange Money'),
  ('mtn_momo', 'MTN Mobile Money', 'Compte MTN Mobile Money'),
];

class _EtatComptesMarchandsScreenState
    extends State<EtatComptesMarchandsScreen> {
  late Future<List<EglisePaiement>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EglisePaiement>> _load() =>
      context.read<AppState>().api.getMesPaiements(
            context.read<AppState>().church!.id,
          );

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('État des comptes marchands')),
      body: FutureBuilder<List<EglisePaiement>>(
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
          final configs = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'État des comptes seulement. Les numéros marchands et les clés se saisissent uniquement dans Réglages et confidentialité, section « Clés marchandes et API » — aucun champ de clé ici.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final (code, nom, sousTitre) in _comptes) ...[
                  SectionTitle(title: nom),
                  _CompteCard(
                    sousTitre: sousTitre,
                    config: configs
                        .where((c) => c.fournisseurCode == code)
                        .firstOrNull,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompteCard extends StatelessWidget {
  final String sousTitre;
  final EglisePaiement? config;

  const _CompteCard({
    required this.sousTitre,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    // Configuré seulement si au moins un champ (une clé) est
    // enregistré côté serveur ; un compte créé sans clé reste
    // « Non configuré ».
    final configure = config != null &&
        config!.champs.any((c) => c.configure);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  // Maquette, écran 29 : le titre de la carte est
                  // « Compte Wave », le nom du fournisseur est
                  // l'en-tête de section au-dessus de la carte.
                  child: Text(
                    sousTitre,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(
                  label: configure ? 'Configuré' : 'Non configuré',
                  color: configure
                      ? AppTheme.violetProfond
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!configure)
              const Text('Non configuré — aucune clé enregistrée')
            else ...[
              if (config!.libelle != null && config!.libelle!.isNotEmpty)
                Text('Libellé : ${config!.libelle}'),
              if (config!.apercu != null && config!.apercu!.isNotEmpty)
                Text('Identifiant : ${config!.apercu}'),
              Text(config!.actif ? 'Compte actif.' : 'Compte inactif.'),
            ],
          ],
        ),
      ),
    );
  }
}
