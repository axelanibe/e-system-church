import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import '../screens/a_propos_screen.dart';
import '../screens/abonnement_screen.dart';
import '../screens/annonces_screen.dart';
import '../screens/annexes_screen.dart';
import '../screens/mes_eglises_screen.dart';
import '../screens/finances_mere_screen.dart';
import '../screens/modules_screen.dart';
import '../screens/mon_eglise_screen.dart';
import '../screens/plateforme_screen.dart';
import '../screens/rapports_mere_screen.dart';
import '../screens/rattachements_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transferts_screen.dart';
import '../screens/tree_screen.dart';

/// Tiroir court : l'église courante seule, jamais la liste complète.
/// Pour changer d'église, une seule entrée, « Changer d'église », qui
/// ouvre un écran dédié. Les entrées en jargon portent une courte
/// explication en dessous, pour qu'un nouveau responsable comprenne
/// où il va avant de toucher.
class TiroirCourt extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Membres,
  /// 2 Finances, 3 Départements).
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
            color: AppTheme.bleuNuit,
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
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white),
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                Text(
                  state.user?.fullName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white),
                ),
                Text(
                  state.roleLabel,
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
          ListTile(
            leading: const Icon(Icons.swap_horiz_outlined),
            title: const Text('Changer d’église'),
            subtitle: const Text(
                'Voir une autre de vos églises, par nom ou code'),
            onTap: () => _ouvrir(context, const MesEglisesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Réseau'),
            subtitle: const Text('Votre église et ses sous-églises'),
            onTap: () => _ouvrir(context, const TreeScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Annonces'),
            subtitle: const Text('Messages pour votre église'),
            onTap: () => _ouvrir(context, const AnnoncesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.church_outlined),
            title: const Text('Mon église'),
            subtitle: const Text('Présentation et horaires des cultes'),
            onTap: () => _ouvrir(context, const MonEgliseScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('Modules'),
            subtitle: const Text('Tous les modules de l’église'),
            onTap: () => _ouvrir(context, const ModulesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Demandes pour rejoindre une église'),
            subtitle: const Text('Personnes qui veulent vous rejoindre'),
            onTap: () => _ouvrir(context, const RattachementsScreen()),
          ),
          // Une annexe n'a pas d'annexe : l'entrée n'existe que pour
          // une église mère (règle du 11/11/2026).
          if (state.isAdmin && (church?.isMere ?? false))
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Mes annexes'),
              subtitle:
                  const Text('Églises annexes et leurs codes de tutelle'),
              onTap: () => _ouvrir(context, const AnnexesScreen()),
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
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Mon abonnement'),
              subtitle:
                  const Text('Plan, durée et renouvellement'),
              onTap: () => _ouvrir(context, const AbonnementScreen()),
            ),
          // Tranche P5 : rapports à mon église mère. Une annexe
          // seulement : une église mère n'a pas de mère à qui envoyer
          // ses rapports, elle lit les siens dans « Rapports reçus »
          // sur son accueil.
          if (state.isAdmin && !(church?.isMere ?? false))
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Rapports à mon église mère'),
              subtitle:
                  const Text('Envoyez vos rapports à votre église mère'),
              onTap: () => _ouvrir(context, const RapportsMereScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('À propos de e-System Church'),
            onTap: () => _ouvrir(context, const AProposScreen()),
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
