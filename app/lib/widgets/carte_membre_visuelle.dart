import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'common_widgets.dart';

/// Visuel de la carte de membre, mise en page horizontale de la
/// maquette (écran 38) : photo, nom et matricule en haut à gauche,
/// pastille ESC à droite, lignes Église, Annexe et Membre depuis,
/// puis QR à gauche et code de vérification à droite. Couleurs
/// e-System : dégradé violet, barre or. Rien d'autre. Réutilisé par
/// la fiche membre, par la page Carte seule et par l'impression
/// des cartes.
class CarteMembreVisuelle extends StatelessWidget {
  final Member member;
  final String qrData;

  /// Pastille de statut sous « Membre depuis » (fiche complète
  /// seulement, jamais sur la page Carte ni à l'impression).
  final bool avecStatut;
  final Color couleurStatut;

  /// Format pass vertical centré (maquette de refonte, onglet Carte
  /// du fidèle) : tête en dégradé, lignes, QR haute définition sur
  /// fond blanc, code de vérification. Faux par défaut : la fiche
  /// membre et l'impression gardent la mise en page horizontale.
  final bool vertical;

  const CarteMembreVisuelle({
    super.key,
    required this.member,
    required this.qrData,
    this.avecStatut = false,
    this.couleurStatut = Colors.grey,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final eglise = context.read<AppState>().church;
    final nomEglise = eglise?.name;
    // Le membre appartient à une annexe quand son église a une mère :
    // la ligne « Annexe » s'affiche alors, sans migration.
    final estAnnexe = eglise?.parentChurchId != null;
    if (vertical) {
      return _passVertical(context, nomEglise, estAnnexe, eglise?.code);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A0059), Color(0xFF3D0073)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête horizontal (maquette, écran 38) : photo,
                  // nom et matricule à gauche, pastille ESC à droite.
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white24,
                        backgroundImage: member.photoUrl != null
                            ? NetworkImage(member.photoUrl!)
                            : null,
                        child: member.photoUrl == null
                            ? Text(
                                member.fullName.isNotEmpty
                                    ? member.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 23, color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.fullName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Matricule : ${member.matricule}',
                              style: AppTheme.styleCode.copyWith(
                                color: AppTheme.or,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.violetProfond,
                          borderRadius: BorderRadius.circular(11),
                          border:
                              Border.all(color: AppTheme.or, width: 2),
                        ),
                        child: const Text(
                          'ESC',
                          style: TextStyle(
                            color: AppTheme.or,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  if (nomEglise != null)
                    Text(
                      'Église : $nomEglise',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70, fontSize: 12.5),
                    ),
                  if (estAnnexe)
                    Text(
                      'Annexe : $nomEglise · ${eglise!.code}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70, fontSize: 12.5),
                    ),
                  if (member.createdAt != null)
                    Text(
                      'Membre depuis : ${formatDate(member.createdAt)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70, fontSize: 12.5),
                    ),
                  if (avecStatut) ...[
                    const SizedBox(height: 8),
                    StatusChip(
                      label: member.statutAffiche,
                      color: couleurStatut,
                    ),
                  ],
                  const SizedBox(height: 14),
                  // QR à gauche, code de vérification à droite
                  // (maquette, écran 38).
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 104,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Code de vérification : ',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors.white70,
                                        fontSize: 11.5),
                              ),
                              TextSpan(
                                text: qrData,
                                style: AppTheme.styleCode.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(height: 6, color: AppTheme.or),
          ],
        ),
      ),
    );
  }

  /// Format pass vertical centré (maquette de refonte) : tête en
  /// dégradé avec avatar, nom et matricule, lignes d'église, QR
  /// haute définition sur fond blanc, code de vérification. Même
  /// QR réel que la carte horizontale (code:matricule).
  Widget _passVertical(
    BuildContext context,
    String? nomEglise,
    bool estAnnexe,
    String? codeEglise,
  ) {
    final church = context.read<AppState>().church;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PaletteMembre.bordure),
        boxShadow: [
          BoxShadow(
            color: PaletteMembre.violetRoyal.withValues(alpha: 0.16),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PaletteMembre.violetRoyal,
                  PaletteMembre.degradeSecondaire,
                  PaletteMembre.accent,
                ],
                stops: [0, 0.55, 1],
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: PaletteMembre.or,
                      width: 2,
                    ),
                    color: Colors.white.withValues(alpha: 0.12),
                    image: member.photoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(member.photoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: member.photoUrl == null
                      ? Text(
                          member.fullName.isNotEmpty
                              ? member.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 19,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 9),
                Text(
                  member.fullName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${member.matricule}'
                  '${church?.isMere == true ? ' · Église mère' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              children: [
                if (nomEglise != null)
                  _lignePass(context, 'Église', nomEglise),
                if (codeEglise != null && codeEglise.isNotEmpty)
                  _lignePass(context, 'Code église', codeEglise),
                if (estAnnexe && nomEglise != null)
                  _lignePass(context, 'Annexe', '$nomEglise · $codeEglise'),
                if (member.createdAt != null)
                  _lignePass(
                    context,
                    'Membre depuis',
                    formatDate(member.createdAt),
                  ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: PaletteMembre.bordure),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 196,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Code de vérification\n$qrData',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PaletteMembre.texteSecondaire,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lignePass(BuildContext context, String label, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PaletteMembre.texteSecondaire,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PaletteMembre.texte,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
