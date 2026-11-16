import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'logo_app.dart';

/// En-tête clair, en haut de chaque coquille : titre de l'écran
/// et l'icône ESC.
/// [leading] est le bouton de gauche : menu du tiroir dans les
/// coquilles, retour sur les écrans poussés.
/// [sousTitre] s'affiche sous le titre quand il est renseigné
/// (maquette, écran 1 : onglet Membres seulement) ; sans lui, le
/// rendu est inchangé.
/// [tailleTitre] : 19 px par défaut (Accueil, Modules) ; 23 px pour
/// l'onglet Membres, 21 px pour Finances (maquette, tailles EXPL).
class EnTeteClair extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final double tailleTitre;
  final Widget? leading;

  const EnTeteClair({
    super.key,
    required this.titre,
    this.sousTitre,
    this.tailleTitre = 19,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final sousTitre = this.sousTitre;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.fondPapier,
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
                  // Maquette : titre 19 px (Accueil, Modules), 23 px
                  // (Membres), 21 px (Finances) ; headlineSmall vaut 24 px.
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontSize: tailleTitre),
                ),
                if (sousTitre != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sousTitre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Maquette : sous-titre 12,5 px EXPL.
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 12.5),
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
