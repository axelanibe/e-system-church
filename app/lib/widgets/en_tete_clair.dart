import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Logo « eS » : pastille bleu nuit cerclée d'or, comme l'artefact.
class LogoES extends StatelessWidget {
  const LogoES({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.bleuNuit,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.or, width: 2),
      ),
      alignment: Alignment.center,
      child: const Text(
        'eS',
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppTheme.or,
        ),
      ),
    );
  }
}

/// En-tête clair, en haut de chaque coquille : titre de l'écran,
/// sous-titre quand l'écran en a un, et le logo « eS ».
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
                              AppTheme.bleuNuit.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const LogoES(),
        ],
      ),
    );
  }
}
