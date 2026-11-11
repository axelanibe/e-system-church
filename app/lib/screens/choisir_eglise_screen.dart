import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/screen_header.dart';
import '../widgets/soft_card.dart';

/// Écran dédié « Changer d'église » : la liste complète des églises
/// de l'utilisateur vit ici, jamais dans le tiroir. Un toucher choisit
/// l'église, tout ce qui suit montre cette église-là.
class ChoisirEgliseScreen extends StatelessWidget {
  const ChoisirEgliseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final actuelle = state.church;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Changer d’église',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EnteteEcran(
                  titre: 'Quelle église voulez-vous voir ?',
                  sousTitre: 'Touchez une église. Tout ce que vous verrez '
                      'ensuite sera celui de cette église.',
                ),
                if (state.eglises.isEmpty)
                  const EmptyState(
                    icon: Icons.church_outlined,
                    message: 'Vous n’êtes rattaché à aucune église '
                        'pour l’instant. Demandez à votre pasteur '
                        'de vous ajouter.',
                  )
                else
                  for (final membership in state.eglises)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SoftCard(
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (membership.church.id != actuelle?.id) {
                            await context.read<AppState>().switchChurch(
                                  membership.church.id,
                                );
                          }
                        },
                        child: Row(
                          children: [
                            ChurchAvatar(
                                church: membership.church, radius: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    membership.church.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    '${membership.church.code} · ${membership.role}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (membership.church.id == actuelle?.id)
                              const Icon(Icons.check,
                                  color: Color(0xFF3F5A50)),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
