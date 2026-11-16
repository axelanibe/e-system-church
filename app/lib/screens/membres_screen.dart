import 'dart:async';
import '../config/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anniversaire.dart';
import '../models/cultes_direct.dart';
import '../models/member.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/dialog_helpers.dart';
import 'cartes_membres_screen.dart';
import 'familles_screen.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'import_membres_screen.dart';
import 'visiteurs_screen.dart';

/// Membres de mon église, en 5 onglets (projection) : Liste, Fiche,
/// Familles, Anniversaires, Fréquentation.
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
  /// Pastille active : 'tous', 'baptises', 'nouveaux' ou 'en_attente'
  /// (maquette, correction d'Axel du 15 nov. 2026).
  /// Seule « Nouveaux » a un filtre serveur ('nouveau_converti') ;
  /// « Baptisés » et « En attente » filtrent côté client, sur la page
  /// déjà chargée, avec la même réserve de pagination à 50 que la
  /// recherche locale.
  String _pastille = 'tous';
  /// Ids des membres baptisés (table `baptemes`, `GET /baptemes`) :
  /// la liste `GET /membres` ne renvoie pas `bapteme_date` (seul
  /// `GET /moi/carte` le fait), on ne peut donc pas filtrer sur
  /// `Member.baptemeDate` seul. Chargé paresseusement, à la première
  /// sélection de la pastille « Baptisés ».
  Set<String>? _idsBaptises;
  bool _baptemesEnCours = false;
  late Future<MemberPage> _future;
  late Future<List<Anniversaire>> _anniversairesFuture;
  late Future<MemberPage> _membresFicheFuture;
  late Future<PresenceStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      final i = _tabController.index;
      if (i != _tabIndex) setState(() => _tabIndex = i);
    });
    final api = context.read<AppState>().api;
    _future = _load();
    _anniversairesFuture = api.getAnniversaires(jours: 30);
    _membresFicheFuture = api.getMembers();
    _statsFuture = _loadStats();
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

  /// Statistiques de présence du mois en cours.
  Future<PresenceStats> _loadStats() {
    final maintenant = DateTime.now();
    final mois = maintenant.month.toString().padLeft(2, '0');
    final dernierJour =
        DateTime(maintenant.year, maintenant.month + 1, 0).day;
    return context.read<AppState>().api.getPresenceStats(
          from: '${maintenant.year}-$mois-01',
          to: '${maintenant.year}-$mois-${dernierJour.toString().padLeft(2, '0')}',
        );
  }

  /// Baptêmes de l'église, une seule fois : les ids servent au filtre
  /// « Baptisés ». En cas d'erreur, la pastille ne filtre rien et la
  /// liste reste affichée.
  Future<void> _chargerBaptemes() async {
    if (_idsBaptises != null || _baptemesEnCours) return;
    setState(() => _baptemesEnCours = true);
    try {
      final baptemes =
          await context.read<AppState>().api.getBaptemes();
      if (mounted) {
        setState(() {
          _idsBaptises = {for (final b in baptemes) b.memberId};
          _baptemesEnCours = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _idsBaptises = {};
          _baptemesEnCours = false;
        });
      }
    }
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _refreshAnniversaires() {
    setState(() => _anniversairesFuture =
        context.read<AppState>().api.getAnniversaires(jours: 30));
  }

  void _refreshStats() {
    setState(() => _statsFuture = _loadStats());
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
      case 'baptises':
        // Un baptême enregistré pour ce membre (`baptemes`), ou une
        // date de baptême déjà renvoyée sur sa fiche.
        return _idsBaptises?.contains(m.id) == true ||
            m.baptemeDate != null;
      case 'en_attente':
        // « En attente » : la personne ne s'est pas encore décidée
        // (définition d'Axel). Le statut réel le plus proche est
        // « sympathisant » : elle vient sans être membre.
        return m.statutRiche == 'sympathisant';
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
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Rechercher (nom ou matricule)',
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
              if (_pastille == 'baptises' && _baptemesEnCours) {
                return const AppLoading();
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
                              'Baptisés': 'baptises',
                              'Nouveaux': 'nouveaux',
                              'En attente': 'en_attente',
                            }.entries) ...[
                              ChoiceChip(
                                label: Text(entry.key),
                                selected: _pastille == entry.value,
                                onSelected: (_) {
                                  setState(() {
                                    _pastille = entry.value;
                                    _future = _load();
                                  });
                                  if (entry.value == 'baptises') {
                                    _chargerBaptemes();
                                  }
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
                        ? EmptyState(
                            icon: Icons.people_outline,
                            message: _filtreLocal.isNotEmpty ||
                                    _query.isNotEmpty
                                ? 'Aucun membre ne correspond à « ${_filtreLocal.isNotEmpty ? _filtreLocal : _query} ».'
                                : 'Aucun membre enregistré',
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

  /// Onglet Fréquentation : KPIs du mois en cours (projection) +
  /// historique depuis par_culte.
  Widget _frequentationTab() {
    return FutureBuilder<PresenceStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: _refreshStats,
          );
        }
        final stats = snapshot.data!;
        final taux = (stats.tauxPresence * 100).round();
        return RefreshIndicator(
          onRefresh: () async => _refreshStats(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _kpi(
                            'PRÉSENCES, CE MOIS', '${stats.presents}')),
                    const SizedBox(width: 12),
                    Expanded(child: _kpi('TAUX MOYEN', '$taux %')),
                  ],
                ),
                const SectionTitle(title: 'Historique de fréquentation'),
                if (stats.parCulte.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Aucune présence pointée',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'L’historique se construit à chaque pointage de culte.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        ...stats.parCulte.map((entree) {
                          final presents = presentsStat(entree);
                          final date = entree['date_heure'];
                          return ListTile(
                            dense: true,
                            title: Text(titreStatCulte(entree)),
                            subtitle: date == null
                                ? null
                                : Text(afficherDateTime(date)),
                            trailing: Text(
                              '$presents '
                              '${presents > 1 ? 'présents' : 'présent'}',
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kpi(String label, String valeur) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.violetProfond.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valeur,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.violetProfond,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Column(
        children: [
          // Bandeau violet (même style que FamillesScreen) : 5 onglets,
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
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Liste'),
                Tab(text: 'Fiche'),
                Tab(text: 'Familles'),
                Tab(text: 'Anniversaires'),
                Tab(text: 'Fréquentation'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _listeTab(state),
                _ficheTab(),
                const FamillesScreen(),
                _anniversairesTab(),
                _frequentationTab(),
              ],
            ),
          ),
        ],
      ),
      // Le FAB « Nouveau membre » ne s'affiche que sur l'onglet Liste :
      // l'onglet Familles apporte son propre FAB via FamillesScreen.
      floatingActionButton: _tabIndex == 0 && state.canManageMembers
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Nouveau membre'),
            )
          : null,
    );
  }
}
