import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Badge « Église mère » : sable sur fond clair, texte cyprès
/// foncé (contraste 6,30:1). Jamais dans l'AppBar : il est dans le
/// corps de l'écran, carte de l'église ou tiroir, jamais en superposition
/// avec un titre. Affiché sur l'accueil, le tableau de bord et dans
/// Mon église quand l'église active n'a pas de mère.
class MereBadge extends StatelessWidget {
  const MereBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Chip(
      avatar: Icon(Icons.church, size: 16, color: AppTheme.cypress),
      label: Text(
        'Église mère',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.cypress,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: AppTheme.sable,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
