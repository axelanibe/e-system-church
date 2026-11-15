import 'dart:async';
import '../config/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anniversaire.dart';
import '../models/cultes_direct.dart';
import '../models/membres_complement.dart';
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
  /// Pastille active : 'tous', 'anciens', 'nouveaux' ou 'familles'.
  /// Seule « Nouveaux » a un filtre serveur ('nouveau_converti') ;
  /// « Anciens » et « Familles » filtrent côté client, sur la page
  /// déjà chargée, avec la même réserve de pagination à 50 que la
  /// recherche locale.
  String _pastille = 'tous';
  late Future<MemberPage> _future;
  late Future<List<Anniversaire>> _anniversairesFuture;
  late Future<MemberPage> _membresFicheFuture;
  late Future<PresenceStats> _statsFuture;
  late Future<List<Famille>> _famillesFuture;
  late Future<List<LienParentEnfant>> _liensFuture;
  /// Ids des membres « en famille » : chef d'une famille, ou partie
  /// d'un lien parent/enfant validé.
  Set<String> _idsEnFamille = {};

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
    _famillesFuture = api.getFamilles();
    _liensFuture = api.getLiensParentEnfant();
    _chargerIdsEnFamille();
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

  Future<void> _chargerIdsEnFamille() async {
    try {
      final results = await Future.wait([_famillesFuture, _liensFuture]);
      final familles = results[0] as List<Famille>;
      final liens = results[1] as List<LienParentEnfant>;
      final ids = <String>{
        for (final f in familles)
          if (f.chefFamilleId != null) f.chefFamilleId!,
        for (final l in liens)
          if (l.statut == 'valide') ...[l.parentMemberId, l.enfantMemberId],
      };
      if (mounted) setState(() => _idsEnFamille = ids);
    } catch (_) {
      // Familles ou liens indisponibles : la pastille Familles ne
      // filtre rien, la liste reste affichée.
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
      case 'anciens':
        return m.estAncien;
      case 'familles':
        return _idsEnFamille.contains(m.id);
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
          // En largeur étroite, champ seul sur une ligne, boutons
          // sur la suivante : la rangée rigide écrasait le champ
          // entre « Importer », « Cartes » et « Visiteurs ».
          child: LayoutBuilder(
            builder: (context, constraints) {
              final field = TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Rechercher (nom ou matricule)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              );
              final actions = <Widget>[
                if (state.isAdmin) ...[
                  OutlinedButton.icon(
                    onPressed: _openImport,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Importer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CartesMembresScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Cartes'),
                  ),
                ],
                if (state.canManageMembers)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const VisiteursScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Visiteurs'),
                  ),
              ];
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: field),
                  for (final action in actions) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // Pastilles en défilement horizontal (maquette de refonte) :
          // fini l'empilement de boutons, les pastilles défilent.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in <String, String>{
                  'Tous': 'tous',
                  'Anciens': 'anciens',
                  'Nouveaux': 'nouveaux',
                  'Familles': 'familles',
                }.entries) ...[
                  ChoiceChip(
                    label: Text(entry.key),
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
              if (membres.isEmpty) {
                // E-M6 : un seul bouton de création quand la liste
                // est vide, le FAB ; l'état vide n'a pas d'action.
                return EmptyState(
                  icon: Icons.people_outline,
                  message: _filtreLocal.isNotEmpty || _query.isNotEmpty
                      ? 'Aucun membre ne correspond à « ${_filtreLocal.isNotEmpty ? _filtreLocal : _query} ».'
                      : 'Aucun membre enregistré',
                );
              }
              return ListeAvecFab(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    itemCount: membres.length,
                    itemBuilder: (context, index) {
                      final member = membres[index];
                      final fonction = _fonctionTexte(member);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_initiales(member.fullName)),
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
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Supprimer',
                                onPressed: () => _deleteMember(member),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MemberDetailScreen(member: member),
                            ),
                          );
                          if (changed == true && mounted) _refresh();
                        },
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
