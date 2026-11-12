import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'camps_fidele_screen.dart';
import 'cotisations_screen.dart';
import 'journal_screen.dart';
import 'mes_attestations_screen.dart';
import 'parametres_fidele_screen.dart';

/// Menu Plus du fidèle (tranche P1).
/// Ordre P1 : Mon journal, Mes cotisations, Mes camps, Mes attestations,
/// Prière du jour, Sujet de prière privé, Paramètres, Se déconnecter,
/// Voir l'espace admin. Pas de Prendre rendez-vous (P4), pas d'À propos (P2).
class PlusFideleScreen extends StatelessWidget {
  /// Appelé pour aller sur l'accueil fidèle (Prière du jour, Sujet de prière).
  final VoidCallback? onAllerAccueil;

  const PlusFideleScreen({super.key, this.onAllerAccueil});

  @override
  Widget build(BuildContext context) {
    final apercu = context.watch<AppState>().apercuFidele;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: 'Mon menu'),
        Text(
          'Tout votre espace, en un seul endroit.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _LigneMenu(
                icone: Icons.edit_outlined,
                titre: 'Mon journal',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const JournalScreen(),
                  ),
                ),
              ),
              _LigneMenu(
                icone: Icons.account_balance_wallet_outlined,
                titre: 'Mes cotisations',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CotisationsScreen(),
                  ),
                ),
              ),
              _LigneMenu(
                icone: Icons.event_outlined,
                titre: 'Mes camps',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CampsFideleScreen(),
                  ),
                ),
              ),
              _LigneMenu(
                icone: Icons.receipt_long_outlined,
                titre: 'Mes attestations',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MesAttestationsScreen(),
                  ),
                ),
              ),
              _LigneMenu(
                icone: Icons.favorite_outline,
                titre: 'Prière du jour',
                onTap: () {
                  onAllerAccueil?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('La prière du jour est sur votre accueil.'),
                    ),
                  );
                },
              ),
              _LigneMenu(
                icone: Icons.volunteer_activism_outlined,
                titre: 'Sujet de prière privé',
                onTap: () {
                  onAllerAccueil?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Votre sujet de prière privé est sur votre accueil.',
                      ),
                    ),
                  );
                },
              ),
              _LigneMenu(
                icone: Icons.settings_outlined,
                titre: 'Paramètres',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ParametresFideleScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'Démonstration'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Voir l’espace admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (apercu) {
                    context.read<AppState>().sortirApercuFidele();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'L’espace admin est réservé aux responsables '
                          'de votre église.',
                        ),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => context.read<AppState>().logout(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Tu es un don de Dieu',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.orFonce,
                ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LigneMenu extends StatelessWidget {
  final IconData icone;
  final String titre;
  final VoidCallback onTap;

  const _LigneMenu({
    required this.icone,
    required this.titre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone),
      title: Text(titre),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
