import 'package:esystem_church/config/app_config.dart';
import 'package:flutter/material.dart';

/// Icône ESC simplifiée d'e-System Church (carré arrondi violet,
/// ruban or, lettres ESC blanches). C'est elle qui va dans
/// l'application, pas le logo complet (croix, globe, livre, texte),
/// qui reste hors de l'application (correction d'Axel, 14 novembre
/// 2026). L'image a déjà des coins transparents : on l'affiche dans
/// un cadre arrondi à 22 % (projection couleurs du logo, validée
/// par Axel le 14 novembre 2026 pour le web et l'APK).
class LogoApp extends StatelessWidget {
  final double taille;

  const LogoApp({super.key, this.taille = 54});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(taille * 0.22),
      child: Image.asset(
        'assets/icone-esc.png',
        width: taille,
        height: taille,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// En-tête de marque : logo + nom + devise, comme sur les écrans
/// d'accueil de la projection couleurs du logo.
class EnteteMarque extends StatelessWidget {
  const EnteteMarque({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const LogoApp(taille: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                AppConfig.appSlogan,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
