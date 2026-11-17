import 'dart:async';
import '../config/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anniversaire.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/dialog_helpers.dart';
import 'cartes_membres_screen.dart';
import 'familles_screen.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'import_membres_screen.dart';
import 'visiteurs_screen.dart';

/// Membres de mon église, en 4 onglets (maquette, écran 1) : Liste,
/// Fiche, Familles, Anniversaires. L'onglet Fréquentation a été
/// retiré (décision d'Axel) : les présences restent suivies depuis
/// l'écran Présences (pointage de culte) et la fiche de chaque
/// membre garde sa carte Fréquentation.
/// Le trésorier ne peut pas créer de membre.
class MembresScreen extends StatefulWidget {
  const MembresScreen({super.key});

  @override
  State<MembresScreen> createState() => _MembresScreenState();
}

class _MembresScreenState extends State<MembresScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  /// Recherche tapée, appliquée tout de suite sur la page déjà chargée :
  /// l'API pagine à 50, le filtre local ne remplace donc pas l'appel
  /// serveur, il donne seulement un retour immédiat en attendant.
  String _filtreLocal = '';
  /// Pastille active : 'tous', 'anciens' ou 'nouveaux' (maquette,
  /// écran 1). Seule « Nouveaux » a un filtre serveur
  /// ('nouveau_converti') ; « Anciens » filtre côté client, sur la
  /// page déjà chargée, avec la même réserve de pagination à 50 que
  /// la recherche locale.
  String _pastille = 'tous';
  late Future<MemberPage> _future;
  late Future<List<Anniversaire>> _anniversairesFuture;
  late Future<MemberPage> _membresFicheFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      final i = _tabController.index;
      if (i != _tabIndex) setState(() => _tabIndex = i);
    });
    final api = context.read<AppState>().api;
    _future = _load();
    _anniversairesFuture = api.getAnniversaires(jours: 30);
    _membresFicheFuture = api.getMembers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<MemberPage> _load() {
    return context.read<AppState>().api.getMembers(
          q: _query.isEmpty ? null : _query,
          status: _pastille == 'nouveaux' ? 'nouveau_converti' : null,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _refreshAnniversaires() {
    setState(() => _anniversairesFuture =
        context.read<AppState>().api.getAnniversaires(jours: 30));
  }

  Future<void> _deleteMember(Member member) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le membre « ${member.fullName} » (${member.matricule}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteMember(member.id);
      if (mounted) showSuccess(context, 'Membre supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  void _onSearchChanged(String value) {
    // Retour immédiat : on filtre d'abord la page déjà chargée, puis
    // l'appel serveur (temporisé) apporte les résultats complets.
    setState(() => _filtreLocal = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = value.trim();
        _future = _load();
      });
    });
  }

  bool _correspondRecherche(Member m) {
    final q = _filtreLocal.toLowerCase();
    if (q.isEmpty) return true;
    return m.fullName.toLowerCase().contains(q) ||
        m.matricule.toLowerCase().contains(q);
  }

  bool _correspondPastille(Member m) {
    switch (_pastille) {
      case 'anciens':
        // « Anciens » (maquette, écran 1) : membres établis, ni
        // nouveaux convertis ni sympathisants.
        return m.status != 'nouveau_converti' &&
            m.statutRiche != 'sympathisant';
      default:
        return true;
    }
  }

  Future<void> _openForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MemberFormScreen()),
    );
    if (created == true && mounted) {
      showSuccess(context, 'Membre ajouté.');
      _refresh();
    }
  }

  Future<void> _openImport() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportMembresScreen()),
    );
    if (changed == true && mounted) {
      showSuccess(context, 'Import terminé.');
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return AppTheme.vertFonce;
      case 'nouveau_converti':
        return AppTheme.orAttention;
      case 'inactif':
        return Colors.grey;
      case 'ancien':
        return AppTheme.orFonce;
      default:
        return Colors.grey;
    }
  }

  /// Initiales du membre (2 lettres, maquette) : première lettre du
  /// prénom et du nom, ou 2 premières lettres si un seul mot.
  String _initiales(String nomComplet) {
    final parties = nomComplet
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parties.isEmpty) return '?';
    if (parties.length == 1) {
      final mot = parties.first;
      return mot.length >= 2
          ? mot.substring(0, 2).toUpperCase()
          : mot.toUpperCase();
    }
    return (parties.first[0] + parties.last[0]).toUpperCase();
  }

  /// Fonction à afficher dans la ligne, seulement si le membre en a
  /// une (« Aucun » veut dire sans fonction précise).
  String? _fonctionTexte(Member member) {
    final f = member.fonction?.trim() ?? '';
    if (f.isEmpty || f == 'Aucun') return null;
    return f;
  }

  /// État vide de l'onglet Liste (maquette écran 1) : quand aucun
  /// membre n'est enregistré du tout, titre, sous-texte et bouton
  /// « Créer un membre » (même formulaire que le FAB). Avec un
  /// filtre ou une recherche actifs, simple message d'absence de
  /// résultat.
  Widget _etatVideListe({
    required AppState state,
    required bool vraimentVide,
  }) {
    if (!vraimentVide) {
      return EmptyState(
        icon: Icons.people_outline,
        message: _filtreLocal.isNotEmpty || _query.isNotEmpty
            ? 'Aucun membre ne correspond à « ${_filtreLocal.isNotEmpty ? _filtreLocal : _query} ».'
            : 'Aucun membre enregistré',
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline,
                size: 26,
                color: AppTheme.violetProfond,
              ),
              const SizedBox(height: 8),
              const Text(
                'Aucun membre enregistré',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.violetProfond,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'La liste se remplira dès la première inscription.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.violetProfond.withValues(alpha: 0.7),
                ),
              ),
              if (state.canManageMembers) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _openForm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.or,
                    foregroundColor: AppTheme.violetProfond,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Créer un membre',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Onglet Liste : le contenu actuel (recherche, boutons, pastilles,
  /// liste, FAB). La carte anniversaires a déménagé dans l'onglet
  /// Anniversaires.
  Widget _listeTab(AppState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          // Recherche + menu « ⋯ » (maquette) : Importer, Cartes et
          // Visiteurs sont groupés dans le menu, un seul bouton
          // icône à côté du champ. Le bouton ESC est déjà dans
          // l'en-tête clair de la coque.
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher un membre par nom ou matricule',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (state.isAdmin || state.canManageMembers) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Plus',
                  onSelected: (choix) {
                    if (choix == 'importer') {
                      _openImport();
                    } else if (choix == 'cartes') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CartesMembresScreen(),
                        ),
                      );
                    } else if (choix == 'visiteurs') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const VisiteursScreen(),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    if (state.isAdmin) ...[
                      const PopupMenuItem(
                        value: 'importer',
                        child: Text('Importer'),
                      ),
                      const PopupMenuItem(
                        value: 'cartes',
                        child: Text('Cartes'),
                      ),
                    ],
                    if (state.canManageMembers)
                      const PopupMenuItem(
                        value: 'visiteurs',
                        child: Text('Visiteurs'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<MemberPage>(
            future: _future,
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
              final page = snapshot.data!;
              final membres = page.membres
                  .where(_correspondRecherche)
                  .where(_correspondPastille)
                  .toList();
              // Pastilles masquées tant que la liste est vide
              // (maquette) : aucun membre enregistré, aucune
              // recherche, aucune pastille active. Dès qu'un filtre
              // ou une recherche est actif, elles restent visibles
              // pour revenir en arrière.
              final montrerPastilles = page.total > 0 ||
                  _query.isNotEmpty ||
                  _filtreLocal.isNotEmpty ||
                  _pastille != 'tous';
              return Column(
                children: [
                  if (montrerPastilles)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      // Pastilles en défilement horizontal (maquette
                      // de refonte) : fini l'empilement de boutons,
                      // les pastilles défilent.
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final entry in <String, String>{
                              'Tous': 'tous',
                              'Anciens': 'anciens',
                              'Nouveaux': 'nouveaux',
                            }.entries) ...[
                              ChoiceChip(
                                label: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                selected: _pastille == entry.value,
                                onSelected: (_) {
                                  setState(() {
                                    _pastille = entry.value;
                                    _future = _load();
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: membres.isEmpty
                        ? _etatVideListe(
                            state: state,
                            vraimentVide: page.total == 0 &&
                                _query.isEmpty &&
                                _filtreLocal.isEmpty &&
                                _pastille == 'tous',
                          )
                        : ListeAvecFab(
                            child: RefreshIndicator(
                              onRefresh: () async => _refresh(),
                              child: ListView.builder(
                                itemCount: membres.length,
                                itemBuilder: (context, index) {
                                  final member = membres[index];
                                  final fonction =
                                      _fonctionTexte(member);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child:
                                          Text(_initiales(member.fullName)),
                                    ),
                                    title: Text(member.fullName),
                                    subtitle: Text(
                                        '${member.matricule}'
                                        '${fonction != null ? ' · $fonction' : ''}'
                                        ' · ${member.department ?? '—'}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StatusChip(
                                          label: member.statutAffiche,
                                          color: _statusColor(member.estAncien
                                              ? 'ancien'
                                              : member.status),
                                        ),
                                        if (state.canManageMembers)
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            tooltip: 'Supprimer',
                                            onPressed: () =>
                                                _deleteMember(member),
                                          ),
                                      ],
                                    ),
                                    onTap: () async {
                                      final changed = await Navigator.of(
                                              context)
                                          .push<bool>(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MemberDetailScreen(
                                                  member: member),
                                        ),
                                      );
                                      if (changed == true && mounted) {
                                        _refresh();
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Onglet Fiche : la liste déroulante « Fiche d'un membre »,
  /// déplacée depuis FamillesScreen, qui ouvre MemberDetailScreen.
  Widget _ficheTab() {
    return FutureBuilder<MemberPage>(
      future: _membresFicheFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: () => setState(() =>
                _membresFicheFuture = context.read<AppState>().api.getMembers()),
          );
        }
        final membres = snapshot.data!.membres;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Fiche d’un membre'),
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
            ],
          ),
        );
      },
    );
  }

  /// Onglet Anniversaires : la liste des anniversaires 30 jours
  /// (même Future, mêmes items que l'ancienne carte au-dessus de la
  /// liste), en plein onglet.
  Widget _anniversairesTab() {
    return FutureBuilder<List<Anniversaire>>(
      future: _anniversairesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: _refreshAnniversaires,
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.cake_outlined,
            message: 'Aucun anniversaire proche',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.cake_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Anniversaires proches (30 jours)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refreshAnniversaires(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final a = items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(a.fullName.isNotEmpty
                            ? a.fullName[0].toUpperCase()
                            : '?'),
                      ),
                      title: Text(a.fullName),
                      subtitle:
                          Text('${a.matricule} · ${a.ageAtteint} ans'),
                      trailing: Text(
                        a.joursRestants == 0
                            ? "Aujourd'hui"
                            : 'dans ${a.joursRestants} j',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        try {
                          final membre = await context
                              .read<AppState>()
                              .api
                              .getMember(a.id);
                          if (!context.mounted) return;
                          final changed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MemberDetailScreen(member: membre),
                            ),
                          );
                          if (changed == true && mounted) _refresh();
                        } catch (e) {
                          if (context.mounted) showApiError(context, e);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Column(
        children: [
          // Bandeau violet (même style que FamillesScreen) : 4 onglets,
          // indicateur or, défilant sur téléphone étroit. Le titre
          // « Membres » est déjà dans l'en-tête clair de la coque
          // (HomeScreen), on ne le duplique pas ici.
          Container(
            color: AppTheme.violetProfond,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.or,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12.5,
              ),
              tabs: const [
                Tab(text: 'Liste'),
                Tab(text: 'Fiche'),
                Tab(text: 'Familles'),
                Tab(text: 'Anniversaires'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _listeTab(state),
                _ficheTab(),
                // Familles sans boutons de création (maquette écran
                // 1) : la création se fait dans l'écran Départements.
                const FamillesScreen(masquerCreation: true),
                _anniversairesTab(),
              ],
            ),
          ),
        ],
      ),
      // Le FAB « Nouveau membre » ne s'affiche que sur l'onglet Liste :
      // l'onglet Familles n'a plus de bouton de création (maquette
      // écran 1, création dans l'écran Départements).
      floatingActionButton: _tabIndex == 0 && state.canManageMembers
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text(
                'Nouveau membre',
                style: TextStyle(fontSize: 13.5),
              ),
            )
          : null,
    );
  }
}
