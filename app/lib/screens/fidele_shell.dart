import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/en_tete_clair.dart';
import '../widgets/tiroir_fidele.dart';
import 'assistant_fidele_screen.dart';
import 'bible_fidele_screen.dart';
import 'carte_fidele_screen.dart';
import 'fidele_home_screen.dart';
import 'messages_fidele_screen.dart';

/// Coquille fidèle (tranche P1) : la navigation du fidèle, séparée de
/// l'admin. Barre du bas Accueil, Bible, Carte, Clavardage. Le menu
/// Plus est remplacé par le tiroir hamburger, ouvert depuis la barre
/// de l'accueil ; le fil privé vers l'église (Messages) est renommé
/// Clavardage, sans changer son écran ni son comportement.
/// Écrans larges (≥ 900 px) : rail latéral, comme la coquille admin.
/// La barre admin est absente ici.
class FideleShell extends StatefulWidget {
  const FideleShell({super.key, this.ongletInitial = 0});

  /// Onglet affiché à l'ouverture (0 Accueil, 1 Bible, 2 Carte,
  /// 3 Clavardage). Sert l'ouverture depuis une notification push.
  final int ongletInitial;

  @override
  State<FideleShell> createState() => _FideleShellState();
}

class _FideleShellState extends State<FideleShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.ongletInitial;
  }

  static const _titles = [
    'Accueil',
    'Bible',
    'Carte',
    'Clavardage',
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
          label: 'Clavardage'),
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
      default:
        ecran = const FideleHomeScreen();
    }

    // Refonte espace membre : le thème membre (palette violet royal
    // et or) descend dans toute la coquille et dans les écrans
    // poussés depuis elle (cotisations, journal, détail du culte).
    // L'espace admin garde le thème de l'application.
    return Theme(
      data: AppTheme.themeMembre(Theme.of(context)),
      child: Scaffold(
        drawer: TiroirFidele(onAllerAccueil: _allerAccueil),
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
                // Page Carte : visuel seul, sans titre (projection).
                // Accueil : le bouton hamburger ouvre le tiroir.
                if (courant != 2)
                  EnTeteClair(
                    titre: _titles[courant],
                    leading: courant == 0
                        ? Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(Icons.menu),
                              tooltip: 'Menu',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                            ),
                          )
                        : null,
                  ),
                // T13, D04 : abonnement expiré, bandeau persistant.
                if (context.watch<AppState>().lectureSeule)
                  const BandeauLectureSeule(),
                Expanded(child: ecran),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: courant == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AssistantFideleScreen(),
                ),
              ),
              tooltip: 'Assistant e-System',
              backgroundColor: PaletteMembre.or,
              foregroundColor: PaletteMembre.violetRoyal,
              child: const Icon(Icons.smart_toy_outlined),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : BarreDuBas(
              destinations: destinations,
              selectedIndex: courant,
              onDestinationSelected: (i) => setState(() => _index = i),
            ),
      ),
    );
  }
}
