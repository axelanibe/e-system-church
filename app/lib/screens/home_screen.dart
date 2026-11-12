import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/short_drawer.dart';
import 'annonces_screen.dart';
import 'dashboard_screen.dart';
import 'finances_screen.dart';
import 'membres_screen.dart';
import 'modules_screen.dart';
import 'tree_screen.dart';

/// Coquille principale après connexion : navigation entre les 6 écrans.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre
/// inférieure de 5 libellés courts maximum. Les annonces, sixième
/// entrée, restent accessibles par le tiroir court et par le tableau
/// de bord : rien n'est supprimé, l'entrée change seulement de place.
/// L'AppBar montre le titre de l'écran seul, une ligne, coupé avec
/// « … ». Le tiroir court ne montre que l'église courante, « Changer
/// d'église » ouvre l'écran dédié « Mes églises » (paginé et
/// cherchable), et il garde les entrées « Mon église », « Modules de
/// l'église », « Demandes de rattachement », « Mes annexes »,
/// « Plateforme », « Transferts de membres » et « Finances de la mère ».
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = [
    'Accueil',
    'Réseau',
    'Membres',
    'Finances',
    'Annonces',
    'Modules',
  ];

  /// Chaque écran reçoit une clé liée à l'église active : après une
  /// bascule d'église, HomeScreen reste monté et les écrans garderaient
  /// sinon leur Future d'avant (données de l'église précédente). La clé
  /// changeante recrée l'écran, donc son chargement, sans refaire la
  /// navigation. Vaut pour les 5 écrans à Future en initState
  /// (Accueil, Réseau, Membres, Finances, Annonces) ; ModulesScreen est
  /// sans état et lit déjà l'état courant.
  Widget _screenFor(int index, String? egliseId) {
    final cle = ValueKey(egliseId);
    switch (index) {
      case 0:
        return DashboardScreen(key: cle);
      case 1:
        return TreeScreen(key: cle);
      case 2:
        return MembresScreen(key: cle);
      case 3:
        return FinancesScreen(key: cle);
      case 4:
        return AnnoncesScreen(key: cle);
      case 5:
        return ModulesScreen(key: cle);
      default:
        return DashboardScreen(key: cle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 900;

    // Libellés courts, une ligne : « Accueil », « Réseau », « Membres »,
    // « Finances », « Modules ». Les titres complets restent dans _titles.
    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Accueil'),
      NavigationDestination(
          icon: Icon(Icons.account_tree_outlined),
          selectedIcon: Icon(Icons.account_tree),
          label: 'Réseau'),
      NavigationDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: 'Membres'),
      NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Finances'),
      NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'Annonces'),
      NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Modules'),
    ];

    // Tous les modules sont affichés pour toutes les églises (règle
    // du 11/11/2026) : plus de destination masquée.
    final courant = _index.clamp(0, _titles.length - 1);

    // Barre du bas : 5 libellés maximum. Les annonces (index 4) n'y
    // figurent pas, elles restent dans le tiroir et le tableau de bord.
    const barIndices = [0, 1, 2, 3, 5];
    final barDests =
        barIndices.map((i) => destinations[i]).toList();
    final barSelected = barIndices.contains(courant)
        ? barIndices.indexOf(courant)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[courant],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      drawer: TiroirCourt(
        onAller: (i) => setState(() => _index = i),
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: courant,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          Expanded(child: _screenFor(courant, state.church?.id)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : BarreDuBas(
              destinations: barDests,
              selectedIndex: barSelected,
              onDestinationSelected: (i) =>
                  setState(() => _index = barIndices[i]),
            ),
    );
  }
}
