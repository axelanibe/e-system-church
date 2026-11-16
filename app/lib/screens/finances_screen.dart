import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'campagnes_screen.dart';
import 'contribution_form_screen.dart';
import 'attestations_annuelles_screen.dart';
import 'dons_nature_screen.dart';
import 'etat_comptes_marchands_screen.dart';
import 'finances_completes_screen.dart';
import 'finances_mere_screen.dart';
import 'nouvelle_depense_screen.dart';
import 'promesses_screen.dart';
import 'receipt_screen.dart';
import 'transparence_screen.dart';

/// Finances de mon église : totaux par type, liste avec filtres, ajout
/// d'une contribution, reçu avec confirmation / annulation.
/// Le rôle « membre » simple n'a pas accès à cet écran.
class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  String? _typeFilter;
  String? _statusFilter;
  /// Sous-onglet (maquette de refonte) : 0 Contributions,
  /// 1 Finances complètes.
  int _sousOnglet = 0;
  late Future<ContributionPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ContributionPage> _load() {
    return context.read<AppState>().api.getContributions(
          type: _typeFilter,
          status: _statusFilter,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _openForm() async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) =>
              const ContributionFormScreen(initialType: 'cotisation')),
    );
    if (created != null && mounted) {
      showSuccess(
        context,
        created == 'depense'
            ? 'Dépense enregistrée (en attente).'
            : 'Contribution enregistrée (en attente).',
      );
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirme':
        return AppTheme.violetProfond;
      case 'en_attente':
        return Colors.orange;
      case 'annule':
        return AppTheme.rougeErreur;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.canReadFinances) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message:
            'Votre rôle ne donne pas accès aux finances de l’église.',
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Maquette, écrans 2–3 : sous-titre de l'écran Finances. E8.
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Contributions, caisse et clôtures de l’église.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _SousOnglets(
              index: _sousOnglet,
              onChange: (i) => setState(() {
                _sousOnglet = i;
                if (i == 0) _future = _load();
              }),
            ),
          ),
          Expanded(
            child: _sousOnglet == 1
                ? const ContenuFinancesCompletes()
                : FutureBuilder<ContributionPage>(
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
                final page = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    // Marge basse pour le bouton flottant « Ajouter »,
                    // qui recouvrait sinon le contenu en bas d'écran.
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      // Les 4 chiffres de la projection (Cotisations du
                      // mois, Caisse, Entrées et Sorties du jour) en
                      // tête du premier sous-onglet ; Finances complètes
                      // garde le détail. E-F0.
                      const _GrilleChiffres(),
                      const SizedBox(height: 16),
                      // Filtres en tête de liste : sous les cartes, ils
                      // défilaient dans la bande du bouton flottant, qui
                      // recouvrait une pastille à chaque arrêt. En tête,
                      // ils ne descendent jamais dans cette bande.
                      _FiltresDefilants(
                        enfants: [
                          for (final entry in <String, String?>{
                            'Tous types': null,
                            'Dîmes': 'dime',
                            'Offrandes': 'offrande',
                            'Dons': 'don',
                            'Dépenses': 'depense',
                            'Cotisations': 'cotisation',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.key, style: const TextStyle(fontSize: 12.5)),
                              selected: _typeFilter == entry.value,
                              onSelected: (_) {
                                setState(() {
                                  _typeFilter = entry.value;
                                  _future = _load();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _FiltresDefilants(
                        enfants: [
                          for (final entry in <String, String?>{
                            'Tous statuts': null,
                            'En attente': 'en_attente',
                            'Confirmées': 'confirme',
                            'Annulées': 'annule',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.key, style: const TextStyle(fontSize: 12.5)),
                              selected: _statusFilter == entry.value,
                              onSelected: (_) {
                                setState(() {
                                  _statusFilter = entry.value;
                                  _future = _load();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Une seule grille de chiffres : celle du haut
                      // (_GrilleChiffres, maquette écrans 2–3). La
                      // seconde grille (totaux par type : dîmes,
                      // offrandes, dons, dépenses), absente de la
                      // maquette, est supprimée. E8.
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.volunteer_activism_outlined),
                          title: const Text('Campagnes de collecte', style: TextStyle(fontSize: 13.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CampagnesScreen(
                                    initialTab: 0),
                              ),
                            );
                            _refresh();
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.handshake_outlined),
                          title: const Text('Promesses de don', style: TextStyle(fontSize: 13.5)),
                          subtitle:
                              const Text('Suivi des promesses',
                                  style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PromessesScreen(),
                              ),
                            );
                            _refresh();
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.card_giftcard_outlined),
                          title: const Text('Dons en nature', style: TextStyle(fontSize: 13.5)),
                          subtitle:
                              const Text('Enregistrement et suivi',
                                  style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DonsNatureScreen(),
                              ),
                            );
                            _refresh();
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.visibility_outlined),
                          title: const Text('Transparence financière', style: TextStyle(fontSize: 13.5)),
                          subtitle:
                              const Text('Ce que les membres voient',
                                  style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TransparenceScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.account_balance_outlined),
                          title: const Text('Budget & caisse', style: TextStyle(fontSize: 13.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CampagnesScreen(
                                    initialTab: 1),
                              ),
                            );
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.receipt_long_outlined),
                          title: const Text('Dépenses', style: TextStyle(fontSize: 13.5)),
                          subtitle:
                              const Text('Saisie d’une dépense',
                                  style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const NouvelleDepenseScreen(),
                              ),
                            );
                            _refresh();
                          },
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.store_outlined),
                          title: const Text('État des comptes marchands', style: TextStyle(fontSize: 13.5)),
                          subtitle: const Text(
                              'Wave, Orange Money, MTN — consultation seulement · Configuration et clés : Réglages uniquement.',
                              style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const EtatComptesMarchandsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      if (state.church?.isMere ?? false)
                        Card(
                          child: ListTile(
                            leading:
                                const Icon(Icons.account_tree_outlined),
                            title:
                                const Text('Finances des annexes',
                                    style: TextStyle(fontSize: 13.5)),
                            subtitle: const Text(
                                'Totaux par annexe, lecture seule · Gestion des annexes : Mes annexes',
                                style: TextStyle(fontSize: 11.5)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const FinancesMereScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      // Maquette, écrans 2–3 : « Attestations annuelles »
                      // est une carte de la liste, comme les autres
                      // fonctions, avec son sous-titre, pas un bouton
                      // à part. E8.
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.description_outlined),
                          title: const Text('Attestations annuelles',
                              style: TextStyle(fontSize: 13.5)),
                          subtitle: const Text(
                              'Total des cotisations de l’année',
                              style: TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AttestationsAnnuellesScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (page.contributions.isEmpty)
                        EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          message: switch (_typeFilter) {
                            'depense' => 'Aucune dépense trouvée.',
                            'dime' => 'Aucune dîme trouvée.',
                            'offrande' => 'Aucune offrande trouvée.',
                            'don' => 'Aucun don trouvé.',
                            _ => 'Aucune contribution pour l’instant.',
                          },
                        )
                      else
                        ...page.contributions.map(
                          (c) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  c.type == 'depense'
                                      ? Icons.remove
                                      : Icons.add,
                                ),
                              ),
                              title: Text(
                                  '${c.typeLabel} — ${formatFcfa(c.amountFcfa)}',
                                  style: const TextStyle(fontSize: 13.5)),
                              subtitle: Text(
                                  '${c.paymentLabel}${c.membreNom != null ? ' · ${c.membreNom}' : ''} · ${formatDate(c.createdAt)}',
                                  style: const TextStyle(fontSize: 11.5)),
                              trailing: StatusChip(
                                label: c.statusLabel,
                                color: _statusColor(c.status),
                              ),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ReceiptScreen(contributionId: c.id),
                                  ),
                                );
                                _refresh();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _sousOnglet == 0 && state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter', style: TextStyle(fontSize: 13.5)),
            )
          : null,
    );
  }
}

