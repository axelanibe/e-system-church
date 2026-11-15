import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'annexes_screen.dart';
import 'attestations_screen.dart';
import 'bible_fidele_screen.dart';
import 'cultes_direct_screen.dart';
import 'departements_screen.dart';
import 'ecole_biblique_screen.dart';
import 'gouvernance_screen.dart';
import 'pastoral_screen.dart';
import 'patrimoine_screen.dart';
import 'prieres_screen.dart';
import 'rapports_recus_screen.dart';
import 'rendez_vous_admin_screen.dart';
import 'serviteurs_screen.dart';

/// Modules de l'église (maquette Membres Finances, écran 21) : grille
/// de 13 cartes EXACTEMENT, dans l'ordre de la maquette. Chaque carte
/// ouvre sa vraie fonctionnalité, une seule entrée par fonction, jamais
/// de doublon avec la barre du bas (Accueil, Membres, Finances,
/// Départements) ni avec la connexion, qui est l'entrée de
/// l'application, ni avec l'espace fidèle, périmètre étanche.
/// La carte « Bible et école » ouvre les vrais écrans Bible de la T9 :
/// la lecture d'abord, l'école biblique par le bouton de la barre.
/// La carte « Messages admin » ouvre l'écran Prières, dont le 2e
/// onglet est « Messages internes » : il n'existe pas d'écran admin
/// de messages dédié dans l'application.
class ModulesScreen extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Membres,
  /// 2 Finances). Sans [onAller], une carte d'onglet revient
  /// simplement à l'écran précédent.
  final void Function(int index)? onAller;

  const ModulesScreen({super.key, this.onAller});

  static const _modules = [
    (
      'departements',
      'Départements',
      'Équipes, fonctions et cellules.',
      Icons.groups_outlined,
    ),
    (
      'cultes',
      'Cultes en direct',
      'Conducteur, transposition, portes.',
      Icons.schedule_outlined,
    ),
    (
      'pastoral',
      'Radar pastoral',
      'Absences, visites et accompagnements.',
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
      'Demandes et messages internes.',
      Icons.favorite_outline,
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
      'Messages internes de l’église.',
      Icons.message_outlined,
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
              title: const Text('Bible et école'),
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
      case 'messages':
        // Pas d'écran admin de messages dédié : les messages
        // internes vivent dans l'écran Prières, 2e onglet.
        _pousser(context, const PrieresScreen());
      case 'annexes':
        _pousser(context, const AnnexesScreen());
      case 'rapports':
        _pousser(context, const RapportsRecusScreen());
      case 'rendezVous':
        _pousser(context, const RendezVousAdminScreen());
      case 'attestations':
        _pousser(context, const AttestationsScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modules de l’église')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tous les modules',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
                children: [
                  for (final (cible, titre, description, icone)
                      in _modules)
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _ouvrir(context, cible),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icone,
                                      color: AppTheme.orFonce, size: 28),
                                  const Spacer(),
                                  const Icon(Icons.chevron_right,
                                      color: AppTheme.orFonce, size: 20),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                titre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(
                                  description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
