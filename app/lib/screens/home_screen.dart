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

/// Coquille principale après connexion : navigation entre les écrans.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre
/// inférieure de 5 libellés courts maximum. Les annonces, sixième
/// entrée, restent accessibles par le tiroir court et par le tableau
/// de bord : rien n'est supprimé, l'entrée change seulement de place.
/// L'AppBar montre le titre de l'écran seul, une ligne, coupé avec
/// « … ». Le tiroir court ne montre que l'église courante, « Changer
/// d'église » ouvre un écran dédié.
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

  /// Code du module US1 par destination, ou null (toujours visible). Seules
  /// les annonces sont un module activable dans cette navigation.
  static const List<String?> _modules = [
    null,
    null,
    null,
    null,
    'annonces',
    null,
  ];

  Widget _screenFor(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const TreeScreen();
      case 2:
        return const MembresScreen();
      case 3:
        return const FinancesScreen();
      case 4:
        return const AnnoncesScreen();
      case 5:
        return const ModulesScreen();
      default:
        return const DashboardScreen();
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

    // US1 : les destinations des modules désactivés disparaissent de la
    // navigation. `courant` est la destination réelle affichée.
    final visibles = <int>[];
    for (var i = 0; i < _titles.length; i++) {
      final code = _modules[i];
      if (code == null || state.isModuleActif(code)) visibles.add(i);
    }
    final courant = visibles[_index.clamp(0, visibles.length - 1)];
    final dests = visibles.map((i) => destinations[i]).toList();

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
        onAller: (i) => setState(() => _index = visibles.indexOf(i)),
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: visibles.indexOf(courant),
              onDestinationSelected: (i) =>
                  setState(() => _index = visibles[i]),
              labelType: NavigationRailLabelType.all,
              destinations: dests
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          Expanded(child: _screenFor(courant)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : BarreDuBas(
              destinations: barDests,
              selectedIndex: barSelected,
              onDestinationSelected: (i) => setState(
                  () => _index = visibles.indexOf(barIndices[i])),
            ),
    );
  }
}
