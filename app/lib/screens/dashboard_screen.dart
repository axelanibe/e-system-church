import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/mere_badge.dart';
import '../widgets/screen_header.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'annonces_screen.dart';
import 'annexes_screen.dart';
import 'finances_mere_screen.dart';
import 'membres_screen.dart';
import 'mes_eglises_screen.dart';
import 'plateforme_screen.dart';

class _DashboardData {
  final int membresTotal;
  final Map<String, ContributionTotals> totaux;
  final RapportConsolide? rapport;
  final int annoncesCount;

  const _DashboardData({
    required this.membresTotal,
    required this.totaux,
    required this.rapport,
    required this.annoncesCount,
  });
}

/// Tableau de bord : chiffres de mon église + consolidé du réseau
/// (`GET /rapports/consolide`, admin de la mère seulement).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final state = context.read<AppState>();
    final api = state.api;
    final membres = await api.getMembers();
    Map<String, ContributionTotals> totaux = {};
    if (state.canReadFinances) {
      final page = await api.getContributions();
      totaux = page.totaux;
    }
    RapportConsolide? rapport;
    if (state.isAdmin) {
      try {
        rapport = await api.getRapport();
      } catch (_) {
        rapport = null; // Une sous-église admin n'a pas de réseau : on ignore.
      }
    }
    final annonces = await api.getAnnonces();
    return _DashboardData(
      membresTotal: membres.total,
      totaux: totaux,
      rapport: rapport,
      annoncesCount: annonces.length,
    );
  }

  int _totalEntrees(Map<String, ContributionTotals> totaux) {
    var sum = 0;
    for (final entry in totaux.entries) {
      if (entry.key != 'depense') sum += entry.value.totalFcfa;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _future = _load());
        await _future;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EnteteEcran(
                  titre: 'Accueil',
                  sousTitre: 'Voici votre église en un coup d’œil.',
                ),
                SoftCard(
                  color: AppTheme.sable,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChurchAvatar(church: church, radius: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  church?.name ?? '—',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${church?.code ?? ''} · ${church?.city ?? ''} · ${state.roleLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (church?.isMere ?? false) ...[
                                  const SizedBox(height: 8),
                                  const Row(
                                    children: [
                                      MereBadge(),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Tête de votre réseau.',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Changer d'église : l'écran dédié « Mes églises »
                      // est paginé et cherchable, il remplace la liste
                      // complète qui était dans le tiroir.
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const MesEglisesScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.swap_horiz_outlined),
                          label: const Text('Changer d’église'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Guide de première prise en main : un nouveau
                // responsable sait quoi faire, sans aide et sans jargon.
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Par où commencer ?',
                        style:
                            Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          'Trois gestes suffisent pour prendre '
                          'l’application en main.'),
                      const SizedBox(height: 12),
                      const _GuideEtape(
                        numero: '1',
                        texte: 'Regardez vos chiffres ci-dessous : '
                            'membres, argent reçu, argent dépensé.',
                      ),
                      const _GuideEtape(
                        numero: '2',
                        texte: 'Ouvrez « Membres » en bas de l’écran '
                            'pour voir vos personnes et leurs fiches.',
                      ),
                      const _GuideEtape(
                        numero: '3',
                        texte: 'Ouvrez « Réseau » pour voir les églises '
                            'rattachées à la vôtre.',
                      ),
                      const SizedBox(height: 12),
                      BoutonAvecAide(
                        label: 'Voir mes membres',
                        aide: 'La liste de toutes les personnes de votre '
                            'église, avec leurs fiches.',
                        icon: Icons.people_outlined,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MembresScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (state.isSuperAdmin)
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toute la plateforme',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            'Chiffres globaux de toutes les églises mères '
                            'ensemble, sans détail nominatif.'),
                        const SizedBox(height: 12),
                        BoutonAvecAide(
                          label: 'Voir les chiffres de la plateforme',
                          aide: 'Le total de toutes les églises, sans '
                              'voir les noms des personnes.',
                          icon: Icons.public_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PlateformeScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                if (state.isSuperAdmin) const SizedBox(height: 16),
                FutureBuilder<_DashboardData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: AppLoading(),
                      );
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: () =>
                            setState(() => _future = _load()),
                      );
                    }
                    final data = snapshot.data!;
                    final entrees = _totalEntrees(data.totaux);
                    final depenses =
                        data.totaux['depense']?.totalFcfa ?? 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionTitle(title: 'Mon église'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount =
                                constraints.maxWidth > 600 ? 4 : 2;
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              // 1,0 : les cartes portent un libellé et
                              // une courte explication, elles sont hautes.
                              childAspectRatio: 1.0,
                              children: [
                                StatCard(
                                  label: 'Membres',
                                  value: '${data.membresTotal}',
                                  icon: Icons.people_outline,
                                  aide: 'Personnes inscrites dans votre '
                                      'église.',
                                ),
                                StatCard(
                                  label: 'Argent reçu',
                                  value: formatFcfa(entrees),
                                  icon: Icons.trending_up,
                                  color: AppTheme.cypress,
                                  aide: 'Montants confirmés par la '
                                      'structure.',
                                ),
                                StatCard(
                                  label: 'Argent dépensé',
                                  value: formatFcfa(depenses),
                                  icon: Icons.trending_down,
                                  color: AppTheme.rougeErreur,
                                  aide: 'Dépenses confirmées par la '
                                      'structure.',
                                ),
                                StatCard(
                                  label: 'Annonces',
                                  value: '${data.annoncesCount}',
                                  icon: Icons.campaign_outlined,
                                  aide: 'Messages publiés pour votre '
                                      'église. Touchez pour les lire.',
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AnnoncesScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        if (data.rapport != null) ...[
                          const SectionTitle(
                              title: 'Mes églises rattachées'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total de mes églises',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    '${data.rapport!.totauxReseau.membresActifs} membres actifs · '
                                    '${data.rapport!.totauxReseau.nombreContributions} contributions · '
                                    '${formatFcfa(data.rapport!.totauxReseau.totalFcfa)}'),
                                const SizedBox(height: 12),
                                const Divider(),
                                ...data.rapport!.sousEglises.map(
                                  (s) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.account_tree_outlined),
                                    title: Text(s.egliseNom),
                                    subtitle: Text(
                                        '${s.membresActifs} membres · ${formatFcfa(s.totalFcfa)}'
                                        '${s.niveau == 1 ? '' : ' · niveau ${s.niveau}'}'),
                                    trailing: Text(
                                        '${s.nombreContributions} contributions'),
                                  ),
                                ),
                                if (data.rapport!.sousEglises.isEmpty)
                                  const Text(
                                      'Aucune église rattachée pour l’instant. Créez-en une depuis « Réseau ».'),
                                const SizedBox(height: 12),
                                BoutonAvecAide(
                                  label: 'Voir les finances en détail',
                                  aide: 'Chaque entrée et chaque dépense, '
                                      'église par église.',
                                  icon: Icons.account_balance_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const FinancesMereScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                BoutonAvecAide(
                                  label: 'Voir mes annexes',
                                  aide: 'Les églises annexes rattachées à '
                                      'la vôtre, et leurs codes.',
                                  icon: Icons.hub_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AnnexesScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une étape du guide de première prise en main : numéro dans un rond
/// cyprès, phrase courte, sans jargon.
class _GuideEtape extends StatelessWidget {
  final String numero;
  final String texte;

  const _GuideEtape({required this.numero, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.cypress,
            child: Text(
              numero,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(texte)),
        ],
      ),
    );
  }
}
