import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ecole_biblique.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Champ vide -> null (comme dans les autres écrans de modules).
String? _opt(TextEditingController c) {
  final v = c.text.trim();
  return v.isEmpty ? null : v;
}

/// École biblique (tranche T9) : cours, leçons, inscriptions et suivi de
/// progression. Le contenu des cours et des leçons est créé par l'église
/// (admin / responsable de culte), jamais pré-rempli. Le membre s'inscrit
/// lui-même et marque ses leçons terminées ; le serveur pose le statut
/// « terminé » quand toutes les leçons sont terminées.
class EcoleBibliqueScreen extends StatefulWidget {
  const EcoleBibliqueScreen({super.key});

  @override
  State<EcoleBibliqueScreen> createState() => _EcoleBibliqueScreenState();
}

class _EcoleBibliqueScreenState extends State<EcoleBibliqueScreen> {
  late Future<List<CoursEcole>> _coursFuture;
  late Future<List<InscriptionEcole>> _inscriptionsFuture;

  @override
  void initState() {
    super.initState();
    _refreshFutures();
  }

  void _refreshFutures() {
    final api = context.read<AppState>().api;
    _coursFuture = api.getCoursEcole();
    _inscriptionsFuture = api.getInscriptionsEcole();
  }

  void _refresh() => setState(_refreshFutures);

