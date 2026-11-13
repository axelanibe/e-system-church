import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/en_tete_clair.dart';
import 'bible_fidele_screen.dart';
import 'carte_fidele_screen.dart';
import 'fidele_home_screen.dart';
import 'messages_fidele_screen.dart';
import 'plus_fidele_screen.dart';

/// Coquille fidèle (tranche P1) : la navigation du fidèle, séparée de
/// l'admin. Barre du bas Accueil, Bible, Carte, Messages, Plus.
/// Écrans larges (≥ 900 px) : rail latéral, comme la coquille admin.
/// La barre admin est absente ici. En aperçu admin
/// (« Voir l'espace fidèle »), les écrans montrent leurs états vides
/// pour les lectures réservées au rôle `membre`.
class FideleShell extends StatefulWidget {
  const FideleShell({super.key});

  @override
  State<FideleShell> createState() => _FideleShellState();
}

class _FideleShellState extends State<FideleShell> {
  int _index = 0;

  static const _titles = [
    'Accueil',
    'Bible',
    'Carte',
    'Messages',
    'Plus',
  ];

  void _allerAccueil() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final courant = _index.clamp(0, _titles.length - 1);

    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_outlined),
          label: 'Accueil'),
      NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book_outlined),
          label: 'Bible'),
      NavigationDestination(
          icon: Icon(Icons.badge_outlined),
          selectedIcon: Icon(Icons.badge_outlined),
          label: 'Carte'),
      NavigationDestination(
          icon: Icon(Icons.mail_outline),
          selectedIcon: Icon(Icons.mail_outline),
          label: 'Messages'),
      NavigationDestination(
          icon: Icon(Icons.list_outlined),
          selectedIcon: Icon(Icons.list_outlined),
          label: 'Plus'),
    ];

    Widget ecran;
    switch (courant) {
      case 1:
        ecran = const BibleFideleScreen();
        break;
      case 2:
        ecran = const CarteFideleScreen();
        break;
      case 3:
        ecran = const MessagesFideleScreen();
        break;
      case 4:
        ecran = PlusFideleScreen(onAllerAccueil: _allerAccueil);
        break;
      default:
        ecran = const FideleHomeScreen();
    }

    return Scaffold(
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
                  // En aperçu admin, un retour visible vers l'espace admin.
                  leading: context.watch<AppState>().apercuFidele
                      ? IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Voir l’espace admin',
                          onPressed: () => context
                              .read<AppState>()
                              .sortirApercuFidele(),
                        )
                      : null,
                ),
                Expanded(child: ecran),
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
