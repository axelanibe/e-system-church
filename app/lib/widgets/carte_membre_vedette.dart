import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../services/preferences_locales.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';

/// Carte de membre en vedette, en tête de l'espace fidèle : la plus
/// belle chose de l'écran, comme une carte bancaire dans une application
/// grand public. Dégradé violet, barre or en haut, matricule en or et
/// en mono, comme la carte du modèle. Photo ou initiales, nom en grand,
/// matricule, église, QR en miniature. Rien d'inventé : que des
/// données réelles du profil. La photo n'apparaît que si elle a été
/// fournie (migration 018), sinon les initiales. Le bouton ouvre la
/// vraie carte de membre, il ne la reconstruit pas.
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
    // QR de la carte : CODE_EGLISE:MATRICULE, matricule seul sinon
    // (même règle que la carte complète).
    final qrData = profil.matricule != null && church.code.isNotEmpty
        ? '${church.code}:${profil.matricule}'
        : (profil.matricule ?? '');
    final photoUrl = profil.user.photoUrl;
    // T12 (US16) : en mode économique, la photo réseau n'est pas chargée.
    // Lecture nullable : les tests pompent parfois la carte sans le
    // fournisseur de préférences, le mode économique vaut alors faux.
    final photoAffichee =
        (context.watch<PreferencesLocales?>()?.modeEconomique ?? false)
            ? null
            : photoUrl;
    // Carte du modèle : dégradé violet, barre or en haut.
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 6, color: AppTheme.or),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white24,
                        backgroundImage: photoAffichee != null
                            ? NetworkImage(photoAffichee)
                            : null,
                        child: photoAffichee == null
                            ? Text(
                                _initiales(profil.user.fullName),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profil.user.fullName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              church.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                            Text(
                              '${church.code}'
                              '${church.city != null ? ' · ${church.city}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if (qrData.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 64,
                          ),
                        )
                      else
                        ChurchAvatar(church: church, radius: 20),
                    ],
                  ),
                  if (profil.matricule != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.badge_outlined,
                            size: 20, color: AppTheme.or),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Matricule : ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.white70),
                                ),
                                TextSpan(
                                  text: profil.matricule,
                                  style: AppTheme.styleCode.copyWith(
                                    color: AppTheme.or,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (church.isMere) const MereBadge(),
                      ],
                    ),
                  ] else if (church.isMere) ...[
                    const SizedBox(height: 12),
                    const Row(children: [MereBadge()]),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onVoirCarte,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.or,
                        foregroundColor: AppTheme.bleuNuit,
                      ),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text(
                        'Voir ma carte de membre',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'À montrer à l’entrée de l’église.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
