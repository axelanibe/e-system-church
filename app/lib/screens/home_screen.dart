import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/short_drawer.dart';
import 'dashboard_screen.dart';
import 'familles_screen.dart';
import 'finances_screen.dart';
import 'membres_screen.dart';

/// Coquille principale après connexion : 4 destinations.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre
/// inférieure de 4 libellés courts. Réseau et Annonces ne sont plus
/// des onglets : ils restent accessibles par le tiroir court et par
/// le tableau de bord (« Mon réseau », « Annonces récentes »),
/// qui les montrent directement, sans déplacement inutile.
/// L'AppBar montre le titre de l'écran seul, une ligne, coupé avec
/// « … ». Le tiroir court ne montre que l'église courante, « Changer
/// d'église » ouvre l'écran dédié « Mes églises » (paginé et
/// cherchable), et il garde les entrées « Réseau », « Annonces »,
/// « Mon église », « Demandes de rattachement », « Mes annexes »,
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
    'Membres',
    'Finances',
    'Départements',
  ];

  /// Chaque écran reçoit une clé liée à l'église active : après une
  /// bascule d'église, HomeScreen reste monté et les écrans garderaient
  /// sinon leur Future d'avant (données de l'église précédente). La clé
  /// changeante recrée l'écran, donc son chargement, sans refaire la
  /// navigation. Vaut pour les 4 écrans à Future en initState
  /// (Accueil, Membres, Finances, Familles).
  Widget _screenFor(int index, String? egliseId) {
    final cle = ValueKey(egliseId);
    switch (index) {
      case 0:
        return DashboardScreen(key: cle);
      case 1:
        return MembresScreen(key: cle);
      case 2:
        return FinancesScreen(key: cle);
      case 3:
        return FamillesScreen(key: cle, ongletInitial: 1);
      default:
        return DashboardScreen(key: cle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 900;

    // Libellés courts, une ligne : « Accueil », « Membres »,
    // « Finances », « Départements ». Les titres complets restent
    // dans _titles. Le hub « Modules » reste accessible par le
    // tiroir court, il n'est plus un onglet (copie de l'artefact).
    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Accueil'),
      NavigationDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: 'Membres'),
      NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Finances'),
      NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Départements'),
    ];

    // Tous les modules sont affichés pour toutes les églises (règle
    // du 11/11/2026) : plus de destination masquée.
    final courant = _index.clamp(0, _titles.length - 1);

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
              destinations: destinations,
              selectedIndex: courant,
              onDestinationSelected: (i) => setState(() => _index = i),
            ),
    );
  }
}
