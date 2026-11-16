import 'package:esystem_church/config/app_config.dart';
import 'package:esystem_church/config/app_theme.dart';
import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'church_avatar.dart';

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

/// En-tête d'un espace connecté (accueil administrateur, accueil
/// fidèle) : nom et logo de l'église connectée. Une fois l'église
/// ou ses membres connectés, le logo e-System Church ne s'affiche
/// plus en grand : c'est le nom de leur église avec leur logo
/// (règle d'Axel, 14 novembre 2026). Sans logo, les initiales
/// (ChurchAvatar) ; sans église connectée, repli sur la marque
/// e-System Church. La pastille ESC (EnTeteClair, en haut à droite)
/// reste visible.
///
/// Maquette, écran 36 (annexe, admin) : quand l'église est une
/// annexe, on affiche en plus le rôle (« Admin d'église »), le badge
/// « Annexe » et « Église mère : <nom> · <code> ». Le nom et le code
/// de la mère sont déjà dans l'état (les églises de l'utilisateur) :
/// la ligne n'apparaît que si la mère s'y trouve, rien n'est inventé.
class EnteteEspace extends StatelessWidget {
  final Church? eglise;

  const EnteteEspace({super.key, required this.eglise});

  @override
  Widget build(BuildContext context) {
    final eglise = this.eglise;
    if (eglise == null) return const EnteteMarque();
    final codeVille = [eglise.code, eglise.city]
        .where((v) => (v ?? '').isNotEmpty)
        .join(' · ');
    // Église mère, depuis les églises de l'état (annexe, admin
    // seulement : l'en-tête fidèle ne change pas).
    final state = context.watch<AppState>();
    Church? mere;
    if (!eglise.isMere && state.isAdmin) {
      final parentId = eglise.parentChurchId;
      for (final m in state.eglises) {
        if (m.church.id == parentId) {
          mere = m.church;
          break;
        }
      }
    }
    return Row(
      children: [
        ChurchAvatar(church: eglise, radius: 27),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eglise.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Maquette, écran 36 : nom d'église 15 px EXPL.
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (codeVille.isNotEmpty)
                Text(
                  codeVille,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Maquette, écran 36 : code 11,5 px EXPL.
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 11.5),
                ),
              if (mere != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Chip(
                      label: Text(
                        'Annexe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.violetProfond,
                          fontWeight: FontWeight.bold,
                          // Maquette, écran 36 : pastille 11,5 px.
                          fontSize: 11.5,
                        ),
                      ),
                      backgroundColor: AppTheme.orClair,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.roleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Maquette, écran 36 : rôle 11,5 px EXPL.
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Église mère : ${mere.name} · ${mere.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Maquette, écran 36 : ligne mère 12 px EXPL.
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
/// En-tête de marque : logo + nom + devise, comme sur les écrans
/// d'accueil de la projection couleurs du logo. Ne sert plus que
/// de repli quand aucune église n'est connectée (EnteteEspace),
/// et sur les pages publiques.
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
