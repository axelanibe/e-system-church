import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ecole_biblique.dart';
import '../state/app_state.dart';
import 'common_widgets.dart';

/// « Ma progression » (maquette, écran 40) : agrégat réel des
/// progressions des cours du membre connecté (leçons terminées /
/// total, %). Sans inscription : 0 % / 0 leçon sur 0. Widget partagé
/// entre l'écran École biblique et la carte Progression de Ma Bible :
/// une seule copie, un seul chargement par écran. En aperçu admin, la
/// progression d'un membre n'est pas visible : état explicite, comme
/// Carte / Messages.
class ProgressionEcole extends StatelessWidget {
  final Future<List<ProgressionCours>> future;

  const ProgressionEcole({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().apercuFidele) {
      return const EmptyState(
        icon: Icons.school_outlined,
        message: 'En aperçu, la progression d’un membre n’est pas visible. '
            'Connectez-vous avec un compte fidèle pour suivre votre '
            'progression.',
      );
    }
    return FutureBuilder<List<ProgressionCours>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: 'Progression indisponible : ${snapshot.error}',
          );
        }
        final progressions = snapshot.data ?? const <ProgressionCours>[];
        final total =
            progressions.fold<int>(0, (somme, p) => somme + p.total);
        final terminees =
            progressions.fold<int>(0, (somme, p) => somme + p.terminees);
        final pourcentage =
            total == 0 ? 0 : (terminees * 100 / total).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Ma progression',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text('$pourcentage %',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 11),
            LinearProgressIndicator(
                value: total == 0 ? 0 : terminees / total),
            const SizedBox(height: 8),
            Text('$terminees leçon(s) terminée(s) sur $total.'),
          ],
        );
      },
    );
  }
}
