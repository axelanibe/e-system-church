import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/church.dart';
import '../state/app_state.dart';

/// Avatar de l'église active : logo (NetworkImage) quand l'église en a un,
/// sinon ses initiales sur fond de sa couleur principale.
///
/// Accessibilité (11 novembre 2026) : une église sans couleur, ou avec
/// une couleur claire comme l'or, avait des initiales blanches sur fond
/// clair, ratio ~1,5:1, invisibles. Le fond de repli est désormais le
/// cyprès, et la couleur du texte est celle, blanc ou cyprès,
/// dont le contraste avec le fond est le plus fort. Un seuil fixe sur la
/// luminosité ne suffit pas : l'or ambre #B8862D a une luminosité
/// moyenne, mais du blanc dessus ne contraste qu'à 3,24:1, et du
/// cyprès dessus qu'à 2,98:1.
class ChurchAvatar extends StatelessWidget {
  final Church? church;
  final double radius;

  const ChurchAvatar({super.key, required this.church, this.radius = 20});

  /// Contraste WCAG entre deux couleurs.
  static double _contraste(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final clair = l1 > l2 ? l1 : l2;
    final sombre = l1 > l2 ? l2 : l1;
    return (clair + 0.05) / (sombre + 0.05);
  }

  /// Couleur de texte la plus lisible sur [fond] : blanc ou cyprès.
  /// Ex. sur or ambre #B8862D, le blanc ne vaut que 3,24:1, le cyprès
  /// 2,98:1, c'est le meilleur des deux mais il reste sous 4,5:1.
  static Color texteSur(Color fond) =>
      _contraste(fond, Colors.white) >= _contraste(fond, AppTheme.cypress)
          ? Colors.white
          : AppTheme.cypress;

  @override
  Widget build(BuildContext context) {
    final c = church;
    if (c == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.cypress,
        child: const Icon(Icons.church_outlined, color: Colors.white),
      );
    }
    // Fond de repli cyprès quand l'église n'a pas de couleur.
    final fond = c.couleur ?? AppTheme.cypress;
    final logoUrl = c.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      final baseUrl = context.read<AppState>().apiBaseUrl;
      final fullUrl = logoUrl.startsWith('http') ? logoUrl : '$baseUrl$logoUrl';
      return CircleAvatar(
        radius: radius,
        backgroundColor: fond,
        backgroundImage: NetworkImage(fullUrl),
        onBackgroundImageError: (_, __) {},
        child: Text(
          c.initiales,
          style: TextStyle(
            color: texteSur(fond),
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.8,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: fond,
      child: Text(
        c.initiales,
        style: TextStyle(
          color: texteSur(fond),
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
