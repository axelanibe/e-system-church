import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import 'soft_button.dart';
import 'soft_card.dart';

/// Carte de membre en vedette, en tête de l'espace fidèle : la plus
/// belle chose de l'écran, comme une carte bancaire dans une application
/// grand public. Photo ou initiales, nom en grand, matricule, église, QR
/// en miniature. Rien d'inventé : que des données réelles du profil.
/// La photo n'apparaît que si elle a été fournie (migration 018),
/// sinon les initiales. Le bouton ouvre la vraie carte de membre,
/// il ne la reconstruit pas.
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
    return SoftCard(
      color: AppTheme.orClair,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.bleuNuit,
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
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
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      church.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${church.code}'
                      '${church.city != null ? ' · ${church.city}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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
                    size: 20, color: AppTheme.bleuNuit),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matricule : ${profil.matricule}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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
          BoutonAvecAide(
            label: 'Voir ma carte de membre',
            aide: 'Votre carte, avec votre photo et votre matricule, '
                'à montrer à l’entrée de l’église.',
            icon: Icons.badge_outlined,
            onPressed: onVoirCarte,
          ),
        ],
      ),
    );
  }
}
