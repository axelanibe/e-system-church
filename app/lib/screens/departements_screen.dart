import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'enfants_screen.dart';
import 'familles_screen.dart';

/// Départements de l'église, en 3 onglets (maquette écran 4) :
/// Familles, Cellules, Enfants & jeunesse. Les onglets Familles et
/// Cellules réutilisent FamillesScreen, avec les boutons de création
/// affichés ici. L'onglet Enfants & jeunesse reste tel quel.
///
/// Les 16 départements sont un catalogue validé et fixe : l'interface
/// de gestion (créer, renommer, supprimer) a été retirée de cet écran.
/// L'onglet Budgets est retiré aussi : la création de budget relève
/// de l'écran 28, un seul accès aux budgets. Le titre
/// « Départements », le logo ESC et le bouton de menu sont déjà dans
/// l'en-tête clair de la coque (HomeScreen), on ne les duplique pas
/// ici : pas d'AppBar propre.
class DepartementsScreen extends StatefulWidget {
  const DepartementsScreen({super.key});

  @override
  State<DepartementsScreen> createState() => _DepartementsScreenState();
}

class _DepartementsScreenState extends State<DepartementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Bandeau violet (même style que MembresScreen) : 3 onglets,
          // indicateur or, défilant sur téléphone étroit. Le retour
          // est ici : l'écran n'a pas d'AppBar propre, il est poussé
          // depuis la grille Modules.
          Container(
            color: AppTheme.violetProfond,
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: AppTheme.or,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    ),
                    tabs: const [
                      Tab(text: 'Familles'),
                      Tab(text: 'Cellules'),
                      Tab(text: 'Enfants & jeunesse'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                // 1er onglet : Familles, avec le bouton « + Famille ».
                FamillesScreen(ongletUnique: 0),
                // 2e onglet : Cellules, avec le bouton « + Cellule ».
                FamillesScreen(ongletUnique: 1),
                // 3e onglet : « Enfants & jeunesse », déplacé de
                // Familles (maquette).
                EnfantsScreen(sansAppBar: true),
              ],
            ),
          ),
        ],
      ),
      // Pas de FAB propre : FamillesScreen apporte le sien sur les
      // onglets Familles et Cellules, EnfantsScreen sur le sien.
    );
  }
}
