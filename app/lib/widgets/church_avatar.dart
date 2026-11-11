import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/church.dart';
import '../state/app_state.dart';

/// Avatar de l'église active : logo (NetworkImage) quand l'église en a un,
/// sinon ses initiales sur fond de sa couleur principale.
/// Correctif accessibilité (audit 11 nov. 2026, cas A1/A2) : sans couleur,
/// le fond est bleu nuit (jamais le gris clair par défaut de CircleAvatar,
/// qui rendait les initiales blanches invisibles), et la couleur du texte
/// suit la luminosité du fond (blanc sur fond sombre, bleu nuit sur fond
/// clair, ex. or #D4A72C).
class ChurchAvatar extends StatelessWidget {
  final Church? church;
  final double radius;

  const ChurchAvatar({super.key, required this.church, this.radius = 20});

  /// Couleur du texte des initiales sur [fond] : celle des deux (blanc ou
  /// bleu nuit) qui contraste le mieux avec le fond, au sens WCAG. Un seuil
  /// fixe ne suffit pas : l'or #D4A72C a une luminosité de 0,42, sous 0,5,
  /// mais du blanc dessus ne contraste qu'à 2,24:1 (invisible, cas A2).
  static Color texteSur(Color fond) {
    final l = fond.computeLuminance();
    final contrasteBlanc = 1.05 / (l + 0.05);
    final contrasteNuit =
        (l + 0.05) / (AppTheme.bleuNuit.computeLuminance() + 0.05);
    return contrasteBlanc >= contrasteNuit ? Colors.white : AppTheme.bleuNuit;
  }

  @override
  Widget build(BuildContext context) {
    final c = church;
    if (c == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.bleuNuit,
        child: const Icon(Icons.church_outlined, color: Colors.white),
      );
    }
    final fond = c.couleur ?? AppTheme.bleuNuit;
    final style = TextStyle(
      color: texteSur(fond),
      fontWeight: FontWeight.bold,
      fontSize: radius * 0.8,
    );
    final logoUrl = c.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      final baseUrl = context.read<AppState>().apiBaseUrl;
      final fullUrl = logoUrl.startsWith('http') ? logoUrl : '$baseUrl$logoUrl';
      return CircleAvatar(
        radius: radius,
        backgroundColor: fond,
        backgroundImage: NetworkImage(fullUrl),
        onBackgroundImageError: (_, __) {},
        child: Text(c.initiales, style: style),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: fond,
      child: Text(c.initiales, style: style),
    );
  }
}
