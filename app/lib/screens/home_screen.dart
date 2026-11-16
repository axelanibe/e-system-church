import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/en_tete_clair.dart';
import '../widgets/short_drawer.dart';
import 'dashboard_screen.dart';
import 'modules_screen.dart';
import 'finances_screen.dart';
import 'membres_screen.dart';

/// Coquille principale après connexion : 4 destinations.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre
/// inférieure de 4 libellés courts. Réseau et Annonces ne sont plus
/// des onglets : ils restent accessibles par le tableau de bord
/// (« Mes annexes », « Annonces récentes »), qui les montre
/// directement, sans déplacement inutile. L'en-tête clair est
/// au-dessus de l'écran. Le tiroir court ne montre que l'église
/// courante, « Changer d'église » ouvre l'écran dédié « Mes églises »
/// (paginé et cherchable), et il ne garde que deux sections
/// (maquette, écran 20) : Outils (Notifications, Paiements
/// automatiques, File hors ligne, Qualité et bascule) et Compte
/// (Mon abonnement, Réglages, À propos de e-System Church).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = [
    'Accueil administrateur',
    'Membres et familles',
    'Finances',
    'Modules de l’église',
  ];

  // Tailles de titre par onglet (maquette, écrans 19, 1, 2, 21).
  static const _taillesTitre = [19.0, 23.0, 21.0, 19.0];

  /// Chaque écran reçoit une clé liée à l'église active : après une
  /// bascule d'église, HomeScreen reste monté et les écrans garderaient
  /// sinon leur Future d'avant (données de l'église précédente). La clé
  /// changeante recrée l'écran, donc son chargement, sans refaire la
  /// navigation. Vaut pour les 4 écrans à Future en initState
  /// (Accueil, Membres, Finances, Modules).
  Widget _screenFor(int index, String? egliseId) {
    final cle = ValueKey(egliseId);
    switch (index) {
      case 0:
        return DashboardScreen(
            key: cle, onAller: (i) => setState(() => _index = i));
      case 1:
        return MembresScreen(key: cle);
      case 2:
        return FinancesScreen(key: cle);
      case 3:
        return ModulesScreen(key: cle, sansAppBar: true);
      default:
        return DashboardScreen(
            key: cle, onAller: (i) => setState(() => _index = i));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 900;

    // Libellés courts, une ligne : « Accueil », « Membres »,
    // « Finances », « Modules ». Les titres complets restent
    // dans _titles. Chaque module est joignable par le tiroir, une
    // seule entrée par fonctionnalité, jamais par une grille.
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
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Modules'),
    ];

    // Tous les modules sont affichés pour toutes les églises (règle
    // du 11/11/2026) : plus de destination masquée.
    final courant = _index.clamp(0, _titles.length - 1);

    return Scaffold(
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
          Expanded(
            child: Column(
              children: [
                EnTeteClair(
                  titre: _titles[courant],
                  tailleTitre: _taillesTitre[courant],
                  // Maquette : sous-titre 12,5 px EXPL sur Membres
                  // (« Registre des membres et des familles. ») et
                  // sur Finances (« Contributions, caisse et clôtures
                  // de l'église. ») ; les autres onglets n'en ont pas.
                  sousTitre: courant == 1
                      ? 'Registre des membres et des familles.'
                      : courant == 2
                          ? 'Contributions, caisse et clôtures de l’église.'
                          : null,
                  leading: Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                      onPressed: () =>
                          Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ),
                // T13, D04 : abonnement expiré, bandeau persistant.
                if (state.lectureSeule) const BandeauLectureSeule(),
                Expanded(child: _screenFor(courant, state.church?.id)),
              ],
            ),
          ),
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
