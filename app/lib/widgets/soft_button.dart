import 'package:flutter/material.dart';

/// Bouton doux principal : plein largeur, 48 px de haut, bleu nuit.
/// Une seule action évidente par écran : le bouton principal est le
/// geste à faire, le reste est secondaire.
class BoutonDoux extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const BoutonDoux({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? FilledButton(
            onPressed: onPressed,
            child: Text(label),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Bouton doux secondaire : plein largeur, 48 px de haut, contour bleu nuit.
class BoutonDouxSecondaire extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const BoutonDouxSecondaire({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? OutlinedButton(
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Bouton avec sa courte explication dessous, comme pour l'inscription :
/// un nouveau membre comprend ce que fait le bouton avant de toucher.
/// Ex. « Voir ma carte de membre » + « Votre carte, avec votre photo
/// et votre matricule, à montrer à l'entrée. »
class BoutonAvecAide extends StatelessWidget {
  final String label;
  final String aide;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondaire;

  const BoutonAvecAide({
    super.key,
    required this.label,
    required this.aide,
    required this.onPressed,
    this.icon,
    this.secondaire = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        secondaire
            ? BoutonDouxSecondaire(
                label: label, onPressed: onPressed, icon: icon)
            : BoutonDoux(label: label, onPressed: onPressed, icon: icon),
        const SizedBox(height: 6),
        Text(
          aide,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
