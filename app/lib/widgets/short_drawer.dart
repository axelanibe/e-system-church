import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import '../screens/a_propos_screen.dart';
import '../screens/abonnement_screen.dart';
import '../screens/annonces_screen.dart';
import '../screens/mes_eglises_screen.dart';
import '../screens/biens_screen.dart';
import '../screens/cultes_direct_screen.dart';
import '../screens/enfants_screen.dart';
import '../screens/finances_complement_screen.dart';
import '../screens/medias_screen.dart';
import '../screens/mon_eglise_screen.dart';
import '../screens/pastoral_screen.dart';
import '../screens/presences_screen.dart';
import '../screens/prieres_screen.dart';
import '../screens/rapports_screen.dart';
import '../screens/serviteurs_screen.dart';
import '../screens/plateforme_screen.dart';
import '../screens/rapports_mere_screen.dart';
import '../screens/rattachements_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transferts_screen.dart';

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
    final codeVille = [church?.code, church?.city]
        .where((v) => (v ?? '').isNotEmpty)
        .join(' · ');
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
                if (codeVille.isNotEmpty)
                  Text(
                    codeVille,
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
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const MesEglisesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Annonces'),
            subtitle: const Text('Messages pour votre église'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const AnnoncesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.church_outlined),
            title: const Text('Mon église'),
            subtitle: const Text('Présentation et horaires des cultes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const MonEgliseScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Cultes en direct'),
            subtitle: const Text('Conducteur chronométré, transposition, portes.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const CultesDirectScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.how_to_reg_outlined),
            title: const Text('Présences'),
            subtitle: const Text('Feuille de présence par culte et statistiques.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const PresencesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Budget & caisse'),
            subtitle: const Text('Postes, budgets, dépenses, caisse et rapport financier.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const FinancesComplementScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('Prières & messages'),
            subtitle: const Text('Demandes de prière et messages internes.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const PrieresScreen()),
          ),
          if (state.canManageMembers)
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('Suivi pastoral'),
              subtitle: const Text('Parcours des nouveaux, visites et accompagnements.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _ouvrir(context, const PastoralScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Serviteurs'),
            subtitle: const Text('Affectations par département et planning des services.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const ServiteursScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.child_care_outlined),
            title: const Text('Enfants & jeunesse'),
            subtitle: const Text('Classes, autorisations de sortie et activités.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const EnfantsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: const Text('Médias & bibliothèque'),
            subtitle: const Text('Prédications, plans de lecture, livres et prêts.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const MediasScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: const Text('Biens de l’église'),
            subtitle: const Text('Salles, réservations, matériel et maintenance.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const BiensScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.assessment_outlined),
            title: const Text('Rapports'),
            subtitle: const Text('Statistiques globales et export CSV.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const RapportsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Demandes pour rejoindre une église'),
            subtitle: const Text('Personnes qui veulent vous rejoindre'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const RattachementsScreen()),
          ),
          if (state.isSuperAdmin)
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Plateforme'),
              subtitle: const Text('Chiffres de toutes les églises'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _ouvrir(context, const PlateformeScreen()),
            ),
          if (state.canManageMembers)
            ListTile(
              leading: const Icon(Icons.sync_alt_outlined),
              title: const Text('Transferts de membres'),
              subtitle: const Text('Déplacer un membre vers une église'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _ouvrir(context, const TransfertsScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Réglages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(context, const SettingsScreen()),
          ),
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Mon abonnement'),
              subtitle:
                  const Text('Plan, durée et renouvellement'),
              trailing: const Icon(Icons.chevron_right),
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _ouvrir(context, const RapportsMereScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('À propos de e-System Church'),
            trailing: const Icon(Icons.chevron_right),
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
