import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../services/preferences_locales.dart';

/// Carte d'identité compacte en tête de l'accueil fidèle (refonte
/// validée le 24 novembre 2026, modèle MemberHeroCard de la maquette) :
/// une seule carte en dégradé violet royal, initiales ou photo dans
/// un cercle bordure or, badge « Église mère », nom en gras, matricule
/// lisible, bouton QR blanc à droite, et en bas le nom de l'église
/// avec son code et le lien doré « Ma carte ». Rien d'inventé : que
/// des données réelles du profil. La photo n'apparaît que si elle a
/// été fournie (migration 018), sinon les initiales. Le bouton QR et
/// le lien ouvrent la vraie carte de membre, ils ne la reconstruisent
/// pas : le QR réel reste sur l'onglet Carte.
class CarteMembreVedette extends StatelessWidget {
  final FideleProfil profil;
  final VoidCallback onVoirCarte;

  const CarteMembreVedette({
    super.key,
    required this.profil,
    required this.onVoirCarte,
  });

  String _initiales(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+'));
    final lettres = mots.where((m) => m.isNotEmpty).take(2).map((m) => m[0]);
    return lettres.join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final church = profil.church;
    final photoUrl = profil.user.photoUrl;
    // T12 (US16) : en mode économique, la photo réseau n'est pas chargée.
    // Lecture nullable : les tests pompent parfois la carte sans le
    // fournisseur de préférences, le mode économique vaut alors faux.
    final photoAffichee =
        (context.watch<PreferencesLocales?>()?.modeEconomique ?? false)
            ? null
            : photoUrl;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PaletteMembre.violetRoyal,
            PaletteMembre.degradeSecondaire,
            PaletteMembre.accent,
          ],
          stops: [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: PaletteMembre.violetRoyal.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PaletteMembre.or.withValues(alpha: 0.35),
                    PaletteMembre.or.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.68],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: PaletteMembre.or,
                          width: 2,
                        ),
                        color: Colors.white.withValues(alpha: 0.12),
                        image: photoAffichee != null
                            ? DecorationImage(
                                image: NetworkImage(photoAffichee),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: photoAffichee == null
                          ? Text(
                              _initiales(profil.user.fullName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppFontSizes.s18,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (church.isMere)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: PaletteMembre.or
                                    .withValues(alpha: 0.16),
                                border: Border.all(
                                  color: PaletteMembre.or
                                      .withValues(alpha: 0.55),
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.church_outlined,
                                    size: 12,
                                    color: PaletteMembre.orSurViolet,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Église mère',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color:
                                              PaletteMembre.orSurViolet,
                                          fontWeight: FontWeight.bold,
                                          fontSize: AppFontSizes.s11,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          if (church.isMere)
                            const SizedBox(height: 6),
                          Text(
                            profil.user.fullName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppFontSizes.s20,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (profil.matricule != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              'ID · ${profil.matricule}',
                              style: AppTheme.styleCode.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSizes.s13_5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _BoutonQr(onTap: onVoirCarte),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.only(top: 13),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              church.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppFontSizes.s13,
                                  ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Code église · ${church.code}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white
                                        .withValues(alpha: 0.72),
                                    fontSize: AppFontSizes.s11_5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: onVoirCarte,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xs,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ma carte',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: PaletteMembre.or,
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppFontSizes.s13_5,
                                  ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right,
                              size: 15,
                              color: PaletteMembre.or,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton QR blanc à droite du héros : ouvre la vraie carte.
class _BoutonQr extends StatelessWidget {
  final VoidCallback onTap;

  const _BoutonQr({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 52,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_2_outlined,
                size: 22,
                color: PaletteMembre.violetRoyal,
              ),
              Text(
                'QR',
                style: TextStyle(
                  fontSize: AppFontSizes.s10,
                  fontWeight: FontWeight.bold,
                  color: PaletteMembre.violetRoyal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
