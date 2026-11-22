import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'activites_screen.dart';
import 'annexes_screen.dart';
import 'attestations_screen.dart';
import 'bible_fidele_screen.dart';
import 'cultes_direct_screen.dart';
import 'departements_screen.dart';
import 'ecole_biblique_screen.dart';
import 'gouvernance_screen.dart';
import 'identite_institutionnelle_screen.dart';
import 'messages_admin_screen.dart';
import 'pastoral_screen.dart';
import 'patrimoine_screen.dart';
import 'prieres_screen.dart';
import 'rapports_recus_screen.dart';
import 'rendez_vous_admin_screen.dart';
import 'serviteurs_screen.dart';
import 'temoignages_screen.dart';

/// Modules de l'église (maquette Membres Finances, écran 21) : grille
/// de 16 cartes, les 13 de la maquette plus « Identité
/// institutionnelle » (phase 2), en dernière position, « Activités »
/// (V1, migration 039), après « Cultes en direct », et « Témoignages »
/// (lot 3c, migration 041), après « Prières » : la maquette ne
/// parle d'aucune carte Activités, c'est le placement retenu. La carte
/// « Messagerie » ajoutée par la tranche T-Msg-1 a été retirée
/// (design couleurs messagerie, 16 nov. 2026) : la messagerie est
/// désormais un onglet de la barre du bas, une seule entrée par
/// fonction, jamais de doublon avec la barre du bas (Accueil,
/// Membres, Finances, Modules, Messagerie) ni avec la connexion, qui
/// est l'entrée de l'application, ni avec l'espace fidèle, périmètre
/// étanche. La carte « Mes annexes » porte la bordure or de la
/// Projection (.annexe-cover) : les 12 autres cartes restent
/// blanches, conformes à la maquette écran 21.
/// La carte « Bible et école » ouvre les vrais écrans Bible de la T9 :
/// la lecture d'abord, l'école biblique par le bouton de la barre.
/// La carte « Messages admin » ouvre MessagesAdminScreen, l'écran
/// dédié de l'administration (contrat : `MessagesAdminScreen`,
/// constructeur par défaut).
class ModulesScreen extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Membres,
  /// 2 Finances, 3 Modules, 4 Messagerie). Sans [onAller], une carte d'onglet revient
  /// simplement à l'écran précédent.
  final void Function(int index)? onAller;

  /// [sansAppBar] : intégré comme onglet (barre du bas), sans sa propre
  /// barre, l'en-tête clair de HomeScreen donne déjà le titre.
  final bool sansAppBar;

  const ModulesScreen({super.key, this.onAller, this.sansAppBar = false});

  static const _modules = [
    (
      'departements',
      'Départements',
      'Familles, cellules, enfants & jeunesse',
      Icons.groups_outlined,
    ),
    (
      'cultes',
      'Cultes en direct',
      'Conducteur chronométré, transposition, portes',
      Icons.schedule_outlined,
    ),
    (
      'activites',
      'Activités',
      'Sorties, réunions, formations.',
      Icons.event_outlined,
    ),
    (
      'pastoral',
      'Suivi pastoral',
      'Radar, parcours, visites, accompagnements',
      Icons.track_changes_outlined,
    ),
    (
      'serviteurs',
      'Serviteurs',
      'Affectations et planning.',
      Icons.handshake_outlined,
    ),
    (
      'bible',
      'Bible et école',
      'Lecture, cours et progression.',
      Icons.menu_book_outlined,
    ),
    (
      'gouvernance',
      'Gouvernance',
      'Mandats, procès-verbaux, documents.',
      Icons.verified_outlined,
    ),
    (
      'patrimoine',
      'Patrimoine',
      'Biens, salles et maintenance.',
      Icons.home_work_outlined,
    ),
    (
      'prieres',
      'Prières',
      'Demandes de prière des membres',
      Icons.favorite_outline,
    ),
    (
      'temoignages',
      'Témoignages',
      'Témoignages des membres, modérés par l’église.',
      Icons.mic_outlined,
    ),
    (
      'annexes',
      'Mes annexes',
      'Réseau, transferts et rattachements.',
      Icons.account_tree_outlined,
    ),
    (
      'rapports',
      'Rapports d’annexe',
      'Bilans reçus des annexes.',
      Icons.description_outlined,
    ),
    (
      'rendezVous',
      'Rendez-vous',
      'Demandes et créneaux pastoraux.',
      Icons.event_available_outlined,
    ),
    (
      'attestations',
      'Attestations d’actes',
      'Baptêmes, mariages et attestations.',
      Icons.badge_outlined,
    ),
    (
      'messages',
      'Messages admin',
      'Messages de l’administration aux églises',
      Icons.message_outlined,
    ),
    (
      'identite',
      'Identité institutionnelle',
      'Logo, coordonnées et modèles hérités.',
      Icons.account_balance_outlined,
    ),
  ];

  void _pousser(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  /// Ouvre la vraie fonctionnalité du module [cible].
  void _ouvrir(BuildContext context, String cible) {
    switch (cible) {
      case 'departements':
        _pousser(context, const DepartementsScreen());
      case 'cultes':
        _pousser(context, const CultesDirectScreen());
      case 'activites':
        _pousser(context, const ActivitesScreen());
      case 'pastoral':
        _pousser(context, const PastoralScreen());
      case 'serviteurs':
        _pousser(context, const ServiteursScreen());
      case 'bible':
        // La Bible est un écran sans Scaffold propre : on l'habille
        // ici, comme dans l'accueil fidèle. L'école biblique, qui a
        // sa propre barre, s'ouvre par le bouton de la barre.
        _pousser(
          context,
          Scaffold(
            appBar: AppBar(
              title: const Text('Bible et école biblique'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.school_outlined),
                  tooltip: 'École biblique',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EcoleBibliqueScreen(),
                    ),
                  ),
                ),
              ],
            ),
            body: const BibleFideleScreen(),
          ),
        );
      case 'gouvernance':
        _pousser(context, const GouvernanceScreen());
      case 'patrimoine':
        _pousser(context, const PatrimoineScreen());
      case 'prieres':
        _pousser(context, const PrieresScreen());
      case 'temoignages':
        _pousser(context, const TemoignagesScreen());
      case 'messages':
        // Écran admin de messages dédié (maquette, écran 31).
        _pousser(context, const MessagesAdminScreen());
      case 'annexes':
        _pousser(context, const AnnexesScreen());
      case 'rapports':
        _pousser(context, const RapportsRecusScreen());
      case 'rendezVous':
        _pousser(context, const RendezVousAdminScreen());
      case 'attestations':
        _pousser(context, const AttestationsScreen());
      case 'identite':
        _pousser(context, const IdentiteInstitutionnelleScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: sansAppBar
          ? null
          : AppBar(title: const Text('Modules de l’église')),
      // Un seul défilement : en-tête et grille dans le même
      // CustomScrollView (SliverGrid), sans défilement imbriqué. E5.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tous les modules',
                        // Maquette, écran 21 : 16 px.
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Une carte par fonction : touchez un module pour ouvrir '
                        'son écran.',
                        // Maquette, écran 21 : 12,5 px.
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid.count(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  // Cartes compactes, à la hauteur de leur contenu
                  // (icône, titre, description) : 1,25 en 2 colonnes,
                  // 2,0 en 3 colonnes. L'ancien 0,82 laissait un grand
                  // vide blanc sous chaque module.
                  childAspectRatio:
                      crossAxisCount == 2 ? 1.25 : 2.0,
                  children: [
                    for (final (cible, titre, description, icone)
                        in _modules)
                      _carteModule(
                        context,
                        cible,
                        titre,
                        description,
                        icone,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Une carte de la grille. La carte « Mes annexes » porte une
  /// variante ciblée, référence Projection (.annexe-cover) : fond
  /// carte blanc, bordure or, icône et chevron or foncé, titre bleu
  /// nuit. Les autres cartes restent blanches, bordure standard,
  /// conformes à la maquette écran 21. Pas de dégradé sur
  /// « Mes annexes » (précision d'Axel, 16 nov. 2026 : la Projection
  /// est la référence, pas la maquette).
  Widget _carteModule(
    BuildContext context,
    String cible,
    String titre,
    String description,
    IconData icone,
  ) {
    final estAnnexes = cible == 'annexes';
    final contenu = Padding(
      // Maquette, écran 21 (.modcard) : 10 px.
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icone,
                color: AppTheme.orFonce,
                size: 19,
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.orFonce,
                size: 15,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Zone de titre de hauteur fixe (2 lignes de 13 px) : le
          // sous-titre commence à la même hauteur d'une carte à
          // l'autre, titres et chevrons alignés. E10.
          SizedBox(
            height: 32,
            child: Text(
              titre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Maquette, écran 21 (.modcard .mt) : 13 px.
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              // Maquette, écran 21 (.modcard .md) : 11 px.
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
    if (estAnnexes) {
      return Card(
        // Projection (.annexe-cover) : bordure or sur fond carte.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.or, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _ouvrir(context, cible),
          child: contenu,
        ),
      );
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ouvrir(context, cible),
        child: contenu,
      ),
    );
  }
}
