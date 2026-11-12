import 'package:flutter/material.dart';

/// En-tête d'écran : titre 24 gras, une ligne ou retour à la ligne,
/// jamais coupé par un autre élément, et sous-titre 16 en bleu nuit qui
/// dit en une phrase ce que l'écran sert à faire. Un nouveau membre qui
/// ouvre l'écran sait tout de suite où il est et quoi y faire.
class EnteteEcran extends StatelessWidget {
  final String titre;
  final String? sousTitre;

  const EnteteEcran({super.key, required this.titre, this.sousTitre});

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
          if (sousTitre != null) ...[
            const SizedBox(height: 4),
            Text(
              sousTitre!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
