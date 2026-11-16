import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';
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
  final List<CompteBancaire> comptes;

  const _DonneesHub({
    required this.suiviCotisations,
    required this.solde,
    required this.entreesJour,
    required this.sortiesJour,
    required this.rapprochement,
    required this.clotures,
    required this.nombreRecus,
    required this.comptes,
  });
}

/// Contenu de l'onglet « Finances complètes » (tranche T7) :
/// indicateurs du mois et de la caisse, puis une carte par fonction
/// (cotisations, comptes bancaires, rapprochement, clôture, reçus),
/// chacune ouvrant son écran. Les budgets par département vivent dans
/// l'onglet Départements (maquette, un seul accès aux budgets :
/// « Budget & caisse » depuis Finances). Le rôle
/// « membre » simple n'a pas accès à cet écran.
class ContenuFinancesCompletes extends StatefulWidget {
  const ContenuFinancesCompletes({super.key});

  @override
  State<ContenuFinancesCompletes> createState() =>
      _ContenuFinancesCompletesState();
}

class _ContenuFinancesCompletesState
    extends State<ContenuFinancesCompletes> {
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
      comptes: results[6] as List<CompteBancaire>,
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
    return FutureBuilder<_DonneesHub>(
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
          // On ne clôture qu'un mois terminé, jamais le mois en cours.
          final aCloturer = dernierMoisTermine();
          final cloturee =
              d.clotures.any((c) => c.periode == aCloturer);
          final suivi = d.suiviCotisations;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // Une seule grille de chiffres : celle de l'onglet
                // Contributions (maquette écrans 2–3). Le panneau
                // « Finances complètes » de la maquette n'a pas de
                // grille : celle-ci, identique, est supprimée. E8.
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
                  titre: 'Clôture de période',
                  texte: d.clotures.isEmpty
                      ? 'Aucune période clôturée.'
                      : 'Dernière clôture : ${libellePeriodeMois(d.clotures.first.periode)}',
                  badge: cloturee ? 'Clôturé' : 'Ouvert',
                  badgeColor:
                      cloturee ? AppTheme.vertFonce : Colors.grey,
                  infoLabel: 'Période à clôturer :',
                  infoValeur: libellePeriodeMois(aCloturer),
                  actionLabel: 'Clôturer la période',
                  onTap: () => _ouvrir(const ClotureCaisseScreen()),
                ),
                _CarteFonction(
                  icone: Icons.receipt_long_outlined,
                  titre: 'Reçus numérotés',
                  texte: '',
                  badge: pluriel(d.nombreRecus, 'reçu'),
                  onTap: () => _ouvrir(const RecusScreen()),
                ),
                // Maquette, écrans 2–3 : les budgets vivent dans
                // « Budget & caisse », onglet Contributions.
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Budgets : « Budget & caisse », onglet Contributions.',
                    style: TextStyle(fontSize: 12.5),
                  ),
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
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        // Maquette, écrans 2–3 : sous-titre SYCEBNL.
                        const Text(
                          'Bilan, compte de résultat, flux de trésorerie',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () =>
                              _ouvrir(const SycebnlScreen()),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Ouvrir l’export SYCEBNL', style: TextStyle(fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
  }
}

/// Une carte de fonction de l'écran Finances complètes : titre, texte,
/// et valeur, badge ou action selon la fonction. Mise en page
/// horizontale : le texte prend toute la largeur restante, le bouton
/// d'action est en dessous, jamais en trailing d'un ListTile (la carte
/// Clôture s'affichait en colonne d'une lettre avec un ListTile).
class _CarteFonction extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String texte;
  final String? sousTexte;
  final String? valeur;
  final bool valeurAlerte;
  final String? badge;
  final Color? badgeColor;
  final String? infoLabel;
  final String? infoValeur;
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
    this.badgeColor,
    this.infoLabel,
    this.infoValeur,
    this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icone, color: AppTheme.violetProfond),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titre,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(texte, style: const TextStyle(fontSize: 11.5)),
                        if (sousTexte != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            sousTexte!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (valeur != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      valeur!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: valeurAlerte
                            ? AppTheme.rougeErreur
                            : AppTheme.vertFonce,
                      ),
                    ),
                  ] else if (badge != null) ...[
                    const SizedBox(width: 12),
                    StatusChip(
                      label: badge!,
                      color: badgeColor ?? AppTheme.violetProfond,
                    ),
                  ] else if (actionLabel == null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right),
                  ],
                ],
              ),
              if (infoLabel != null && infoValeur != null) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.fondPapier,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        infoLabel!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        infoValeur!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onTap,
                    child: Text(actionLabel!, style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
