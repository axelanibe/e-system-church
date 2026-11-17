import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/dialog_helpers.dart';

/// Module 1 — Familles et cellules de l'église.
/// La fiche complète d'un membre (statuts, baptême, liens) s'ouvre depuis
/// l'onglet Fiche de l'écran Membres. Les départements se gèrent dans
/// l'onglet Départements ; les fonctions et les postes sont des options
/// dans les formulaires où on les attribue.
///
/// [masquerCreation] : intégré dans l'onglet Familles de l'écran
/// Membres (maquette écran 1), sans boutons de création : la création
/// se fait dans l'écran Départements (maquette écran 4).
/// [ongletUnique] : intégré comme un seul onglet de l'écran
/// Départements (maquette écran 4), 0 Familles ou 1 Cellules, sans
/// sa propre barre d'onglets ni défilement entre les deux.
///
/// Mise en page (maquette d'Axel, 14 novembre 2026) : bandeau violet
/// avec les onglets Familles / Cellules (indicateur or) et la recherche
/// blanche arrondie, état vide élégant, bouton flottant étendu. Le
/// titre « Départements », le logo ESC et le bouton de menu sont déjà
/// dans l'en-tête clair de la coque (HomeScreen), on ne les duplique
/// pas ici : pas d'AppBar propre, pas de pastille logo, pas de barre
/// de navigation du bas (la coque les fournit déjà).
class FamillesScreen extends StatefulWidget {
  final bool masquerCreation;
  final int? ongletUnique;

  const FamillesScreen({
    super.key,
    this.masquerCreation = false,
    this.ongletUnique,
  });

  @override
  State<FamillesScreen> createState() => _FamillesScreenState();
}

