import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'church_avatar.dart';
import 'mere_badge.dart';
import '../screens/a_propos_screen.dart';
import '../screens/abonnement_screen.dart';
import '../screens/file_hors_ligne_screen.dart';
import '../screens/mes_eglises_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/paiements_screen.dart';
import '../screens/settings_screen.dart';

/// Tiroir désengorgé (maquette Membres Finances, écran 20) :
/// 7 entrées seulement, en deux sections (Outils, Compte), une par
/// ligne avec un titre et un sous-titre, dans le style clair de la
/// maquette d'Axel (14 novembre 2026) : icône violet profond sur fond
/// teinté 6 %, titre semi-bold sombre, sous-titre atténué, petit
/// chevron discret. Le fond est clair (thème du tiroir, blanc),
/// jamais sombre : un texte sombre y est illisible. Une seule entrée
/// par fonction, jamais de doublon avec la barre du bas (Accueil,
/// Membres, Finances, Modules). Les fonctions retirées restent
/// accessibles depuis leur écran parent : Cultes et Présences depuis
/// Modules, Suivi pastoral, Rendez-vous, Prières, Serviteurs et
/// Gouvernance depuis Modules, Rapports d'annexe et Mes annexes
/// depuis le tableau de bord. La Plateforme a sa propre connexion,
/// elle ne se rejoint pas depuis une église. L'en-tête montre
/// l'église courante ; le toucher change d'église (même espace
/// seulement, règle de bascule).
class TiroirCourt extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Membres,
  /// 2 Finances, 3 Modules).
  final void Function(int index) onAller;

  const TiroirCourt({super.key, required this.onAller});

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  /// Entrée claire, style de la maquette d'Axel : icône violet
  /// profond sur fond teinté 6 %, titre semi-bold, sous-titre
  /// atténué, petit chevron discret. Le `Expanded(column: false)`
  /// de la maquette est une erreur (Expanded n'a pas ce paramètre),
  /// il n'est pas repris.
  Widget _entree({
    required IconData icone,
    required String titre,
    required String sousTitre,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.violetProfond.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icone, color: AppTheme.violetProfond, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.violetProfond,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sousTitre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.texteSecondaire,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// Titre d'une section du tiroir (Outils, Compte) : petites
  /// majuscules, comme SectionTitle.
  Widget _titreSection(String titre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        titre.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.violetProfond,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// Ligne inerte « À venir » (maquette, écran 20 : « Qualité et
  /// bascule ») : même présentation qu'une entrée, sans chevron et
  /// sans navigation, avec une pastille « À venir ».
  Widget _entreeInerte({
    required IconData icone,
    required String titre,
    required String sousTitre,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.violetProfond.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icone, color: AppTheme.violetProfond, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.violetProfond,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sousTitre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.texteSecondaire,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.orClair,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'À venir',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.violetProfond,
              ),
            ),
          ),
        ],
      ),
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
                        icon: const Icon(Icons.close,
                            color: AppTheme.violetProfond),
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
                    // Maquette, écran 20 : 16 px.
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 16),
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
                      // Maquette, écran 20 : 12 px.
                      style: AppTheme.styleCode.copyWith(fontSize: 12),
                    ),
                  Text(
                    state.user?.fullName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Maquette, écran 20 : 12 px.
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 12),
                  ),
                  Text(
                    state.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Maquette, écran 20 : 12 px.
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: AppTheme.texteSecondaire,
                            fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(
                        Icons.swap_horiz_outlined,
                        size: 16,
                        color: AppTheme.violetProfond,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Changer d’église',
                        style: TextStyle(
                          color: AppTheme.texteSecondaire,
                          // Maquette, écran 20 : 12,5 px.
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: AppTheme.bordure, height: 1),
          _titreSection('Outils'),
          _entree(
            icone: Icons.notifications_outlined,
            titre: 'Notifications',
            sousTitre: 'Alertes et messages aux membres',
            onTap: () => _ouvrir(context, const NotificationsScreen()),
          ),
          _entree(
            icone: Icons.credit_card_outlined,
            titre: 'Paiements automatiques',
            sousTitre: 'Échéances programmées',
            onTap: () => _ouvrir(context, const PaiementsScreen()),
          ),
          _entree(
            icone: Icons.cloud_off_outlined,
            titre: 'File hors ligne',
            sousTitre: 'Actions en attente de synchronisation',
            onTap: () =>
                _ouvrir(context, const FileHorsLigneScreen()),
          ),
          _entreeInerte(
            icone: Icons.verified_outlined,
            titre: 'Qualité et bascule',
            sousTitre: 'Contrôles et bascule de version',
          ),
          _titreSection('Compte'),
          if (state.isAdmin)
            _entree(
              icone: Icons.payments_outlined,
              titre: 'Mon abonnement',
              sousTitre: 'État et renouvellement de l’abonnement',
              onTap: () => _ouvrir(context, const AbonnementScreen()),
            ),
          _entree(
            icone: Icons.settings_outlined,
            titre: 'Réglages',
            sousTitre: 'Profil, clés, rôles et mode test',
            onTap: () => _ouvrir(context, const SettingsScreen()),
          ),
          const Divider(color: AppTheme.bordure, height: 1),
          _entree(
            icone: Icons.info_outline,
            titre: 'À propos de e-System Church',
            sousTitre: 'L’église sans frontières',
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
                fontSize: 13.5,
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
