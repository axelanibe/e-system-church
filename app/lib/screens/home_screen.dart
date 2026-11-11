import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module_eglise.dart';
import '../state/app_state.dart';
import '../widgets/church_avatar.dart';
import '../widgets/mere_badge.dart';
import 'annonces_screen.dart';
import 'dashboard_screen.dart';
import 'finances_mere_screen.dart';
import 'finances_screen.dart';
import 'membres_screen.dart';
import 'modules_activation_screen.dart';
import 'modules_screen.dart';
import 'mon_eglise_screen.dart';
import 'plateforme_screen.dart';
import 'rattachements_screen.dart';
import 'settings_screen.dart';
import 'transferts_screen.dart';
import 'tree_screen.dart';

/// Coquille principale après connexion : navigation entre les 6 écrans.
/// Écrans larges (≥ 900 px) : rail latéral ; écrans étroits : barre inférieure.
/// Le tiroir donne accès aux demandes de rattachement, à « Mes églises »
/// (sélecteur d'église active), à « Mon église », aux réglages et à la
/// déconnexion. L'AppBar affiche l'identité de l'église active (logo ou
/// initiales, nom et code) — données réelles de l'API.
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
    'Modules',
  ];

  /// Code du module US1 par destination, ou null (toujours visible). Seules
  /// les annonces sont un module activable dans cette navigation.
  static const List<String?> _modules = [
    null,
    null,
    null,
    null,
    'annonces',
    null,
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
      case 5:
        return const ModulesScreen();
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
      NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Modules'),
    ];

    // US1 : les destinations des modules désactivés disparaissent de la
    // navigation. `courant` est la destination réelle affichée.
    final visibles = <int>[];
    for (var i = 0; i < _titles.length; i++) {
      final code = _modules[i];
      if (code == null || state.isModuleActif(code)) visibles.add(i);
    }
    final courant = visibles[_index.clamp(0, visibles.length - 1)];
    final dests = visibles.map((i) => destinations[i]).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ChurchAvatar(church: church, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    church?.name ?? 'e-System Church',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (church != null)
                    Row(
                      children: [
                        Text(
                          church.code,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (church.isMere) ...[
                          const SizedBox(width: 8),
                          const MereBadge(),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            Text(
              _titles[courant],
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
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
                  ChurchAvatar(church: church, radius: 24),
                  const SizedBox(height: 8),
                  Text(
                    church?.name ?? 'e-System Church',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (church?.isMere ?? false) ...[
                    const SizedBox(height: 8),
                    const MereBadge(),
                  ],
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'MES ÉGLISES',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            for (final membership in state.eglises)
              ListTile(
                leading: ChurchAvatar(
                    church: membership.church, radius: 18),
                title: Text(membership.church.name),
                subtitle: Text(
                    '${membership.church.code} · ${membership.role}'),
                trailing: membership.church.id == church?.id
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.of(context).pop();
                  if (membership.church.id != church?.id) {
                    await context
                        .read<AppState>()
                        .switchChurch(membership.church.id);
                  }
                },
              ),
            const Divider(),
            // US1 : l'entrée Mon église disparaît si le module est désactivé.
            if (state.isModuleActif(CodesModules.monEglise))
              ListTile(
                leading: const Icon(Icons.church_outlined),
                title: const Text('Mon église'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MonEgliseScreen()),
                  );
                },
              ),
            if (state.isAdmin)
              ListTile(
                leading: const Icon(Icons.toggle_on_outlined),
                title: const Text('Modules de l’église'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ModulesActivationScreen()),
                  );
                },
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
              selectedIndex: visibles.indexOf(courant),
              onDestinationSelected: (i) =>
                  setState(() => _index = visibles[i]),
              labelType: NavigationRailLabelType.all,
              destinations: dests
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          Expanded(child: _screenFor(courant)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: visibles.indexOf(courant),
              onDestinationSelected: (i) =>
                  setState(() => _index = visibles[i]),
              destinations: dests,
            ),
    );
  }
}
