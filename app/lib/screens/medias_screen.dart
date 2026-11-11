import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/medias.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 9 — Médias : prédications, plans de lecture et bibliothèque
/// (livres et prêts).
class MediasScreen extends StatefulWidget {
  const MediasScreen({super.key});

  @override
  State<MediasScreen> createState() => _MediasScreenState();
}

class _MediasScreenState extends State<MediasScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';

  late Future<List<Predication>> _predicationsFuture;
  late Future<List<PlanLecture>> _plansFuture;
  late Future<List<Livre>> _livresFuture;
  late Future<List<PretLivre>> _pretsFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _predicationsFuture = api.getPredications();
    _plansFuture = api.getPlansLecture();
    _livresFuture = api.getLivres();
    _pretsFuture = api.getPretsLivres();
    _membresFuture = api.getMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) _predicationsFuture = api.getPredications();
      if (_tab == 1) _plansFuture = api.getPlansLecture();
      if (_tab == 2) {
        _livresFuture = api.getLivres();
        _pretsFuture = api.getPretsLivres();
      }
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<List<Member>> _membres() async =>
      (await _membresFuture).membres;

  Future<void> _createPredication() async {
    final titreController = TextEditingController();
    final dateController = TextEditingController();
    final orateurController = TextEditingController();
    final serieController = TextEditingController();
    final urlAudioController = TextEditingController();
    final urlVideoController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle prédication',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogDateField(
            context: context,
            controller: dateController,
            label: 'Date de la prédication'),
        dialogTextField(controller: orateurController, label: 'Orateur'),
        dialogTextField(controller: serieController, label: 'Série'),
        dialogTextField(controller: urlAudioController, label: 'URL audio'),
        dialogTextField(controller: urlVideoController, label: 'URL vidéo'),
      ],
      isValid: () =>
          titreController.text.trim().isNotEmpty &&
          dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createPredication(
                titre: titreController.text.trim(),
                datePredication: dateController.text.trim(),
                orateur: _opt(orateurController),
                serie: _opt(serieController),
                urlAudio: _opt(urlAudioController),
                urlVideo: _opt(urlVideoController),
              );
          if (mounted) showSuccess(context, 'Prédication créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createPlan() async {
    final nomController = TextEditingController();
    final descriptionController = TextEditingController();
    final dureeController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau plan de lecture',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du plan'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogTextField(
          controller: dureeController,
          label: 'Durée en jours',
          keyboardType: TextInputType.number,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createPlanLecture(
                nom: nomController.text.trim(),
                description: _opt(descriptionController),
                dureeJours: int.tryParse(dureeController.text.trim()),
              );
          if (mounted) showSuccess(context, 'Plan de lecture créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createLivre() async {
    final titreController = TextEditingController();
    final auteurController = TextEditingController();
    final categorieController = TextEditingController();
    final exemplairesController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau livre',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(controller: auteurController, label: 'Auteur'),
        dialogTextField(controller: categorieController, label: 'Catégorie'),
        dialogTextField(
          controller: exemplairesController,
          label: 'Nombre d’exemplaires',
          keyboardType: TextInputType.number,
        ),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createLivre(
                titre: titreController.text.trim(),
                auteur: _opt(auteurController),
                categorie: _opt(categorieController),
                exemplaires:
                    int.tryParse(exemplairesController.text.trim()) ?? 1,
              );
          if (mounted) showSuccess(context, 'Livre ajouté à la bibliothèque.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createPret(
      List<Livre> livres, List<Member> membres) async {
    String? livreId = livres.isEmpty ? null : livres.first.id;
    String? memberId = membres.isEmpty ? null : membres.first.id;
    final dateController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau prêt',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: livreId,
          label: 'Livre',
          options: {for (final l in livres) l.id: l.titre},
          onChanged: (v) => livreId = v,
        ),
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDateField(
            context: context,
            controller: dateController,
            label: 'Date de retour prévue'),
      ],
      isValid: () => livreId != null && memberId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createPretLivre(
                livreId: livreId!,
                memberId: memberId!,
                dateRetourPrevue: dateController.text.trim().isEmpty
                    ? null
                    : dateController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Prêt enregistré.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _rendreLivre(PretLivre pret) async {
    try {
      await context.read<AppState>().api.rendreLivre(pret.id);
      if (mounted) showSuccess(context, 'Livre rendu.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _predicationsTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une prédication',
        ),
        Expanded(
          child: FutureBuilder<List<Predication>>(
            future: _predicationsFuture,
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
                  .where((p) => _matches(p.titre))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.mic_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune prédication pour l’instant.'
                      : 'Aucune prédication ne correspond à la recherche.',
                  actionLabel: 'Ajouter une prédication',
                  onAction: _createPredication,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final p = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.mic_outlined),
                      ),
                      title: Text(p.titre),
                      subtitle: Text(
                        '${afficherDate(p.datePredication)}'
                        '${p.orateur != null ? ' · ${p.orateur}' : ''}'
                        '${p.serie != null ? ' · Série ${p.serie}' : ''}',
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _plansTab() {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un plan de lecture',
        ),
        Expanded(
          child: FutureBuilder<List<PlanLecture>>(
            future: _plansFuture,
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
                  .where((p) => _matches(p.nom))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.menu_book_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun plan de lecture pour l’instant.'
                      : 'Aucun plan ne correspond à la recherche.',
                  actionLabel: 'Créer un plan de lecture',
                  onAction: _createPlan,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final p = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.menu_book_outlined),
                      ),
                      title: Text(p.nom),
                      subtitle: Text(
                        '${p.description ?? '—'}'
                        '${p.dureeJours != null ? ' · ${p.dureeJours} jours' : ''}',
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bibliothequeTab(Map<String, String> noms) {
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un livre ou un prêt',
        ),
        Expanded(
          child: FutureBuilder<List<Livre>>(
            future: _livresFuture,
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
              final livres = snapshot.data!
                  .where((l) => _matches(l.titre))
                  .toList();
              return FutureBuilder<List<PretLivre>>(
                future: _pretsFuture,
                builder: (context, pretSnapshot) {
                  if (pretSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  if (pretSnapshot.hasError) {
                    return AppError(
                      message: pretSnapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final prets = pretSnapshot.data!;
                  final livresTitres = {
                    for (final l in snapshot.data!) l.id: l.titre
                  };
                  if (livres.isEmpty && prets.isEmpty) {
                    return EmptyState(
                      icon: Icons.library_books_outlined,
                      message: 'Aucun livre dans la bibliothèque pour l’instant.',
                      actionLabel: 'Ajouter un livre',
                      onAction: _createLivre,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SectionTitle(title: 'Livres'),
                        if (livres.isEmpty)
                          const EmptyState(
                            icon: Icons.library_books_outlined,
                            message: 'Aucun livre pour l’instant.',
                          )
                        else
                          ...livres.map((l) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.book_outlined),
                                ),
                                title: Text(l.titre),
                                subtitle: Text(
                                  '${l.auteur ?? '—'}'
                                  '${l.categorie != null ? ' · ${l.categorie}' : ''}'
                                  ' · ${l.exemplaires} exemplaire(s)',
                                ),
                              )),
                        const SectionTitle(title: 'Prêts en cours'),
                        if (prets
                            .where((p) => p.statut == 'en_cours')
                            .isEmpty)
                          const EmptyState(
                            icon: Icons.outbox_outlined,
                            message: 'Aucun prêt en cours pour l’instant.',
                          )
                        else
                          ...prets
                              .where((p) => p.statut == 'en_cours')
                              .map((p) => ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.outbox_outlined),
                                    ),
                                    title: Text(livresTitres[p.livreId] ??
                                        p.livreId),
                                    subtitle: Text(
                                      '${noms[p.memberId] ?? p.memberId} · Retour prévu : ${afficherDate(p.dateRetourPrevue)}',
                                    ),
                                    trailing: TextButton(
                                      onPressed: () => _rendreLivre(p),
                                      child: const Text('Rendre'),
                                    ),
                                  )),
                        if (prets
                            .where((p) => p.statut != 'en_cours')
                            .isNotEmpty) ...[
                          const SectionTitle(title: 'Prêts terminés'),
                          ...prets
                              .where((p) => p.statut != 'en_cours')
                              .map((p) => ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.check_outlined),
                                    ),
                                    title: Text(livresTitres[p.livreId] ??
                                        p.livreId),
                                    subtitle: Text(
                                      '${noms[p.memberId] ?? p.memberId} · ${p.statut}',
                                    ),
                                  )),
                        ],
                        const SizedBox(height: 80),
                      ],
                    ),
                  );
                },
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Médias & bibliothèque'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Prédications'),
              Tab(text: 'Plans de lecture'),
              Tab(text: 'Bibliothèque'),
            ],
          ),
        ),
        body: FutureBuilder<MemberPage>(
          future: _membresFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {
                  _membresFuture =
                      context.read<AppState>().api.getMembers();
                }),
              );
            }
            final noms = {
              for (final m in snapshot.data!.membres) m.id: m.fullName
            };
            return TabBarView(
              children: [
                _predicationsTab(),
                _plansTab(),
                _bibliothequeTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                await _createPredication();
              } else if (_tab == 1) {
                await _createPlan();
              } else {
                // Deux créations possibles dans la bibliothèque : on
                // propose le choix.
                final choix = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Ajouter'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(ctx).pop('livre'),
                        child: const Text('Un livre'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(ctx).pop('pret'),
                        child: const Text('Un prêt'),
                      ),
                    ],
                  ),
                );
                if (choix == 'livre' && mounted) {
                  await _createLivre();
                } else if (choix == 'pret' && mounted) {
                  final livres = await _livresFuture;
                  final membres = await _membres();
                  if (mounted) await _createPret(livres, membres);
                }
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0
              ? 'Prédication'
              : _tab == 1
                  ? 'Plan'
                  : 'Livre / Prêt'),
        ),
      ),
    );
  }
}
