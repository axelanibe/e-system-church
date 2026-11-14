import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Modules de l'église (modèle projection, écran « Tous les modules »,
/// captures IMG_4018 à IMG_4020) : grille 2 colonnes, icône or,
/// titre, description et pastille d'état en bas de carte. L'ordre
/// des cartes suit la projection (Accueil admin, Espace membre,
/// Membres et familles, Cultes en direct, Radar pastoral, Finances,
/// Bible et école, Gouvernance, Réglages et confiance, Paiements
/// automatiques, US restantes et dette, Qualité et bascule,
/// Connexion). Liste d'état seulement : les cartes ne naviguent
/// pas, chaque module se rejoint par la barre du bas ou par le
/// tiroir, jamais par une grille. Tous les modules sont affichés
/// pour toutes les églises (règle du 11 novembre 2026) : rien à
/// activer ici. L'état du paiement automatique (T8) est corrigé
/// par rapport à la projection : construit et en ligne depuis la
/// PR #81, pas « À venir ».
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  static const _modules = [
    (
      'Accueil admin',
      'Carte Aujourd’hui, chiffres, réseau, annonces.',
      'T3 · Construit',
      Icons.home_outlined,
    ),
    (
      'Espace membre',
      'Carte avec QR, parcours, attestations, prière.',
      'T2 · Construit',
      Icons.badge_outlined,
    ),
    (
      'Membres et familles',
      'Fiche unique, création guidée, anniversaires.',
      'T4 · Construit',
      Icons.people_outline,
    ),
    (
      'Cultes en direct',
      'Conducteur chronométré, transposition, portes.',
      'T5 · Construit, en ligne',
      Icons.schedule_outlined,
    ),
    (
      'Radar pastoral',
      'Absences, rendez-vous, visites, accompagnements.',
      'T6 · Construit, en ligne',
      Icons.track_changes_outlined,
    ),
    (
      'Finances',
      'Cotisations, banque, caisse, reçus, budgets.',
      'T7 · Construit, en ligne',
      Icons.account_balance_wallet_outlined,
    ),
    (
      'Bible et école',
      'Lecture, cours et progression des membres.',
      'T9 · À venir',
      Icons.menu_book_outlined,
    ),
    (
      'Gouvernance',
      'Mandats, nominations, procès-verbaux, documents.',
      'T10 · Construit, en ligne',
      Icons.verified_outlined,
    ),
    (
      'Réglages et confiance',
      'Sauvegarde, hors ligne, 2FA, journal d’audit.',
      'T11 · Construit, en ligne',
      Icons.wb_sunny_outlined,
    ),
    (
      'Paiements automatiques',
      'Webhook Wave, puis Orange Money, puis MTN.',
      'T8 · Construit, en ligne',
      Icons.credit_card_outlined,
    ),
    (
      'US restantes et dette',
      'US4 à US17 restantes et dette.',
      'T12 · À venir',
      Icons.receipt_long_outlined,
    ),
    (
      'Qualité et bascule',
      'Contrôles qualité et bascule finale.',
      'T13 · À venir',
      Icons.fact_check_outlined,
    ),
    (
      'Connexion',
      'E-mail ou téléphone, inscription église ou membre.',
      'T1 · Construit',
      Icons.login_outlined,
    ),
  ];

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
                    color: AppTheme.bleuNuit,
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
                  for (final (titre, description, etat, icone) in _modules)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icone,
                                color: AppTheme.orFonce, size: 28),
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
                            Text(
                              description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
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
                                      : AppTheme.bleuNuit,
                                ),
                              ),
                            ),
                          ],
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
