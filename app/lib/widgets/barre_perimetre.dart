import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../screens/annexes_screen.dart';
import '../screens/plateforme_screen.dart';
import '../screens/tree_screen.dart';
import '../state/app_state.dart';

/// Espace courant de la barre de périmètre de l'artefact.
enum EspaceArtefact { plateforme, egliseMere, annexe, espaceMembre }

/// Barre de périmètre de l'artefact : bande bleu nuit en haut de
/// l'écran, avec l'indicateur « En ligne » et les 4 espaces
/// (1. Plateforme, 2. Église Mère, 3. Annexe, 4. Espace Membre),
/// l'espace courant en or. Un espace est touchable là où
/// l'application le permet déjà, sinon il est grisé, sans
/// navigation inventée.
class BarrePerimetre extends StatelessWidget {
  final EspaceArtefact courant;
  final VoidCallback? allerPlateforme;
  final VoidCallback? allerEgliseMere;
  final VoidCallback? allerAnnexe;
  final VoidCallback? allerEspaceMembre;

  const BarrePerimetre({
    super.key,
    required this.courant,
    this.allerPlateforme,
    this.allerEgliseMere,
    this.allerAnnexe,
    this.allerEspaceMembre,
  });

  /// Barre câblée depuis le contexte : les destinations viennent du
  /// rôle et de l'église connectés. [courant] reste explicite, la
  /// barre ne devine pas où elle est.
  static BarrePerimetre depuisContexte(
    BuildContext context, {
    required EspaceArtefact courant,
  }) {
    final state = context.read<AppState>();
    final estMere = state.church?.isMere ?? true;
    return BarrePerimetre(
      courant: courant,
      allerPlateforme: state.isSuperAdmin
          ? () => _ouvrir(context, const PlateformeScreen())
          : null,
      allerEgliseMere:
          !estMere ? () => _ouvrir(context, const TreeScreen()) : null,
      allerAnnexe: estMere && state.isAdmin
          ? () => _ouvrir(context, const AnnexesScreen())
          : null,
      allerEspaceMembre: courant == EspaceArtefact.espaceMembre
          ? null
          : () => state.entrerApercuFidele(),
    );
  }

  static void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  Widget _puce(
    BuildContext context,
    String label,
    EspaceArtefact espace,
    VoidCallback? onTap,
  ) {
    final estCourant = espace == courant;
    final accessible = estCourant || onTap != null;
    final contenu = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: estCourant
            ? AppTheme.or
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: estCourant
              ? AppTheme.bleuNuit
              : (accessible ? Colors.white : Colors.white54),
        ),
      ),
    );
    if (onTap == null) return contenu;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: contenu,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bleuNuit,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PointEnLigne(),
                SizedBox(width: 6),
                Text(
                  'En ligne',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _puce(context, '1. Plateforme', EspaceArtefact.plateforme,
                  allerPlateforme),
              _puce(context, '2. Église Mère', EspaceArtefact.egliseMere,
                  allerEgliseMere),
              _puce(context, '3. Annexe', EspaceArtefact.annexe,
                  allerAnnexe),
              _puce(context, '4. Espace Membre',
                  EspaceArtefact.espaceMembre, allerEspaceMembre),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointEnLigne extends StatelessWidget {
  const _PointEnLigne();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppTheme.or,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Logo « eS » : pastille bleu nuit cerclée d'or, comme l'artefact.
class LogoES extends StatelessWidget {
  const LogoES({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.bleuNuit,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.or, width: 2),
      ),
      alignment: Alignment.center,
      child: const Text(
        'eS',
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppTheme.or,
        ),
      ),
    );
  }
}

/// En-tête clair de l'artefact, sous la barre de périmètre : titre
/// de l'écran, sous-titre quand l'écran en a un, et le logo « eS ».
/// [leading] est le bouton de gauche : menu du tiroir dans les
/// coquilles, retour sur les écrans poussés.
class EnTeteClair extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final Widget? leading;

  const EnTeteClair({
    super.key,
    required this.titre,
    this.sousTitre,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.fondPapier,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      decoration: const BoxDecoration(
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
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (sousTitre != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sousTitre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color:
                              AppTheme.bleuNuit.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const LogoES(),
        ],
      ),
    );
  }
}
