import 'package:flutter/material.dart';

import 'biens_screen.dart';
import 'cultes_screen.dart';
import 'enfants_screen.dart';
import 'familles_screen.dart';
import 'finances_complement_screen.dart';
import 'medias_screen.dart';
import 'mon_eglise_screen.dart';
import 'parametres_screen.dart';
import 'pastoral_screen.dart';
import 'presences_screen.dart';
import 'prieres_screen.dart';
import 'rapports_screen.dart';
import 'serviteurs_screen.dart';

/// Hub « Modules » : grille de cartes vers les 12 modules et Mon église.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const modules = <_ModuleCard>[
      _ModuleCard(
        icon: Icons.family_restroom_outlined,
        label: 'Familles',
        description: 'Familles, départements, cellules et fiches complètes.',
        screen: FamillesScreen(),
      ),
      _ModuleCard(
        icon: Icons.event_outlined,
        label: 'Cultes',
        description: 'Types de culte, cultes, ordre du culte et événements.',
        screen: CultesScreen(),
      ),
      _ModuleCard(
        icon: Icons.how_to_reg_outlined,
        label: 'Présences',
        description: 'Feuille de présence par culte et statistiques.',
        screen: PresencesScreen(),
      ),
      _ModuleCard(
        icon: Icons.account_balance_outlined,
        label: 'Budget & caisse',
        description: 'Postes, budgets, dépenses, caisse et rapport financier.',
        screen: FinancesComplementScreen(),
      ),
      _ModuleCard(
        icon: Icons.volunteer_activism_outlined,
        label: 'Prières & messages',
        description: 'Demandes de prière et messages internes.',
        screen: PrieresScreen(),
      ),
      _ModuleCard(
        icon: Icons.route_outlined,
        label: 'Suivi pastoral',
        description: 'Parcours des nouveaux, visites et accompagnements.',
        screen: PastoralScreen(),
      ),
      _ModuleCard(
        icon: Icons.volunteer_activism_outlined,
        label: 'Serviteurs',
        description: 'Affectations par département et planning des services.',
        screen: ServiteursScreen(),
      ),
      _ModuleCard(
        icon: Icons.child_care_outlined,
        label: 'Enfants & jeunesse',
        description: 'Classes, autorisations de sortie et activités.',
        screen: EnfantsScreen(),
      ),
      _ModuleCard(
        icon: Icons.mic_outlined,
        label: 'Médias & bibliothèque',
        description: 'Prédications, plans de lecture, livres et prêts.',
        screen: MediasScreen(),
      ),
      _ModuleCard(
        icon: Icons.meeting_room_outlined,
        label: 'Biens de l’église',
        description: 'Salles, réservations, matériel et maintenance.',
        screen: BiensScreen(),
      ),
      _ModuleCard(
        icon: Icons.assessment_outlined,
        label: 'Rapports',
        description: 'Statistiques globales et export CSV.',
        screen: RapportsScreen(),
      ),
      _ModuleCard(
        icon: Icons.settings_outlined,
        label: 'Paramètres',
        description: 'Paramètres de l’église, rôles et journal d’audit.',
        screen: ParametresScreen(),
      ),
      _ModuleCard(
        icon: Icons.church_outlined,
        label: 'Mon église',
        description: 'Logo, présentation, horaires, pasteur et antennes.',
        screen: MonEgliseScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules'),
        automaticallyImplyLeading: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            itemCount: modules.length,
            itemBuilder: (context, index) {
              final module = modules[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => module.screen),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(module.icon,
                            size: 32,
                            color:
                                Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          module.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            module.description,
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ModuleCard {
  final IconData icon;
  final String label;
  final String description;
  final Widget screen;

  const _ModuleCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.screen,
  });
}
