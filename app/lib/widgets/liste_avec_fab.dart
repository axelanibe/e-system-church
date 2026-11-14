import 'package:flutter/material.dart';

/// Marge basse réservée au bouton d'action flottant (T13, défaut D01).
///
/// Sans elle, le FAB recouvre la dernière ligne de la liste. Toute liste
/// d'un écran à FAB doit être enveloppée dans ce widget : il n'ajoute
/// que 88 px en bas, la même marge que l'écran Finances, déjà corrigé.
/// Le padding est hors de la zone défilante : la dernière ligne reste
/// entièrement visible au-dessus du FAB, quel que soit le point d'arrêt
/// du défilement.
class ListeAvecFab extends StatelessWidget {
  const ListeAvecFab({super.key, required this.child});

  /// La liste (ListView, RefreshIndicator, FutureBuilder…).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 88),
      child: child,
    );
  }
}
