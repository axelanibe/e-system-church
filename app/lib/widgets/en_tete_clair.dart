import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'logo_app.dart';

/// En-tête clair, en haut de chaque coquille : titre de l'écran,
/// sous-titre quand l'écran en a un, et l'icône ESC.
/// [leading] est le bouton de gauche : menu du tiroir dans les
/// coquilles, retour sur les écrans poussés.
class EnTeteClair extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final Widget? leading;

  const EnTeteClair({
    super.key,
    required this.titre,
    this.sousTitre,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.fondPapier,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.bordure),
        ),
      ),
      child: Row(
        children: [
          leading ?? const SizedBox(width: 48, height: 48),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (sousTitre != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sousTitre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color:
                              AppTheme.violetProfond.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Icône ESC (48x48 arrondie) à la place du texte « eS »
          // (correction d'Axel, 14 novembre 2026).
          const LogoApp(taille: 48),
        ],
      ),
    );
  }
}
