import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';
import 'finances_complement_screen.dart';

/// Clôture de caisse (tranche T7) : solde de caisse, clôture d'un mois
/// terminé, et historique des clôtures. Une clôture ne se rouvre ni ne
/// se supprime : une erreur se corrige par une écriture dans la
/// période en cours. Saisie admin et trésorier.
class ClotureCaisseScreen extends StatefulWidget {
  const ClotureCaisseScreen({super.key});

  @override
  State<ClotureCaisseScreen> createState() => _ClotureCaisseScreenState();
}

class _DonneesCloture {
  final CaisseSolde solde;
  final List<ClotureCaisse> clotures;

  const _DonneesCloture({required this.solde, required this.clotures});
}

class _ClotureCaisseScreenState extends State<ClotureCaisseScreen> {
  late Future<_DonneesCloture> _future;
  final _periodeController =
      TextEditingController(text: dernierMoisTermine());
  final _compteController = TextEditingController();
  final _commentaireController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  @override
  void dispose() {
    _periodeController.dispose();
    _compteController.dispose();
    _commentaireController.dispose();
    super.dispose();
  }

  Future<_DonneesCloture> _charger() async {
    final api = context.read<AppState>().api;
    final results = await Future.wait([
      api.getCaisseSolde(),
      api.getCloturesCaisse(),
    ]);
    return _DonneesCloture(
      solde: results[0] as CaisseSolde,
      clotures: results[1] as List<ClotureCaisse>,
    );
  }

  void _refresh() => setState(() => _future = _charger());

  Future<void> _cloturer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enCours = true);
    try {
      final compte = _compteController.text.trim();
      await context.read<AppState>().api.cloturerCaisse(
            periode: _periodeController.text.trim(),
            soldeCompteFcfa: compte.isEmpty ? null : int.parse(compte),
            commentaire: _commentaireController.text.trim().isEmpty
                ? null
                : _commentaireController.text.trim(),
          );
      if (!mounted) return;
      showSuccess(context, 'Mois clôturé.');
      _compteController.clear();
      _commentaireController.clear();
      _periodeController.text = dernierMoisTermine();
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return Scaffold(
        appBar: AppBar(title: const Text('Clôture de caisse')),
        body: const EmptyState(
          icon: Icons.block_outlined,
          message: 'Votre rôle ne donne pas accès aux finances de l’église.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Clôture de caisse')),
      body: FutureBuilder<_DonneesCloture>(
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
          final donnees = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        constraints.maxWidth > 600 ? 3 : 2;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          label: 'Solde de caisse',
                          value: formatMontant(
                              donnees.solde.solde, state.devise),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.violetProfond,
                        ),
                        StatCard(
                          label: 'Entrées',
                          value: formatMontant(
                              donnees.solde.entrees, state.devise),
                          icon: Icons.trending_up,
                          color: AppTheme.violetProfond,
                        ),
                        StatCard(
                          label: 'Sorties',
                          value: formatMontant(
                              donnees.solde.sorties, state.devise),
                          icon: Icons.trending_down,
                          color: AppTheme.rougeErreur,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (state.canManageFinances)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Clôturer un mois terminé',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Une clôture ne se rouvre ni ne se supprime.',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _periodeController,
                              decoration: const InputDecoration(
                                labelText: 'Période (AAAA-MM) *',
                                hintText: 'Ex. 2026-10',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  RegExp(r'^\d{4}-\d{2}$')
                                          .hasMatch(v?.trim() ?? '')
                                      ? null
                                      : 'Période au format AAAA-MM.',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _compteController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Solde compté (FCFA)',
                                hintText:
                                    'Vide : reprend le solde calculé',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                final texte = v?.trim() ?? '';
                                if (texte.isEmpty) return null;
                                final montant = int.tryParse(texte);
                                if (montant == null || montant < 0) {
                                  return 'Montant invalide.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _commentaireController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Commentaire',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _enCours ? null : _cloturer,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Clôturer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: SectionTitle(title: 'Clôtures'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const FinancesComplementScreen(
                                    initialTab: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Mouvements de caisse'),
                    ),
                  ],
                ),
                if (donnees.clotures.isEmpty)
                  const EmptyState(
                    icon: Icons.lock_outline,
                    message: 'Aucune période clôturée pour le moment.',
                  )
                else
                  ...donnees.clotures.map(
                    (cloture) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(libellePeriodeMois(cloture.periode)),
                        subtitle: Text(
                          'Calculé : ${formatMontant(cloture.soldeCalculeFcfa, state.devise)}'
                          ' · Compté : ${formatMontant(cloture.soldeCompteFcfa, state.devise)}'
                          '${(cloture.commentaire ?? '').isNotEmpty ? '\n${cloture.commentaire}' : ''}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Écart : ${formatMontant(cloture.ecartFcfa, state.devise)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cloture.ecartFcfa != 0
                                    ? AppTheme.rougeErreur
                                    : AppTheme.violetProfond,
                              ),
                            ),
                            const StatusChip(
                              label: 'Verrouillée',
                              color: AppTheme.violetProfond,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
