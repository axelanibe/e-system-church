import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';
import 'budgets_departements_screen.dart';
import 'cloture_caisse_screen.dart';
import 'comptes_bancaires_screen.dart';
import 'cotisations_admin_screen.dart';
import 'rapprochement_screen.dart';
import 'recus_screen.dart';
import 'sycebnl_screen.dart';

/// Données de l'écran « Finances complètes » (tranche T7) : chaque carte
/// reprend les chiffres réels du serveur, rien n'est inventé.
class _DonneesHub {
  final SuiviCotisations suiviCotisations;
  final CaisseSolde solde;
  final int entreesJour;
  final int sortiesJour;
  final Rapprochement rapprochement;
  final List<ClotureCaisse> clotures;
  final int nombreRecus;
  final SuiviDepartements suiviDepartements;
  final List<CompteBancaire> comptes;

  const _DonneesHub({
    required this.suiviCotisations,
    required this.solde,
    required this.entreesJour,
    required this.sortiesJour,
    required this.rapprochement,
    required this.clotures,
    required this.nombreRecus,
    required this.suiviDepartements,
    required this.comptes,
  });
}

/// Finances complètes (tranche T7, projection validée) : indicateurs du
/// mois et de la caisse, puis une carte par fonction (cotisations,
/// comptes bancaires, rapprochement, clôture, reçus, budgets par
/// département), chacune ouvrant son écran. Le rôle « membre » simple
/// n'a pas accès à cet écran.
class FinancesCompletesScreen extends StatefulWidget {
  const FinancesCompletesScreen({super.key});

  @override
  State<FinancesCompletesScreen> createState() =>
      _FinancesCompletesScreenState();
}

class _FinancesCompletesScreenState extends State<FinancesCompletesScreen> {
  late Future<_DonneesHub> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<_DonneesHub> _charger() async {
    final api = context.read<AppState>().api;
    final maintenant = DateTime.now();
    final results = await Future.wait([
      api.getCotisationsSuivi(),
      api.getCaisseSolde(),
      api.getCaisseMouvements(),
      api.getRapprochement(),
      api.getCloturesCaisse(),
      api.getContributions(status: 'confirme'),
      api.getSuiviDepartements(
          annee: maintenant.year, mois: maintenant.month),
      api.getComptesBancaires(),
    ]);
    final mouvements = results[2] as List<CaisseMouvement>;
    final aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    var entreesJour = 0;
    var sortiesJour = 0;
    for (final m in mouvements) {
      final date = m.createdAt?.toLocal();
      if (date == null) continue;
      if (date.year == aujourdHui.year &&
          date.month == aujourdHui.month &&
          date.day == aujourdHui.day) {
        if (m.type == 'entree') {
          entreesJour += m.montantFcfa;
        } else {
          sortiesJour += m.montantFcfa;
        }
      }
    }
    final page = results[5] as ContributionPage;
    // Nombre de reçus : contributions confirmées avec reçu. Le total
    // « depense » mélange les dépenses du module Budget et caisse, qui
    // n'ont pas de reçu : on ne compte que dîmes, offrandes, dons et
    // cotisations.
    var nombreRecus = 0;
    for (final type in ['dime', 'offrande', 'don', 'cotisation']) {
      nombreRecus += page.totaux[type]?.nombre ?? 0;
    }
    return _DonneesHub(
      suiviCotisations: results[0] as SuiviCotisations,
      solde: results[1] as CaisseSolde,
      entreesJour: entreesJour,
      sortiesJour: sortiesJour,
      rapprochement: results[3] as Rapprochement,
      clotures: results[4] as List<ClotureCaisse>,
      nombreRecus: nombreRecus,
      suiviDepartements: results[6] as SuiviDepartements,
      comptes: results[7] as List<CompteBancaire>,
    );
  }