class _FamillesScreenState extends State<FamillesScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  // Liste brute vide (avant recherche) par onglet : masque la
  // recherche de l'onglet quand sa liste est vide (maquette écran 4 :
  // pas de recherche sur une liste vide).
  bool _famillesVides = false;
  bool _cellulesVides = false;

  late Future<List<Famille>> _famillesFuture;
  late Future<List<Cellule>> _cellulesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletUnique ?? 0;
    _refreshAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    final api = context.read<AppState>().api;
    setState(() {
      _famillesFuture = api.getFamilles();
      _cellulesFuture = api.getCellules();
      _membresFuture = api.getMembers();
    });
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _famillesFuture = api.getFamilles();
      if (_tab == 1) _cellulesFuture = api.getCellules();
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<void> _createFamille(List<Member> membres) async {
    final nomController = TextEditingController();
    final adresseController = TextEditingController();
    final telephoneController = TextEditingController();
    String? chefId;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle famille',
      saveLabel: 'Créer la famille',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la famille'),
        dialogDropdown<String?>(
          value: chefId,
          label: 'Responsable',
          options: {
            null: membres.isEmpty
                ? 'Aucun membre — créez d’abord un membre'
                : 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => chefId = v,
        ),
        dialogTextField(controller: adresseController, label: 'Adresse'),
        dialogTextField(
          controller: telephoneController,
          label: 'Téléphone',
          keyboardType: TextInputType.phone,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createFamille(
                nom: nomController.text.trim(),
                chefFamilleId: chefId,
                adresse: adresseController.text.trim().isEmpty
                    ? null
                    : adresseController.text.trim(),
                telephone: telephoneController.text.trim().isEmpty
                    ? null
                    : telephoneController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Famille créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createCellule(List<Member> membres) async {
    final nomController = TextEditingController();
    final quartierController = TextEditingController();
    final jourController = TextEditingController();
    final heureController = TextEditingController();
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle cellule',
      saveLabel: 'Créer la cellule',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la cellule'),
        dialogTextField(controller: quartierController, label: 'Quartier'),
        dialogDropdown<String?>(
          value: responsableId,
          label: 'Responsable',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => responsableId = v,
        ),
        dialogTextField(controller: jourController, label: 'Jour de réunion'),
        dialogTextField(controller: heureController, label: 'Heure de réunion'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCellule(
                nom: nomController.text.trim(),
                quartier: quartierController.text.trim().isEmpty
                    ? null
                    : quartierController.text.trim(),
                responsableMemberId: responsableId,
                jourReunion: jourController.text.trim().isEmpty
                    ? null
                    : jourController.text.trim(),
                heureReunion: heureController.text.trim().isEmpty
                    ? null
                    : heureController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Cellule créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteFamille(Famille famille) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer la famille « ${famille.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteFamille(famille.id);
      if (mounted) showSuccess(context, 'Famille supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deleteCellule(Cellule cellule) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la cellule « ${cellule.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteCellule(cellule.id);
      if (mounted) showSuccess(context, 'Cellule supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// État vide élégant (maquette d'Axel) : cercle teinté, icône,
  /// titre et piste vers le bouton + du bas. La création se fait par
  /// le bouton flottant, toujours visible. Il est défilant : sur un
  /// petit écran, les textes ne se chevauchent pas.
  Widget _etatVide({
    required IconData icon,
    required String message,
    String? hint,
    // Maquette écran 4 : titre 14 px (familles), 13 px pour la ligne
    // vide des cellules (classe .emptyline).
    double titleSize = 14,
  }) {
    // Défilant : sur un petit écran, les textes ne se chevauchent pas.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.violetProfond.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: AppTheme.violetProfond,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.violetProfond,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.violetProfond.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _famillesTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<Famille>>(
            future: _famillesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoading();
              }
              if (snapshot.hasError) {
                return AppError(
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                );
              }
              final familles = snapshot.data!
                  .where((f) => _matches(f.nom))
                  .toList();
              // Vide brut (avant recherche) : une recherche sans
              // résultat ne masque pas la recherche.
              final famillesVides = snapshot.data!.isEmpty;
              if (famillesVides != _famillesVides) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _famillesVides != famillesVides) {
                    setState(() => _famillesVides = famillesVides);
                  }
                });
              }
              if (familles.isEmpty) {
                return _etatVide(
                  icon: Icons.family_restroom_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune famille'
                      : 'Aucune famille ne correspond à la recherche.',
                  // Maquette écran 4 : la piste vers le bouton
                  // + Famille, seulement quand il est affiché.
                  hint: snapshot.data!.isEmpty && !widget.masquerCreation
                      ? 'Créez votre première famille avec le bouton + Famille'
                      : null,
                );
              }
              return ListeAvecFab(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: familles.length,
                    itemBuilder: (context, index) {
                      final famille = familles[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.family_restroom_outlined),
                        ),
                        title: Text(famille.nom),
                        subtitle: Text(
                          '${famille.chefFamilleId != null ? 'Chef : ${noms[famille.chefFamilleId] ?? '—'}' : 'Sans chef désigné'}'
                          '${famille.telephone != null ? ' · ${famille.telephone}' : ''}'
                          '${famille.adresse != null ? ' · ${famille.adresse}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteFamille(famille),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cellulesTab(List<Member> membres) {
    final noms = {for (final m in membres) m.id: m.fullName};
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<Cellule>>(
            future: _cellulesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoading();
              }
              if (snapshot.hasError) {
                return AppError(
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                );
              }
              final items = snapshot.data!
                  .where((c) => _matches(c.nom))
                  .toList();
              // Vide brut (avant recherche) : une recherche sans
              // résultat ne masque pas la recherche.
              final cellulesVides = snapshot.data!.isEmpty;
              if (cellulesVides != _cellulesVides) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _cellulesVides != cellulesVides) {
                    setState(() => _cellulesVides = cellulesVides);
                  }
                });
              }
              if (items.isEmpty) {
                return _etatVide(
                  icon: Icons.groups_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune cellule.'
                      : 'Aucune cellule ne correspond à la recherche.',
                  titleSize: 13,
                );
              }
              return ListeAvecFab(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final c = items[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.groups_outlined),
                        ),
                        title: Text(c.nom),
                        subtitle: Text(
                          '${c.quartier ?? '—'}'
                          '${c.responsableMemberId != null ? ' · ${noms[c.responsableMemberId] ?? '—'}' : ''}'
                          '${c.jourReunion != null ? ' · ${c.jourReunion}' : ''}'
                          '${c.heureReunion != null ? ' à ${c.heureReunion}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteCellule(c),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Onglet unique (écran Départements) : pas de barre d'onglets
    // propre ni de défilement entre Familles et Cellules.
    final unique = widget.ongletUnique;
    return DefaultTabController(
      length: 2,
      initialIndex: unique ?? 0,
      child: Scaffold(
        body: Column(
          children: [
            // Bandeau violet (maquette d'Axel) : onglets Familles /
            // Cellules avec indicateur or, puis recherche blanche
            // arrondie. Le titre, le logo et le menu sont déjà dans
            // l'en-tête clair de la coque.
            Container(
              color: AppTheme.violetProfond,
              child: Column(
                children: [
                  if (unique == null)
                    TabBar(
                      onTap: (i) => setState(() {
                        _tab = i;
                        _query = '';
                        _searchController.clear();
                      }),
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
                      ],
                    ),
                  // Recherche masquée quand l'onglet courant est vide.
                  if (!(_tab == 0 ? _famillesVides : _cellulesVides))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) =>
                              setState(() => _query = v.trim()),
                          style: const TextStyle(
                            color: AppTheme.violetProfond,
                          ),
                          decoration: InputDecoration(
                            hintText: _tab == 0
                                ? 'Rechercher une famille...'
                                : 'Rechercher une cellule...',
                            hintStyle: TextStyle(
                              color: AppTheme.violetProfond
                                  .withValues(alpha: 0.7),
                              fontSize: 16,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppTheme.violetProfond
                                  .withValues(alpha: 0.7),
                              size: 20,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<MemberPage>(
                future: _membresFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  if (snapshot.hasError) {
                    return AppError(
                      message: snapshot.error.toString(),
                      onRetry: _refreshAll,
                    );
                  }
                  final membres = snapshot.data!.membres;
                  return TabBarView(
                    physics: unique == null
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    children: [
                      _famillesTab(membres),
                      _cellulesTab(membres),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        // Bouton de création masqué dans l'écran Membres (maquette
        // écran 1) : la création se fait dans l'écran Départements.
        floatingActionButton: widget.masquerCreation
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    final membres = (await _membresFuture).membres;
                    if (!mounted) return;
                    if (_tab == 0) {
                      await _createFamille(membres);
                    } else {
                      await _createCellule(membres);
                    }
                  } catch (e) {
                    if (context.mounted) showApiError(context, e);
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(
                  _tab == 0 ? 'Famille' : 'Cellule',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
      ),
    );
  }
}
