import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Barre du bas : 5 libellés courts maximum, une ligne chacun, jamais
/// coupés. Au-delà de 5, l'entrée va dans le tiroir court ou dans le
/// corps de l'écran. Les libellés sont des mots simples, « Accueil »,
/// « Réseau », « Membres », « Finances », « Modules », pas du jargon.
/// [badges] porte le nombre de non lus par destination (même ordre
/// que [destinations], nul ou 0 = pas de pastille) : pastille or,
/// nombre violet profond, comme la carte d'accueil et la tuile
/// fidèle de la messagerie.
class BarreDuBas extends StatelessWidget {
  final List<NavigationDestination> destinations;
  final List<int?>? badges;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const BarreDuBas({
    super.key,
    required this.destinations,
    this.badges,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(destinations.length <= 5,
            'Barre du bas : 5 libellés maximum, sinon l’écran devient illisible.'),
       assert(
         badges == null || badges.length == destinations.length,
         'Barre du bas : un badge par destination, dans le même ordre.',
       );

  NavigationDestination _avecBadge(
    NavigationDestination destination,
    int? badge,
  ) {
    if (badge == null || badge <= 0) return destination;
    Widget pastille(Widget icone) => Badge(
          backgroundColor: AppTheme.or,
          textColor: AppTheme.violetProfond,
          label: Text(
            '$badge',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: icone,
        );
    return NavigationDestination(
      icon: pastille(destination.icon),
      selectedIcon: destination.selectedIcon == null
          ? null
          : pastille(destination.selectedIcon!),
      label: destination.label,
      tooltip: destination.tooltip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final badges = this.badges;
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (var i = 0; i < destinations.length; i++)
          _avecBadge(
            destinations[i],
            badges == null ? null : badges[i],
          ),
      ],
    );
  }
}
