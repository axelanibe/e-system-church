import 'package:flutter/material.dart';

/// Barre du bas : 5 libellés courts maximum, une ligne chacun, jamais
/// coupés. Au-delà de 5, l'entrée va dans le tiroir court ou dans le
/// corps de l'écran. Les libellés sont des mots simples, « Accueil »,
/// « Réseau », « Membres », « Finances », « Modules », pas du jargon.
class BarreDuBas extends StatelessWidget {
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const BarreDuBas({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(destinations.length <= 5,
            'Barre du bas : 5 libellés maximum, sinon l’écran devient illisible.');

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
    );
  }
}
