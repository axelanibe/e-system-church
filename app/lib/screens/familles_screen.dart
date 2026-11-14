import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/dialog_helpers.dart';
import 'enfants_screen.dart';
import 'member_detail_screen.dart';

/// Module 1 — Familles et cellules de l'église.
/// La fiche complète d'un membre (statuts, baptême, liens) s'ouvre depuis
/// la section dédiée en bas de l'onglet Familles. Les départements se
/// gèrent en Paramètres ; les fonctions et les postes sont des options
/// dans les formulaires où on les attribue.
///
/// Mise en page (maquette d'Axel, 14 novembre 2026) : bandeau violet
/// avec les onglets Familles / Cellules (indicateur or) et la recherche
/// blanche arrondie, état vide élégant, bouton flottant étendu. Le
/// titre « Départements », le logo ESC et le bouton de menu sont déjà
/// dans l'en-tête clair de la coque (HomeScreen), on ne les duplique
/// pas ici : pas d'AppBar propre, pas de pastille logo, pas de barre
/// de navigation du bas (la coque les fournit déjà).
class FamillesScreen extends StatefulWidget {
  const FamillesScreen({super.key});

  @override
  State<FamillesScreen> createState() => _FamillesScreenState();
}

class _FamillesScreenState extends State<FamillesScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<Famille>> _famillesFuture;
  late Future<List<Cellule>> _cellulesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
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
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom de la famille'),
        dialogDropdown<String?>(
          value: chefId,
          label: 'Chef de famille',
          options: {
            null: 'Aucun',
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
      saveLabel: 'Créer',
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
  /// le bouton flottant, toujours visible.
  Widget _etatVide({
    required IconData icon,
    required String message,
    String? hint,
  }) {
    return Center(
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.violetProfond,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.violetProfond.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
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
              if (familles.isEmpty) {
                return _etatVide(
                  icon: Icons.family_restroom_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune famille pour l’instant'
                      : 'Aucune famille ne correspond à la recherche.',
                  hint: snapshot.data!.isEmpty
                      ? 'Appuyez sur le bouton + en bas pour en créer une.'
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
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Fiche d’un membre'),
              const Text(
                'Statuts, baptême, départements, cellules et liens parent-enfant.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Member>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Choisir un membre',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: membres
                    .map((m) => DropdownMenuItem<Member>(
                          value: m,
                          child: Text(
                            '${m.fullName} (${m.matricule})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (m) {
                  if (m == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberDetailScreen(member: m),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Enfants & jeunesse'),
              const Text(
                'Classes, autorisations et activités des enfants.',
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.child_care_outlined),
                  title: const Text('Enfants & jeunesse'),
                  subtitle: const Text(
                      'Classes, autorisations et activités.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EnfantsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
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
              if (items.isEmpty) {
                return _etatVide(
                  icon: Icons.groups_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune cellule pour l’instant'
                      : 'Aucune cellule ne correspond à la recherche.',
                  hint: snapshot.data!.isEmpty
                      ? 'Appuyez sur le bouton + en bas pour en créer une.'
                      : null,
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
    return DefaultTabController(
      length: 2,
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
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(text: 'Familles'),
                      Tab(text: 'Cellules'),
                    ],
                  ),
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
                          fontSize: 14,
                          color: AppTheme.violetProfond,
                        ),
                        decoration: InputDecoration(
                          hintText: _tab == 0
                              ? 'Rechercher une famille...'
                              : 'Rechercher une cellule...',
                          hintStyle: TextStyle(
                            color: AppTheme.violetProfond
                                .withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppTheme.violetProfond
                                .withValues(alpha: 0.7),
                            size: 20,
                          ),
                          border: InputBorder.none,
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
        floatingActionButton: FloatingActionButton.extended(
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
          label: Text(_tab == 0 ? 'Famille' : 'Cellule'),
        ),
      ),
    );
  }
}
