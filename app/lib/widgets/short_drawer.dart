import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module_eglise.dart';
import '../state/app_state.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import '../screens/choisir_eglise_screen.dart';
import '../screens/finances_mere_screen.dart';
import '../screens/modules_activation_screen.dart';
import '../screens/mon_eglise_screen.dart';
import '../screens/plateforme_screen.dart';
import '../screens/rattachements_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transferts_screen.dart';

/// Tiroir court : l'église courante seule, jamais la liste complète.
/// Pour changer d'église, une seule entrée, « Changer d'église », qui
/// ouvre un écran dédié. Les entrées en jargon portent une courte
/// explication en dessous, pour qu'un nouveau responsable comprenne
/// où il va avant de toucher.
class TiroirCourt extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Réseau,
  /// 2 Membres, 3 Finances, 4 Annonces, 5 Modules).
  final void Function(int index) onAller;

  const TiroirCourt({super.key, required this.onAller});

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ChurchAvatar(church: church, radius: 24),
                const SizedBox(height: 8),
                Text(
                  church?.name ?? 'e-System Church',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (church?.isMere ?? false) ...[
                  const SizedBox(height: 6),
                  const MereBadge(),
                ],
                const SizedBox(height: 4),
                Text(
                  '${church?.code ?? ''} · ${church?.city ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  state.user?.fullName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  state.roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz_outlined),
            title: const Text('Changer d’église'),
            subtitle: const Text('Voir une autre de vos églises'),
            onTap: () => _ouvrir(context, const ChoisirEgliseScreen()),
          ),
          const Divider(),
          if (state.isModuleActif(CodesModules.annonces))
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Annonces'),
              subtitle: const Text('Messages pour votre église'),
              onTap: () {
                Navigator.of(context).pop();
                onAller(4);
              },
            ),
          if (state.isModuleActif(CodesModules.monEglise))
            ListTile(
              leading: const Icon(Icons.church_outlined),
              title: const Text('Mon église'),
              subtitle: const Text('Présentation et horaires des cultes'),
              onTap: () => _ouvrir(context, const MonEgliseScreen()),
            ),
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.toggle_on_outlined),
              title: const Text('Modules de l’église'),
              subtitle:
                  const Text('Choisir les fonctions visibles dans l’app'),
              onTap: () =>
                  _ouvrir(context, const ModulesActivationScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Demandes pour rejoindre une église'),
            subtitle: const Text('Personnes qui veulent vous rejoindre'),
            onTap: () => _ouvrir(context, const RattachementsScreen()),
          ),
          if (state.isSuperAdmin)
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Plateforme'),
              subtitle: const Text('Chiffres de toutes les églises'),
              onTap: () => _ouvrir(context, const PlateformeScreen()),
            ),
          if (state.canManageMembers)
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Transferts de membres'),
              subtitle: const Text('Déplacer un membre vers une église'),
              onTap: () => _ouvrir(context, const TransfertsScreen()),
            ),
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Finances de la mère'),
              subtitle: const Text('Argent de tout votre réseau'),
              onTap: () => _ouvrir(context, const FinancesMereScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Réglages'),
            onTap: () => _ouvrir(context, const SettingsScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              Navigator.of(context).pop();
              await context.read<AppState>().logout();
            },
          ),
        ],
      ),
    );
  }
}
