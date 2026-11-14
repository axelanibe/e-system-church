import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import 'cartes_membres_screen.dart';
import 'confiance_screen.dart';
import 'cultes_direct_screen.dart';
import 'gouvernance_screen.dart';
import 'paiements_screen.dart';
import 'pastoral_screen.dart';
import 'promesses_screen.dart';

/// Modules de l'église (modèle projection, écran « Tous les modules »,
/// captures IMG_4018 à IMG_4020) : grille 2 colonnes, icône or,
/// titre, description et pastille d'état en bas de carte. L'ordre
/// des cartes suit la projection (Accueil admin, Espace membre,
/// Membres et familles, Cultes en direct, Radar pastoral, Finances,
/// Bible et école, Gouvernance, Réglages et confiance, Paiements
/// automatiques, US restantes et dette, Qualité et bascule,
/// Connexion). Tous les modules sont affichés pour toutes les
/// églises (règle du 11 novembre 2026) : rien à activer ici.
/// Chaque carte ouvre sa vraie fonctionnalité : les modules Accueil,
/// Membres et Finances sont des onglets, ils s'ouvrent par [onAller]
/// (comme le tiroir) ; les autres poussent leur écran, qui a son
/// retour par l'AppBar. Trois modules n'ont pas encore de cible
/// réelle dans l'application : Bible et école (tranche T9, pas
/// encore en ligne), Qualité et bascule (contrôles automatisés,
/// sans écran dédié) et Connexion (l'utilisateur est déjà
/// connecté) ; leur carte ne navigue pas et l'explique par un
/// message, sans inventer de fausse cible.
class ModulesScreen extends StatelessWidget {
  /// Aller à un onglet de la barre du bas (0 Accueil, 1 Membres,
  /// 2 Finances). Sans [onAller], une carte d'onglet revient
  /// simplement à l'écran précédent.
  final void Function(int index)? onAller;

  const ModulesScreen({super.key, this.onAller});

  /// Modules sans cible réelle : la carte ne navigue pas.
  static const _sansCible = {'bible', 'qualite', 'connexion'};

  static const _modules = [
    (
      'accueil',
      'Accueil admin',
      'Carte Aujourd’hui, chiffres, réseau, annonces.',
      'T3 · Construit',
      Icons.home_outlined,
    ),
    (
      'espaceMembre',
      'Espace membre',
      'Carte avec QR, parcours, attestations, prière.',
      'T2 · Construit',
      Icons.badge_outlined,
    ),
    (
      'membres',
      'Membres et familles',
      'Fiche unique, création guidée, anniversaires.',
      'T4 · Construit',
      Icons.people_outline,
    ),
    (
      'cartes',
      'Cartes de membre',
      'Voir les cartes et les imprimer.',
      'Admin · Construit',
      Icons.print_outlined,
    ),
    (
      'cultes',
      'Cultes en direct',
      'Conducteur chronométré, transposition, portes.',
      'T5 · Construit, en ligne',
      Icons.schedule_outlined,
    ),
    (
      'pastoral',
      'Radar pastoral',
      'Absences, rendez-vous, visites, accompagnements.',
      'T6 · Construit, en ligne',
      Icons.track_changes_outlined,
    ),
    (
      'finances',
      'Finances',
      'Cotisations, banque, caisse, reçus, budgets.',
      'T7 · Construit, en ligne',
      Icons.account_balance_wallet_outlined,
    ),
    (
      'bible',
      'Bible et école',
      'Lecture, cours et progression des membres.',
      'T9 · Construit',
      Icons.menu_book_outlined,
    ),
    (
      'gouvernance',
      'Gouvernance',
      'Mandats, nominations, procès-verbaux, documents.',
      'T10 · Construit, en ligne',
      Icons.verified_outlined,
    ),
    (
      'confiance',
      'Réglages et confiance',
      'Sauvegarde, hors ligne, 2FA, journal d’audit.',
      'T11 · Construit, en ligne',
      Icons.wb_sunny_outlined,
    ),
    (
      'paiements',
      'Paiements automatiques',
      'Webhook Wave, puis Orange Money, puis MTN.',
      'T8 · Construit, en ligne',
      Icons.credit_card_outlined,
    ),
    (
      'usRestantes',
      'US restantes et dette',
      'US4 à US17 restantes et dette.',
      'T12 · Construit, en ligne',
      Icons.receipt_long_outlined,
    ),
    (
      'qualite',
      'Qualité et bascule',
      'Contrôles qualité et bascule finale.',
      'T13 · À venir',
      Icons.fact_check_outlined,
    ),
    (
      'connexion',
      'Connexion',
      'E-mail ou téléphone, inscription église ou membre.',
      'T1 · Construit',
      Icons.login_outlined,
    ),
  ];

  void _pousser(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  void _info(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Ouvre la vraie fonctionnalité du module [cible]. Les onglets
  /// se rejoignent par [onAller] : la carte est dépilée d'abord,
  /// sinon l'onglet changerait sous la grille, invisible.
  void _ouvrir(BuildContext context, String cible) {
    switch (cible) {
      case 'accueil':
      case 'membres':
      case 'finances':
        final index = {'accueil': 0, 'membres': 1, 'finances': 2}[cible]!;
        Navigator.of(context).pop();
        onAller?.call(index);
      case 'espaceMembre':
        // Même accès que le tableau de bord (« Basculer vers
        // l’espace fidèle ») : aperçu avec retour, sans changer
        // de session.
        context.read<AppState>().entrerApercuFidele();
      case 'cultes':
        _pousser(context, const CultesDirectScreen());
      case 'cartes':
        _pousser(context, const CartesMembresScreen());
      case 'pastoral':
        _pousser(context, const PastoralScreen());
      case 'bible':
        _info(
          context,
          'Bible et école biblique : tranche T9 en cours, '
          'pas encore en ligne.',
        );
      case 'gouvernance':
        _pousser(context, const GouvernanceScreen());
      case 'confiance':
        _pousser(context, const ConfianceScreen());
      case 'paiements':
        _pousser(context, const PaiementsScreen());
      case 'usRestantes':
        // Entrée des US restantes : les promesses (US4), les
        // autres écrans se rejoignent depuis Finances, Membres,
        // Suivi pastoral, Mes annexes et Réglages.
        _pousser(context, const PromessesScreen());
      case 'qualite':
        _info(
          context,
          'Qualité et bascule : contrôles automatisés en place, '
          'sans écran dédié dans l’application.',
        );
      case 'connexion':
        _info(context, 'Connexion : vous êtes déjà connecté.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modules de l’église')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Tous les modules',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.or,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'T1 à T13',
                  style: AppTheme.styleCode.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.violetProfond,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Chaque module de l’application finale, construit ou prévu. '
            'Tous les modules sont affichés pour toutes les églises.',
          ),
          const SizedBox(height: 16),
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
                  for (final (cible, titre, description, etat, icone)
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
                                  if (!_sansCible.contains(cible))
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
                              // La description prend la place restante et
                              // s'ellipse : sans elle, les cartes à titre
                              // long débordaient de 33 px sur un téléphone
                              // de 390 px (titre 2 lignes + description
                              // 3 lignes + pastille 2 lignes).
                              Expanded(
                                child: Text(
                                  description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: etat.contains('À venir')
                                      ? Colors.grey.shade200
                                      : AppTheme.orClair,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  etat,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.styleCode.copyWith(
                                    color: etat.contains('À venir')
                                        ? Colors.grey.shade700
                                        : AppTheme.violetProfond,
                                  ),
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
