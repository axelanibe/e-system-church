import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';

/// Rapprochement bancaire par canal (tranche T7) : pour chaque canal
/// (Wave, Orange Money, MTN, espèces, virement, chèque), ce qui aurait
/// dû entrer ou sortir contre ce qui est comptabilisé en caisse. Un
/// écart signale des écritures manuelles ou des mouvements d'avant la
/// T7, sans écriture automatique. Les mouvements sans canal sont
/// regroupés en « Non ventilé » : rien n'est caché.
class RapprochementScreen extends StatefulWidget {
  const RapprochementScreen({super.key});

  @override
  State<RapprochementScreen> createState() => _RapprochementScreenState();
}

class _RapprochementScreenState extends State<RapprochementScreen> {
  late Future<Rapprochement> _future;
  int _annee = DateTime.now().year;
  int _mois = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<Rapprochement> _charger() => context
      .read<AppState>()
      .api
      .getRapprochement(annee: _annee, mois: _mois);

  void _refresh() => setState(() => _future = _charger());

  void _moisPrecedent() {
    setState(() {
      if (_mois == 1) {
        _mois = 12;
        _annee -= 1;
      } else {
        _mois -= 1;
      }
      _future = _charger();
    });
  }

  void _moisSuivant() {
    setState(() {
      if (_mois == 12) {
        _mois = 1;
        _annee += 1;
      } else {
        _mois += 1;
      }
      _future = _charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rapprochement')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'Votre rôle ne donne pas accès aux finances de l’église.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rapprochement')),
      body: FutureBuilder<Rapprochement>(
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
          final rapp = snapshot.data!;
          final totaux = rapp.totaux;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _moisPrecedent,
                      tooltip: 'Mois précédent',
                    ),
                    Text(
                      libellePeriodeMois(rapp.periode),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _moisSuivant,
                      tooltip: 'Mois suivant',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                          label: 'Attendu',
                          value: formatMontant(
                              totaux.attenduFcfa, state.devise),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'En caisse',
                          value: formatMontant(
                              totaux.caisseNetFcfa, state.devise),
                          icon: Icons.trending_up,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Écart total',
                          value: formatMontant(
                              totaux.ecartFcfa, state.devise),
                          icon: Icons.swap_horiz,
                          color: totaux.ecartFcfa != 0
                              ? AppTheme.rougeErreur
                              : AppTheme.bleuNuit,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Par canal'),
                ...rapp.canaux.map(
                  (ligne) => RapprochementCanalTile(
                    ligne: ligne,
                    devise: state.devise,
                  ),
                ),
                RapprochementCanalTile(
                  ligne: rapp.nonVentile,
                  devise: state.devise,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Un écart signale des écritures manuelles ou des mouvements antérieurs à la mise en place du rapprochement, sans écriture automatique. Les mouvements sans canal sont regroupés en « Non ventilé ».',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Une ligne du rapprochement : canal, attendu, caisse, et écart mis
/// en avant quand il n'est pas nul.
class RapprochementCanalTile extends StatelessWidget {
  final LigneRapprochement ligne;
  final String devise;

  const RapprochementCanalTile({
    super.key,
    required this.ligne,
    required this.devise,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text(ligne.canalLabel),
        subtitle: Text(
          'Attendu : ${formatMontant(ligne.attenduFcfa, devise)}'
          ' · Caisse : ${formatMontant(ligne.caisseNetFcfa, devise)}\n'
          'Entrées confirmées : ${formatMontant(ligne.entreesConfirmeesFcfa, devise)}'
          ' · Sorties payées : ${formatMontant(ligne.sortiesPayeesFcfa, devise)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMontant(ligne.ecartFcfa, devise),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ligne.alerte
                    ? AppTheme.rougeErreur
                    : AppTheme.bleuNuit,
              ),
            ),
            if (ligne.alerte)
              const StatusChip(
                label: 'Écart',
                color: AppTheme.rougeErreur,
              ),
          ],
        ),
      ),
    );
  }
}