  Future<void> _createCours() async {
    final titreController = TextEditingController();
    final descriptionController = TextEditingController();
    String? niveau;
    await showCreateDialog(
      context: context,
      title: 'Nouveau cours',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre du cours'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        DropdownButtonFormField<String>(
          initialValue: niveau,
          decoration: const InputDecoration(labelText: 'Niveau'),
          items: const [
            DropdownMenuItem(value: 'debutant', child: Text('Débutant')),
            DropdownMenuItem(
                value: 'intermediaire', child: Text('Intermédiaire')),
            DropdownMenuItem(value: 'avance', child: Text('Avancé')),
          ],
          onChanged: (v) => niveau = v,
        ),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCoursEcole(
                titre: titreController.text.trim(),
                description: _opt(descriptionController),
                niveau: niveau,
              );
          if (mounted) showSuccess(context, 'Cours créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteCours(CoursEcole cours) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le cours « ${cours.titre} » ? '
      'Un cours avec des leçons ou des inscriptions ne peut pas être supprimé.',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteCoursEcole(cours.id);
      if (mounted) showSuccess(context, 'Cours supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peutGerer = context.watch<AppState>().canManageMembers;
    return Scaffold(
      appBar: AppBar(title: const Text('École biblique')),
      floatingActionButton: peutGerer
          ? FloatingActionButton(
              onPressed: _createCours,
              tooltip: 'Nouveau cours',
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<List<CoursEcole>>(
        future: _coursFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: EmptyState(
                icon: Icons.error_outline,
                message: 'Impossible de charger les cours : ${snapshot.error}',
              ),
            );
          }
          final cours = snapshot.data ?? [];
          if (cours.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.school_outlined,
                message:
                    'Aucun cours pour l’instant. L’église crée ses cours ici.',
              ),
            );
          }
          return FutureBuilder<List<InscriptionEcole>>(
            future: _inscriptionsFuture,
            builder: (context, inscriptionsSnapshot) {
              final inscriptions = {
                for (final i in inscriptionsSnapshot.data ?? [])
                  i.coursId: i,
              };
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: cours.length,
                itemBuilder: (context, index) {
                  final c = cours[index];
                  final inscription = inscriptions[c.id];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(c.titre),
                      subtitle: Text(
                        [
                          c.niveauLabel,
                          if (c.description != null &&
                              c.description!.isNotEmpty)
                            c.description!,
                          if (!c.actif) 'Fermé aux inscriptions',
                        ].join(' — '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (inscription != null)
                            Chip(label: Text(inscription.statutLabel)),
                          if (peutGerer)
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Supprimer le cours',
                              onPressed: () => _deleteCours(c),
                            ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EcoleCoursDetailScreen(cours: c),
                          ),
                        );
                        _refresh();
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Détail d'un cours : leçons, inscription et progression.
/// L'admin et le responsable de culte gèrent les leçons ; le membre
/// s'inscrit, suit sa progression et marque ses leçons terminées.
class EcoleCoursDetailScreen extends StatefulWidget {
  final CoursEcole cours;

  const EcoleCoursDetailScreen({super.key, required this.cours});

  @override
  State<EcoleCoursDetailScreen> createState() =>
      _EcoleCoursDetailScreenState();
}

class _EcoleCoursDetailScreenState extends State<EcoleCoursDetailScreen> {
  late Future<List<LeconEcole>> _leconsFuture;
  late Future<List<InscriptionEcole>> _inscriptionsFuture;
  Future<ProgressionCours>? _progressionFuture;
  String? _progressionInscriptionId;
  late CoursEcole _cours;

  @override
  void initState() {
    super.initState();
    _cours = widget.cours;
    _refreshFutures();
  }

  void _refreshFutures() {
    final api = context.read<AppState>().api;
    _leconsFuture = api.getLeconsEcole(coursId: _cours.id);
    _inscriptionsFuture = api.getInscriptionsEcole(coursId: _cours.id);
  }

  void _refresh() {
    setState(() {
      _refreshFutures();
      _progressionFuture = null;
      _progressionInscriptionId = null;
    });
  }

  ApiService get _api => context.read<AppState>().api;

  Future<void> _createLecon(int ordreSuivant) async {
    final titreController = TextEditingController();
    final ordreController =
        TextEditingController(text: ordreSuivant.toString());
    final contenuController = TextEditingController();
    final referenceController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle leçon',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: titreController, label: 'Titre'),
        dialogTextField(
          controller: ordreController,
          label: 'Ordre dans le cours',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: contenuController, label: 'Contenu'),
        dialogTextField(
            controller: referenceController,
            label: 'Référence biblique (ex. Jean 3:16)'),
      ],
      isValid: () => titreController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await _api.createLeconEcole(
            coursId: _cours.id,
            ordre: int.tryParse(ordreController.text.trim()) ?? ordreSuivant,
            titre: titreController.text.trim(),
            contenu: _opt(contenuController),
            referenceBiblique: _opt(referenceController),
          );
          if (mounted) showSuccess(context, 'Leçon créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteLecon(LeconEcole lecon) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la leçon « ${lecon.titre} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await _api.deleteLeconEcole(lecon.id);
      if (mounted) showSuccess(context, 'Leçon supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _inscrire() async {
    try {
      await _api.inscrireEcole(coursId: _cours.id);
      if (mounted) showSuccess(context, 'Inscription au cours confirmée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _desinscrire(InscriptionEcole inscription) async {
    final confirmed = await confirmDelete(
      context,
      'Vous désinscrire du cours « ${_cours.titre} » ? Votre progression sera perdue.',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await _api.deleteInscriptionEcole(inscription.id);
      if (mounted) showSuccess(context, 'Désinscription confirmée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _terminerLecon(
      InscriptionEcole inscription, LeconEcole lecon) async {
    try {
      await _api.terminerLeconEcole(
          inscriptionId: inscription.id, leconId: lecon.id);
      if (mounted) showSuccess(context, 'Leçon marquée terminée.');
      setState(() {
        _progressionFuture = _api.getProgressionEcole(inscription.id);
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _basculerActif(bool actif) async {
    try {
      final maj = await _api.updateCoursEcole(_cours.id, actif: actif);
      setState(() => _cours = maj);
      if (mounted) {
        showSuccess(
            context, actif ? 'Cours ouvert aux inscriptions.' : 'Cours fermé.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peutGerer = context.watch<AppState>().canManageMembers;
    final estMembre = context.watch<AppState>().isMembre;
    return Scaffold(
      appBar: AppBar(title: Text(_cours.titre)),
      floatingActionButton: peutGerer
          ? FloatingActionButton(
              onPressed: () async {
                final lecons = await _leconsFuture;
                if (!mounted) return;
                await _createLecon(lecons.length + 1);
              },
              tooltip: 'Nouvelle leçon',
              child: const Icon(Icons.add),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cours.description != null && _cours.description!.isNotEmpty)
            Text(_cours.description!,
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(label: Text(_cours.niveauLabel)),
              const SizedBox(width: 8),
              if (peutGerer)
                Row(
                  children: [
                    const Text('Ouvert aux inscriptions'),
                    Switch(
                      value: _cours.actif,
                      onChanged: _basculerActif,
                    ),
                  ],
                )
              else if (!_cours.actif)
                const Chip(label: Text('Fermé aux inscriptions')),
            ],
          ),
          const SizedBox(height: 16),
          const SectionTitle(title: 'Leçons'),
          FutureBuilder<List<LeconEcole>>(
            future: _leconsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  message:
                      'Impossible de charger les leçons : ${snapshot.error}',
                );
              }
              final lecons = snapshot.data ?? [];
              if (lecons.isEmpty) {
                return const EmptyState(
                  icon: Icons.menu_book_outlined,
                  message: 'Aucune leçon dans ce cours pour l’instant.',
                );
              }
              return Column(
                children: lecons
                    .map((l) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${l.ordre}')),
                            title: Text(l.titre),
                            subtitle: Text(
                              [
                                if (l.referenceBiblique != null &&
                                    l.referenceBiblique!.isNotEmpty)
                                  l.referenceBiblique!,
                                if (l.contenu != null && l.contenu!.isNotEmpty)
                                  l.contenu!,
                              ].join(' — '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: peutGerer
                                ? IconButton(
                                    icon:
                                        const Icon(Icons.delete_outline),
                                    tooltip: 'Supprimer la leçon',
                                    onPressed: () => _deleteLecon(l),
                                  )
                                : null,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          if (estMembre) _sectionMembre(),
          if (peutGerer) _sectionGestion(),
        ],
      ),
    );
  }

  /// Inscription et progression du membre connecté.
  Widget _sectionMembre() {
    return FutureBuilder<List<InscriptionEcole>>(
      future: _inscriptionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: 'Impossible de charger votre inscription : ${snapshot.error}',
          );
        }
        final inscriptions = snapshot.data ?? [];
        if (inscriptions.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Votre inscription'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _cours.actif ? _inscrire : null,
                icon: const Icon(Icons.school_outlined),
                label: const Text('M’inscrire à ce cours'),
              ),
              if (!_cours.actif)
                const Text('Ce cours est fermé aux inscriptions.'),
            ],
          );
        }
        final inscription = inscriptions.first;
        // La progression est chargée une fois par inscription (pas à
        // chaque reconstruction) ; _refresh() réinitialise la garde.
        if (_progressionInscriptionId != inscription.id) {
          _progressionInscriptionId = inscription.id;
          _progressionFuture = _api.getProgressionEcole(inscription.id);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
                title: 'Votre progression — ${inscription.statutLabel}'),
            const SizedBox(height: 8),
            FutureBuilder<ProgressionCours>(
              future: _progressionFuture,
              builder: (context, progressionSnapshot) {
                if (progressionSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (progressionSnapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    message:
                        'Progression indisponible : ${progressionSnapshot.error}',
                  );
                }
                final progression = progressionSnapshot.data;
                if (progression == null) {
                  return const EmptyState(
                    icon: Icons.school_outlined,
                    message: 'Aucune leçon dans ce cours.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                        value: progression.total == 0
                            ? 0
                            : progression.terminees / progression.total),
                    const SizedBox(height: 4),
                    Text(
                      '${progression.terminees} / ${progression.total} leçon(s) — ${progression.pourcentage} %',
                    ),
                    const SizedBox(height: 8),
                    ...progression.lecons.map((l) => Card(
                          child: ListTile(
                            leading: Icon(
                              l.termine
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: l.termine
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(l.titre),
                            subtitle: l.referenceBiblique != null
                                ? Text(l.referenceBiblique!)
                                : null,
                            trailing: l.termine
                                ? const Chip(label: Text('Terminée'))
                                : FilledButton(
                                    onPressed: () async {
                                      final lecons = await _leconsFuture;
                                      final complete = lecons.firstWhere(
                                          (x) => x.id == l.id);
                                      await _terminerLecon(
                                          inscription, complete);
                                    },
                                    child: const Text('Terminer'),
                                  ),
                          ),
                        )),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _desinscrire(inscription),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Me désinscrire'),
            ),
          ],
        );
      },
    );
  }

  /// Vue gestion : nombre d'inscrits au cours.
  Widget _sectionGestion() {
    return FutureBuilder<List<InscriptionEcole>>(
      future: _inscriptionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final total = snapshot.data?.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle(title: 'Inscriptions'),
            const SizedBox(height: 8),
            Text('$total membre(s) inscrit(s) à ce cours.'),
          ],
        );
      },
    );
  }
}
