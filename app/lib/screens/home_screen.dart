import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'annonces_screen.dart';
import 'dashboard_screen.dart';
import 'finances_mere_screen.dart';
import 'finances_screen.dart';
import 'membres_screen.dart';
import 'plateforme_screen.dart';
import 'rattachements_screen.dart';
import 'settings_screen.dart';
import 'transferts_screen.dart';
import 'tree_screen.dart';

/// Coquille principale après connexion : navigation entre les 5 écrans du MVP.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre inférieure.
/// Le tiroir donne accès aux demandes de rattachement, aux réglages et à la
/// déconnexion.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = [
    'Tableau de bord',
    'Arborescence',
    'Membres',
    'Finances',
    'Annonces',
  ];

  Widget _screenFor(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const TreeScreen();
      case 2:
        return const MembresScreen();
      case 3:
        return const FinancesScreen();
      case 4:
        return const AnnoncesScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;
    final wide = MediaQuery.of(context).size.width >= 900;

    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Tableau de bord'),
      NavigationDestination(
          icon: Icon(Icons.account_tree_outlined),
          selectedIcon: Icon(Icons.account_tree),
          label: 'Arborescence'),
      NavigationDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: 'Membres'),
      NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Finances'),
      NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'Annonces'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (state.demoMode)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(label: Text('DÉMO'), visualDensity: VisualDensity.compact),
            ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    church?.name ?? 'e-System Church',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${church?.code ?? ''} · ${church?.city ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.user?.fullName ?? ''} — ${state.roleLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Demandes de rattachement'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RattachementsScreen()),
                );
              },
            ),
            if (state.isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('Plateforme'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PlateformeScreen()),
                  );
                },
              ),
            if (state.canManageMembers)
              ListTile(
                leading: const Icon(Icons.swap_horiz_outlined),
                title: const Text('Transferts de membres'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TransfertsScreen()),
                  );
                },
              ),
            if (state.isAdmin)
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Finances de la mère'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const FinancesMereScreen()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Réglages'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
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
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          Expanded(child: _screenFor(_index)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: destinations,
            ),
    );
  }
}
