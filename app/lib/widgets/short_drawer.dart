import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import '../screens/a_propos_screen.dart';
import '../screens/abonnement_screen.dart';
import '../screens/cultes_direct_screen.dart';
import '../screens/mes_eglises_screen.dart';
import '../screens/modules_screen.dart';
import '../screens/pastoral_screen.dart';
import '../screens/prieres_screen.dart';
import '../screens/rapports_recus_screen.dart';
import '../screens/rendez_vous_admin_screen.dart';
import '../screens/annexes_screen.dart';
import '../screens/confiance_screen.dart';
import '../screens/gouvernance_screen.dart';
import '../screens/serviteurs_screen.dart';
import '../screens/settings_screen.dart';

/// Tiroir désengorgé (simulation tiroir désengorgé, modèle projection) :
/// 11 entrées essentielles, une par ligne avec un titre et un sous-titre,
/// icônes or sur fond bleu nuit. Une seule entrée par fonction, jamais
/// de doublon avec la barre du bas (Accueil, Membres, Finances,
/// Départements). Les autres fonctions restent accessibles depuis leur
/// écran parent : Annonces depuis l'accueil, Présences depuis Cultes,
/// Budget & caisse depuis Finances, Enfants & jeunesse depuis
/// Départements, Médias depuis Cultes, Biens et Mon église depuis
/// Réglages, Transferts et Demandes depuis Mes annexes et Réseau,
/// Statistiques et exports depuis Rapports d'annexe. La Plateforme a
/// sa propre connexion, elle ne se rejoint pas depuis une église.
/// L'en-tête montre l'église courante ; le toucher change d'église
/// (même espace seulement, règle de bascule).
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

  Widget _entree({
    required IconData icone,
    required String titre,
    required String sousTitre,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icone, color: AppTheme.or),
      title: Text(
        titre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        sousTitre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: Colors.white54,
      ),
      onTap: onTap,
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
      backgroundColor: AppTheme.bleuNuit,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          InkWell(
            onTap: () => _ouvrir(context, const MesEglisesScreen()),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChurchAvatar(church: church, radius: 24),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
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
                      style: AppTheme.styleCode.copyWith(
                        color: Colors.white70,
                      ),
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
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(
                        Icons.swap_horiz_outlined,
                        size: 16,
                        color: AppTheme.or,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Changer d’église',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          _entree(
            icone: Icons.church_outlined,
            titre: 'Cultes et Présences',
            sousTitre: 'Pointage QR et compteurs portes',
            onTap: () => _ouvrir(context, const CultesDirectScreen()),
          ),
          if (state.canManageMembers)
            _entree(
              icone: Icons.shield_outlined,
              titre: 'Suivi pastoral',
              sousTitre: 'Radar d’absences et visites',
              onTap: () => _ouvrir(context, const PastoralScreen()),
            ),
          if (state.canManageMembers)
            _entree(
              icone: Icons.event_available_outlined,
              titre: 'Rendez-vous',
              sousTitre: 'Demandes et créneaux pastoraux',
              onTap: () =>
                  _ouvrir(context, const RendezVousAdminScreen()),
            ),
          _entree(
            icone: Icons.favorite_outline,
            titre: 'Prières',
            sousTitre: 'Sujets confidentiels et équipe',
            onTap: () => _ouvrir(context, const PrieresScreen()),
          ),
          _entree(
            icone: Icons.handshake_outlined,
            titre: 'Serviteurs',
            sousTitre: 'Affectations et fonctions',
            onTap: () => _ouvrir(context, const ServiteursScreen()),
          ),
          if (state.canManageMembers)
            _entree(
              icone: Icons.verified_outlined,
              titre: 'Gouvernance',
              sousTitre: 'Mandats, conseil, documents',
              onTap: () => _ouvrir(context, const GouvernanceScreen()),
            ),
          if (state.isAdmin)
            _entree(
              // T13, D09 : icône unique par fonction — le bouclier
              // est déjà celui du Suivi pastoral.
              icone: Icons.verified_user_outlined,
              titre: 'Confiance',
              sousTitre: 'Sauvegarde, hors ligne, 2FA, audit',
              onTap: () => _ouvrir(context, const ConfianceScreen()),
            ),
          _entree(
            icone: Icons.description_outlined,
            titre: 'Rapports d’annexe',
            sousTitre: 'Bilans PDF périodiques',
            onTap: () => _ouvrir(context, const RapportsRecusScreen()),
          ),
          _entree(
            icone: Icons.account_tree_outlined,
            titre: 'Mes annexes et Réseau',
            sousTitre: 'Branches, tutelle et transferts',
            onTap: () => _ouvrir(context, const AnnexesScreen()),
          ),
          if (state.isAdmin)
            _entree(
              icone: Icons.payments_outlined,
              titre: 'Mon abonnement',
              sousTitre: 'État et renouvellement de l’abonnement',
              onTap: () => _ouvrir(context, const AbonnementScreen()),
            ),
          _entree(
            icone: Icons.grid_view_outlined,
            titre: 'Modules de l’église',
            sousTitre: 'Noyau et modules activables',
            onTap: () => _ouvrir(context, ModulesScreen(onAller: onAller)),
          ),
          _entree(
            icone: Icons.settings_outlined,
            titre: 'Réglages',
            sousTitre: 'Profil, clés, rôles et mode test',
            onTap: () => _ouvrir(context, const SettingsScreen()),
          ),
          const Divider(color: Colors.white24, height: 1),
          _entree(
            icone: Icons.info_outline,
            titre: 'À propos de e-System Church',
            sousTitre: 'L’église sans frontière',
            onTap: () => _ouvrir(context, const AProposScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.rougeErreur),
            title: const Text(
              'Se déconnecter',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.rougeErreur,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
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
