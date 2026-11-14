import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Transparence financière agrégée côté membre (US8) : totaux par type
/// et dépenses par poste, sans aucune ligne nominative. Une annexe voit
/// les chiffres de sa mère. La visibilité aux membres se règle par
/// église (désactivée par défaut, bureau seulement) ; le serveur refuse
/// sinon, l'écran l'explique.
class TransparenceScreen extends StatefulWidget {
  const TransparenceScreen({super.key});

  @override
  State<TransparenceScreen> createState() => _TransparenceScreenState();
}

class _TransparenceScreenState extends State<TransparenceScreen> {
  late Future<Transparence> _future;
  String _periode = DateTime.now().toIso8601String().substring(0, 7);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Transparence> _load() =>
      context.read<AppState>().api.getTransparence(periode: _periode);

  void _refresh() => setState(() => _future = _load());

  Future<void> _choisirPeriode() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse('$_periode-01') ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _periode = choisie.toIso8601String().substring(0, 7);
      _refresh();
    });
  }

  String _libelleType(String type) => switch (type) {
        'dime' => 'Dîme',
        'offrande' => 'Offrande',
        'don' => 'Don',
        'cotisation' => 'Cotisation',
        'campagne' => 'Campagne',
        'depense' => 'Dépense',
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    final devise = context.watch<AppState>().devise;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.transparence),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: _periode,
            onPressed: _choisirPeriode,
          ),
        ],
      ),
      body: FutureBuilder<Transparence>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            final message = snapshot.error.toString();
            if (message.contains('transparence')) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t.nonActivee, textAlign: TextAlign.center),
                ),
              );
            }
            return AppError(message: t.erreurChargement, onRetry: _refresh);
          }
          final d = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${d.eglise} · $_periode',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  t.sansLigneNominative,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: t.recettes,
                        value: formatMontant(d.totalRecettesFcfa, devise),
                        icon: Icons.trending_up,
                        color: AppTheme.bleuNuit,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: t.depenses,
                        value: formatMontant(d.totalDepensesFcfa, devise),
                        icon: Icons.trending_down,
                        color: AppTheme.rougeErreur,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StatCard(
                  label: t.solde,
                  value: formatMontant(d.soldeFcfa, devise),
                  icon: Icons.account_balance_wallet_outlined,
                  color: d.soldeFcfa < 0
                      ? AppTheme.rougeErreur
                      : AppTheme.bleuNuit,
                ),
                const SizedBox(height: 20),
                SectionTitle(title: t.parType),
                Card(
                  child: Column(
                    children: d.totauxParType
                        .map((l) => ListTile(
                              title: Text(_libelleType(l.type)),
                              subtitle: Text('${l.nombre}'),
                              trailing: Text(
                                formatMontant(l.totalFcfa, devise),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                SectionTitle(title: t.parPoste),
                Card(
                  child: Column(
                    children: d.depensesParPoste
                        .map((l) => ListTile(
                              title: Text(l.poste,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: Text(
                                formatMontant(l.totalFcfa, devise),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ))
                        .toList(),
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
