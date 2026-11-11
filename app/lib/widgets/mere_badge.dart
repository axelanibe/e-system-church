import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Badge « Église mère » : or sur bleu nuit, lisible (contraste ~7:1),
/// palette officielle inchangée. Affiché sur l'accueil, le tableau de bord
/// et dans Mon église quand l'église active n'a pas de mère.
class MereBadge extends StatelessWidget {
  const MereBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Chip(
      avatar: Icon(Icons.church, size: 16, color: AppTheme.bleuNuit),
      label: Text(
        'Église mère',
        style: TextStyle(
          color: AppTheme.bleuNuit,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: AppTheme.or,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
