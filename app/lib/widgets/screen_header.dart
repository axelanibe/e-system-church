import 'package:flutter/material.dart';

/// En-tête d'écran : titre 24 gras, une ligne ou retour à la ligne,
/// jamais coupé par un autre élément. Un nouveau membre qui
/// ouvre l'écran sait tout de suite où il est.
class EnteteEcran extends StatelessWidget {
  final String titre;

  const EnteteEcran({super.key, required this.titre});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}
