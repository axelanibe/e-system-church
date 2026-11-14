import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'common_widgets.dart';

/// Visuel de la carte de membre, modèle CONNEXION PROPHÉTIQUE :
/// nom en blanc 20 px, matricule en or, établissement en blanc
/// atténué, QR bien visible dans un encadré blanc. Couleurs
/// e-System : dégradé violet, barre or. Photo, nom, matricule,
/// église, Membre depuis, QR. Rien d'autre. Réutilisé par la fiche
/// membre, par la page Carte seule et par l'impression des cartes.
class CarteMembreVisuelle extends StatelessWidget {
  final Member member;
  final String qrData;

  /// Pastille de statut sous « Membre depuis » (fiche complète
  /// seulement, jamais sur la page Carte ni à l'impression).
  final bool avecStatut;
  final Color couleurStatut;

  const CarteMembreVisuelle({
    super.key,
    required this.member,
    required this.qrData,
    this.avecStatut = false,
    this.couleurStatut = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    final nomEglise = context.read<AppState>().church?.name;
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
            Container(height: 6, color: AppTheme.or),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'CARTE DE MEMBRE',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'e-System Church',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          color: AppTheme.or,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 36,
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
                                fontSize: 32, color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    member.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Matricule : ${member.matricule}',
                    style: AppTheme.styleCode.copyWith(
                      color: AppTheme.or,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (nomEglise != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      nomEglise,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (member.createdAt != null)
                    Text(
                      'Membre depuis ${formatDate(member.createdAt)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  if (avecStatut) ...[
                    const SizedBox(height: 8),
                    StatusChip(
                      label: member.statutAffiche,
                      color: couleurStatut,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 180,
                    ),
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