  void _refresh() => setState(() => _future = _charger());

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
    if (mounted) _refresh();
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
      appBar: AppBar(title: const Text('Finances complètes')),
      body: FutureBuilder<_DonneesHub>(
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
          final d = snapshot.data!;
          final suivi = d.suiviCotisations;
          final budgetsDefinis = d.suiviDepartements.parDepartements
              .where((l) => l.budgetDefini)
              .length;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        constraints.maxWidth > 600 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          label: 'Cotisations du mois',
                          value: formatMontant(
                              suivi.totaux.totalPayeFcfa, state.devise),
                          icon: Icons.payments_outlined,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Caisse',
                          value:
                              formatMontant(d.solde.solde, state.devise),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Entrées du jour',
                          value: formatMontant(d.entreesJour, state.devise),
                          icon: Icons.trending_up,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Sorties du jour',
                          value: formatMontant(d.sortiesJour, state.devise),
                          icon: Icons.trending_down,
                          color: AppTheme.rougeErreur,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _CarteFonction(
                  icone: Icons.payments_outlined,
                  titre: 'Cotisations',
                  texte: suivi.configAbsente
                      ? 'Aucune cotisation reçue'
                      : '${suivi.totaux.membresPayes} membre(s) payé(s) sur ${suivi.totaux.membresTotal}',
                  sousTexte:
                      'Chaque cotisation reçue produira un reçu numéroté.',
                  onTap: () =>
                      _ouvrir(const CotisationsAdminScreen()),
                ),
                _CarteFonction(
                  icone: Icons.account_balance_outlined,
                  titre: 'Comptes bancaires',
                  texte: d.comptes.isEmpty
                      ? 'Aucun compte enregistré'
                      : pluriel(d.comptes.length, 'compte enregistré'),
                  sousTexte:
                      'Les comptes de la structure s’ajouteront ici pour le rapprochement.',
                  onTap: () =>
                      _ouvrir(const ComptesBancairesScreen()),
                ),
                _CarteFonction(
                  icone: Icons.swap_horiz,
                  titre: 'Rapprochement',
                  texte: 'Écart entre la caisse et la banque.',
                  valeur: formatMontant(
                      d.rapprochement.totaux.ecartFcfa, state.devise),
                  valeurAlerte: d.rapprochement.totaux.ecartFcfa != 0,
                  onTap: () => _ouvrir(const RapprochementScreen()),
                ),
                _CarteFonction(
                  icone: Icons.lock_outline,
                  titre: 'Clôture',
                  texte: d.clotures.isEmpty
                      ? 'Aucune période clôturée pour le moment.'
                      : 'Dernière clôture : ${d.clotures.first.periode}',
                  actionLabel: 'Clôturer',
                  onTap: () => _ouvrir(const ClotureCaisseScreen()),
                ),
                _CarteFonction(
                  icone: Icons.receipt_long_outlined,
                  titre: 'Reçus numérotés',
                  texte: 'Numérotation continue, sans trou.',
                  badge: pluriel(d.nombreRecus, 'reçu'),
                  onTap: () => _ouvrir(const RecusScreen()),
                ),
                _CarteFonction(
                  icone: Icons.calendar_month_outlined,
                  titre: 'Budgets par département',
                  texte: budgetsDefinis == 0
                      ? 'Aucun budget défini'
                      : '${pluriel(budgetsDefinis, 'budget défini')} · ${libellePeriodeMois('${d.suiviDepartements.annee}-${d.suiviDepartements.mois.toString().padLeft(2, '0')}')}',
                  sousTexte:
                      'Les budgets se créent par département, avec leur enveloppe en FCFA.',
                  onTap: () =>
                      _ouvrir(const BudgetsDepartementsScreen()),
                ),
                const SizedBox(height: 8),
                const SectionTitle(title: 'Déclarations et exports'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'États financiers SYCEBNL',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Bilan, compte de résultat, tableau des flux de trésorerie et notes annexes, à produire depuis votre comptabilité. L’export reste disponible pour toutes les églises, même quand le dépôt n’est pas imposé.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () =>
                              _ouvrir(const SycebnlScreen()),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Ouvrir l’export SYCEBNL'),
                        ),
                      ],
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

/// Une carte de fonction de l'écran Finances complètes : titre, texte,
/// et valeur, badge ou action selon la fonction.
class _CarteFonction extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String texte;
  final String? sousTexte;
  final String? valeur;
  final bool valeurAlerte;
  final String? badge;
  final String? actionLabel;
  final VoidCallback onTap;

  const _CarteFonction({
    required this.icone,
    required this.titre,
    required this.texte,
    this.sousTexte,
    this.valeur,
    this.valeurAlerte = false,
    this.badge,
    this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icone),
        title: Text(titre),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texte),
            if (sousTexte != null)
              Text(
                sousTexte!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: valeur != null
            ? Text(
                valeur!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: valeurAlerte
                      ? AppTheme.rougeErreur
                      : AppTheme.bleuNuit,
                ),
              )
            : badge != null
                ? StatusChip(
                    label: badge!,
                    color: AppTheme.bleuNuit,
                  )
                : actionLabel != null
                    ? OutlinedButton(
                        onPressed: onTap,
                        child: Text(actionLabel!),
                      )
                    : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
