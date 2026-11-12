import 'package:flutter/material.dart';

/// Carte douce : blanche, coins 16 px, ombre douce, sans bordure dure.
/// C'est la carte de base de toute l'application, accueil, tableau de
/// bord et espace fidèle. Une seule action évidente par carte : si la
/// carte est touchable, tout son contenu mène à la même action.
class SoftCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color ?? Colors.white,
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Card(
      color: color ?? Colors.white,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
