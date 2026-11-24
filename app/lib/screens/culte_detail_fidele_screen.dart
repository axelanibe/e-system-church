import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/cultes.dart';
import '../utils/format.dart';
import '../widgets/compte_rebours.dart';

/// Détail du culte (refonte validée le 24 novembre 2026) : date,
/// heure, lieu, orateur, compte à rebours calculé en direct depuis
/// la date réelle du culte, et retour. Aucune donnée inventée : le
/// culte vient de l'accueil fidèle.
class CulteDetailFideleScreen extends StatelessWidget {
  final Culte culte;

  const CulteDetailFideleScreen({super.key, required this.culte});

  @override
  Widget build(BuildContext context) {
    final date = culte.date;
    return Scaffold(
      appBar: AppBar(title: const Text('Détail du culte')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: PaletteMembre.surfaceDouce,
                              borderRadius: BorderRadius.circular(
                                AppRadii.md,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  date == null
                                      ? '--'
                                      : '${date.day}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppFontSizes.s20,
                                        color: PaletteMembre.violetRoyal,
                                      ),
                                ),
                                Text(
                                  date == null
                                      ? ''
                                      : _moisCourt(date.month),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppFontSizes.s11,
                                        color: PaletteMembre.violetRoyal,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  culte.titre,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppFontSizes.s16,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                if (culte.theme != null)
                                  Text(
                                    culte.theme!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: PaletteMembre.texteSecondaire,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ligne(
                        context,
                        'Date',
                        date == null ? 'À confirmer' : afficherDate(date),
                      ),
                      _ligne(
                        context,
                        'Heure',
                        date == null
                            ? 'À confirmer'
                            : formatDateTimeSansDecalage(date),
                      ),
                      _ligne(
                        context,
                        'Lieu',
                        culte.lieu ?? 'Lieu à confirmer',
                      ),
                      if (culte.orateur != null)
                        _ligne(context, 'Avec', culte.orateur!),
                      const SizedBox(height: AppSpacing.md),
                      CompteRebours(date: date),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Retour au prochain culte'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ligne(BuildContext context, String label, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PaletteMembre.texteSecondaire,
                  fontWeight: FontWeight.w600,
                  fontSize: AppFontSizes.s13_5,
                ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PaletteMembre.texte,
                    fontWeight: FontWeight.bold,
                    fontSize: AppFontSizes.s13_5,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _moisCourt(int mois) {
    const moisCourts = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    return moisCourts[mois - 1];
  }
}