/// Sous-onglets Contributions / Finances complètes (maquette de
/// refonte) : segment actif en carte blanche sur fond gris.
class _SousOnglets extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;

  const _SousOnglets({required this.index, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bordure.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: index == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: index == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    i == 0 ? 'Contributions' : 'Finances complètes',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight:
                          index == i ? FontWeight.bold : FontWeight.normal,
                      color: index == i
                          ? AppTheme.violetProfond
                          : AppTheme.violetProfond.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rangée de pastilles en défilement horizontal (maquette de refonte) :
/// fini l'empilement de boutons, les pastilles défilent.
class _FiltresDefilants extends StatelessWidget {
  final List<Widget> enfants;

  const _FiltresDefilants({required this.enfants});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < enfants.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            enfants[i],
          ],
          // Marge de fin : sans elle la dernière pastille est
          // tronquée en plein mot au bord droit de l'écran.
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// Les 4 chiffres de la projection en tête des Contributions (E-F0) :
/// mêmes appels et mêmes cartes que Finances complètes, sans les
/// sections détaillées. La grille apparaît une fois les chiffres
/// reçus ; en cas d'erreur, un message avec réessai, sans bloquer
/// la liste des contributions.
class _GrilleChiffres extends StatefulWidget {
  const _GrilleChiffres();

  @override
  State<_GrilleChiffres> createState() => _GrilleChiffresState();
}

class _Chiffres {
  final SuiviCotisations suivi;
  final CaisseSolde solde;
  final int entreesJour;
  final int sortiesJour;

  const _Chiffres({
    required this.suivi,
    required this.solde,
    required this.entreesJour,
    required this.sortiesJour,
  });
}

class _GrilleChiffresState extends State<_GrilleChiffres> {
  late Future<_Chiffres> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<_Chiffres> _charger() async {
    final api = context.read<AppState>().api;
    final maintenant = DateTime.now();
    final results = await Future.wait([
      api.getCotisationsSuivi(),
      api.getCaisseSolde(),
      api.getCaisseMouvements(),
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
    return _Chiffres(
      suivi: results[0] as SuiviCotisations,
      solde: results[1] as CaisseSolde,
      entreesJour: entreesJour,
      sortiesJour: sortiesJour,
    );
  }

  void _refresh() => setState(() => _future = _charger());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<_Chiffres>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Chiffres indisponibles : ${snapshot.error}',
                  style: const TextStyle(color: AppTheme.rougeErreur),
                ),
              ),
              TextButton(
                onPressed: _refresh,
                child: const Text('Réessayer'),
              ),
            ],
          );
        }
        final d = snapshot.data!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.9,
              children: [
                StatCard(
                  label: 'Cotisations du mois',
                  value: formatMontant(
                      d.suivi.totaux.totalPayeFcfa, state.devise),
                  icon: Icons.payments_outlined,
                  color: AppTheme.violetProfond,
                ),
                StatCard(
                  label: 'Caisse',
                  value: formatMontant(d.solde.solde, state.devise),
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppTheme.violetProfond,
                ),
                StatCard(
                  label: 'Entrées du jour',
                  value: formatMontant(d.entreesJour, state.devise),
                  icon: Icons.trending_up,
                  color: AppTheme.violetProfond,
                ),
                StatCard(
                  label: 'Sorties du jour',
                  value: formatMontant(d.sortiesJour, state.devise),
                  icon: Icons.trending_down,
                  color: AppTheme.violetProfond,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
