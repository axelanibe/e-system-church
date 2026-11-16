import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../models/pastoral.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'evenements_vie_screen.dart';
import 'rendez_vous_admin_screen.dart';

/// Module 6 — Suivi pastoral : radar des absences, parcours des
/// nouveaux convertis, visites pastorales et accompagnements (T6 :
/// radar, visites typées, rencontres datées, priorité, cas ouverts).
/// Les rendez-vous ont leur propre écran (« Rendez-vous » dans le
/// tiroir), une seule entrée par fonction.
class PastoralScreen extends StatefulWidget {
  const PastoralScreen({super.key});

  @override
  State<PastoralScreen> createState() => _PastoralScreenState();
}

const _etapes = {
  'accueil': 'Accueil',
  'formation': 'Formation',
  'bapteme': 'Baptême',
  'integration_cellule': 'Intégration en cellule',
  'integre': 'Intégré',
};

const _etapesOrdre = [
  'accueil',
  'formation',
  'bapteme',
  'integration_cellule',
  'integre',
];

const _priorites = {
  'basse': 'Basse',
  'normale': 'Normale',
  'haute': 'Haute',
  'urgente': 'Urgente',
};

const _typesVisite = {
  'domicile': 'Domicile',
  'hopital': 'Hôpital',
};

class _PastoralScreenState extends State<PastoralScreen> {
  // Une recherche propre à chaque section : l'ancien écran partageait
  // un seul champ entre les onglets, la recherche d'une section
  // filtrait les autres.
  final _rechercheParcoursController = TextEditingController();
  String _queryParcours = '';
  final _rechercheVisitesController = TextEditingController();
  String _queryVisites = '';
  final _rechercheAccompagnementsController = TextEditingController();
  String _queryAccompagnements = '';

  int _seuil = 3;
  String? _visiteType;
  bool _casOuverts = false;

  // La liste brute d'une section est-elle vide (avant recherche) ?
  // Sert à masquer recherche et filtres quand la liste est vide
  // (maquette, écrans 5 et 39 : pas de recherche sur une liste vide).
  // La création, elle, reste dans l'en-tête (« + Nouveau… », toujours
  // visible) : un seul point d'entrée par fonction, l'état vide
  // n'affiche pas de bouton de création.
  bool _parcoursVides = false;
  bool _visitesVides = false;
  bool _accompagnementsVides = false;

  late Future<List<AlerteRadar>> _radarFuture;
  late Future<List<ParcoursNouveau>> _parcoursFuture;
  late Future<List<VisitePastorale>> _visitesFuture;
  late Future<List<Accompagnement>> _accompagnementsFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _radarFuture = api.getRadarAbsences(seuil: _seuil);
    _parcoursFuture = api.getParcoursNouveaux();
    _visitesFuture = api.getVisitesPastorales();
    _accompagnementsFuture = api.getAccompagnements();
    _membresFuture = api.getMembers();
  }

  @override
  void dispose() {
    _rechercheParcoursController.dispose();
    _rechercheVisitesController.dispose();
    _rechercheAccompagnementsController.dispose();
    super.dispose();
  }

  // Les 4 sections sont visibles en même temps : le rafraîchissement
  // recharge les 4 listes, en gardant les filtres de chacune.
  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _radarFuture = api.getRadarAbsences(seuil: _seuil);
      _parcoursFuture = api.getParcoursNouveaux();
      _visitesFuture = api.getVisitesPastorales(type: _visiteType);
      _accompagnementsFuture =
          _casOuverts ? api.getCasOuverts() : api.getAccompagnements();
    });
  }

  bool _matches(String text, String query) =>
      query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<List<Member>> _membres() async =>
      (await _membresFuture).membres;

  Color _prioriteColor(String priorite) => priorite == 'urgente'
      ? AppTheme.rougeErreur
      : priorite == 'haute'
          ? Colors.orange
          : priorite == 'basse'
              ? Colors.grey
              : AppTheme.violetProfond;

  Widget _filtreChips({
    required List<String?> valeurs,
    required String? selection,
    required String Function(String?) label,
    required void Function(String?) onSelect,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: valeurs
            .map((v) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label(v), style: const TextStyle(fontSize: 12.5)),
                    selected: selection == v,
                    onSelected: (_) {
                      onSelect(v);
                      _refresh();
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  /// En-tête d'une section en ligne : même style que SectionTitle, avec
  /// un bouton de création à droite quand la section en a un. Le bouton
  /// flottant de l'ancien écran à onglets dépendait de l'onglet actif ;
  /// chaque section porte désormais sa création.
  Widget _enTeteSection(String titre,
      {VoidCallback? onAjouter, String? libelleAjouter}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titre.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1.2,
                  ),
            ),
          ),
          if (onAjouter != null)
            TextButton.icon(
              onPressed: onAjouter,
              icon: const Icon(Icons.add, size: 18),
              label: Text(libelleAjouter ?? 'Ajouter', style: const TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Future<void> _nouveau(int section) async {
    try {
      final membres = await _membres();
      if (!mounted) return;
      if (section == 1) {
        await _createParcours(membres);
      } else if (section == 2) {
        await _createVisite(membres);
      } else {
        await _createAccompagnement(membres);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _sectionRadar() {
    return Column(
      children: [
        _enTeteSection('Radar'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Les membres absents plusieurs cultes de suite remontent ici.',
                  // Maquette, écrans 5 et 39 : 12 px.
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              // Maquette, écrans 5 et 39 : libellé « Seuil d'absence »
              // devant le menu (défaut 16 px).
              const Text('Seuil d’absence', style: TextStyle(fontSize: 10.5)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _seuil,
                items: [
                  for (var s = 1; s <= 10; s++)
                    DropdownMenuItem(value: s, child: Text('$s cultes', style: const TextStyle(fontSize: 13.5))),
                ],
                onChanged: (s) {
                  if (s == null) return;
                  setState(() => _seuil = s);
                  _refresh();
                },
              ),
            ],
          ),
        ),
        FutureBuilder<List<AlerteRadar>>(
            future: _radarFuture,
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
              final items = snapshot.data!;
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.favorite_outline,
                  message: 'Aucune absence signalée',
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                  itemBuilder: (context, index) {
                    final a = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.favorite_outline),
                      ),
                      title: Text(a.membreNom, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        'Absent ${a.absencesConsecutives} cultes de suite\n'
                        '${a.alerte}'
                        '${a.visiteMotif != null ? '\n${a.visiteMotif}' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            final membres = await _membres();
                            if (mounted) {
                              await _createVisite(
                                membres,
                                memberIdPrefill: a.memberId,
                                motifPrefill: a.visiteMotif,
                                typePrefill: a.visiteType,
                              );
                            }
                          } catch (e) {
                            if (context.mounted) showApiError(context, e);
                          }
                        },
                        child: const Text('Visite', style: TextStyle(fontSize: 12.5)),
                      ),
                    );
                  },
                );
            },
          ),
      ],
    );
  }

  Future<void> _createParcours(List<Member> membres) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String etape = 'accueil';
    final noteController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouveau parcours',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Nouveau converti',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDropdown<String>(
          value: etape,
          label: 'Étape',
          options: _etapes,
          onChanged: (v) => etape = v ?? 'accueil',
        ),
        dialogTextField(controller: noteController, label: 'Note'),
      ],
      isValid: () => memberId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createParcoursNouveau(
                memberId: memberId!,
                etape: etape,
                note: _opt(noteController),
              );
          if (mounted) showSuccess(context, 'Parcours créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _avancerEtape(ParcoursNouveau parcours) async {
    final index = _etapesOrdre.indexOf(parcours.etape);
    final suivante = index >= 0 && index + 1 < _etapesOrdre.length
        ? _etapesOrdre[index + 1]
        : null;
    String etape = suivante ?? parcours.etape;
    await showCreateDialog(
      context: context,
      title: 'Avancement du parcours',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String>(
          value: etape,
          label: 'Étape',
          options: _etapes,
          onChanged: (v) => etape = v ?? parcours.etape,
        ),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          await context
              .read<AppState>()
              .api
              .setParcoursEtape(parcours.id, etape);
          if (mounted) showSuccess(context, 'Étape mise à jour.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createVisite(
    List<Member> membres, {
    String? memberIdPrefill,
    String? motifPrefill,
    String? typePrefill,
  }) async {
    String? memberId = memberIdPrefill ??
        (membres.isEmpty ? null : membres.first.id);
    String? type = typePrefill;
    String priorite = 'normale';
    final dateController = TextEditingController();
    final motifController = TextEditingController(text: motifPrefill ?? '');
    final lieuController = TextEditingController();
    final compteRenduController = TextEditingController();
    // Notes de suivi (maquette, écran 34) : réservées aux rôles
    // autorisés, elles ne s'affichent que pour eux.
    final notesController = TextEditingController();
    final peutVoirNotes =
        context.read<AppState>().canManageMembers;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle visite pastorale',
      saveLabel: 'Enregistrer la visite',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre visité',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDateField(
            context: context, controller: dateController, label: 'Date de la visite'),
        dialogDropdown<String?>(
          value: type,
          label: 'Type',
          options: const {
            null: 'Non précisé',
            'domicile': 'Domicile',
            'hopital': 'Hôpital',
          },
          onChanged: (v) => type = v,
        ),
        dialogTextField(controller: lieuController, label: 'Lieu'),
        dialogTextField(controller: motifController, label: 'Motif'),
        // Priorité (maquette, écran 34). L'API de création des
        // visites n'a pas encore de champ priorité ni notes de
        // suivi : les champs sont affichés, leur enregistrement
        // serveur demande une tranche serveur.
        dialogDropdown<String>(
          value: priorite,
          label: 'Priorité',
          options: _priorites,
          onChanged: (v) => priorite = v ?? 'normale',
        ),
        dialogTextField(
          controller: compteRenduController,
          label: 'Compte rendu',
          maxLines: 3,
        ),
        if (peutVoirNotes)
          dialogTextField(
            controller: notesController,
            label: 'Notes de suivi (facultatif)',
            maxLines: 3,
          ),
      ],
      isValid: () =>
          memberId != null && dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createVisitePastorale(
                memberId: memberId!,
                dateVisite: dateController.text.trim(),
                motif: motifController.text.trim(),
                compteRendu: _opt(compteRenduController),
                type: type,
                lieu: _opt(lieuController),
              );
          if (mounted) showSuccess(context, 'Visite enregistrée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createAccompagnement(List<Member> membres) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String type = 'autre';
    String priorite = 'normale';
    final descriptionController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvel accompagnement',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre accompagné',
          options: {
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
        dialogDropdown<String>(
          value: type,
          label: 'Type',
          options: const {
            'couple': 'Couple',
            'famille': 'Famille',
            'malade': 'Malade',
            'difficulte': 'En difficulté',
            'autre': 'Autre',
          },
          onChanged: (v) => type = v ?? 'autre',
        ),
        dialogDropdown<String>(
          value: priorite,
          label: 'Priorité',
          options: _priorites,
          onChanged: (v) => priorite = v ?? 'normale',
        ),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
      ],
      isValid: () => memberId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createAccompagnement(
                memberId: memberId!,
                type: type,
                description: descriptionController.text.trim(),
                priorite: priorite,
              );
          if (mounted) showSuccess(context, 'Accompagnement créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _showAccompagnement(
      Accompagnement a, Map<String, String> noms) async {
    String priorite = a.priorite;
    final dateController = TextEditingController();
    final noteController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(noms[a.memberId] ?? a.memberId),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.typeLabel} · ${a.description ?? '—'}'),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: priorite,
                  isExpanded: true,
                  items: _priorites.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13.5))))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null || v == priorite) return;
                    try {
                      await context
                          .read<AppState>()
                          .api
                          .setAccompagnementPriorite(a.id, v);
                      setDialogState(() => priorite = v);
                      if (mounted) {
                        showSuccess(context, 'Priorité mise à jour.');
                      }
                      _refresh();
                    } catch (e) {
                      if (mounted) showApiError(context, e);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text('Rencontres',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                FutureBuilder<List<RencontreAccompagnement>>(
                  future: context
                      .read<AppState>()
                      .api
                      .getRencontresAccompagnement(a.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: AppLoading(),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(snapshot.error.toString());
                    }
                    final rencontres = snapshot.data!;
                    if (rencontres.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucune rencontre.', style: TextStyle(fontSize: 13)),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rencontres
                          .map((r) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  '${afficherDate(r.dateRencontre)}'
                                  '${r.note != null ? ' · ${r.note}' : ''}',
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                dialogDateField(
                    context: dialogContext,
                    controller: dateController,
                    label: 'Date de la rencontre'),
                dialogTextField(
                    controller: noteController, label: 'Note'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (dateController.text.trim().isEmpty) return;
                try {
                  await context
                      .read<AppState>()
                      .api
                      .createRencontreAccompagnement(
                        accompagnementId: a.id,
                        dateRencontre: dateController.text.trim(),
                        note: _opt(noteController),
                      );
                  if (mounted) {
                    showSuccess(context, 'Rencontre enregistrée.');
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  _refresh();
                } catch (e) {
                  if (mounted) showApiError(context, e);
                }
              },
              child: const Text('Ajouter la rencontre', style: TextStyle(fontSize: 13.5)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionParcours(Map<String, String> noms) {
    return Column(
      children: [
        _enTeteSection(
          'Parcours',
          onAjouter: () => _nouveau(1),
          libelleAjouter: 'Nouveau parcours',
        ),
        if (!_parcoursVides)
          searchField(
            controller: _rechercheParcoursController,
            onChanged: (v) => setState(() => _queryParcours = v.trim()),
            label: 'Rechercher un parcours',
          ),
        FutureBuilder<List<ParcoursNouveau>>(
            future: _parcoursFuture,
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
                  .where((p) =>
                      _matches(noms[p.memberId] ?? p.memberId, _queryParcours))
                  .toList();
              // Vide brut (avant recherche) : une recherche sans
              // résultat ne masque pas la recherche.
              final videParcours = snapshot.data!.isEmpty;
              if (videParcours != _parcoursVides) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _parcoursVides != videParcours) {
                    setState(() => _parcoursVides = videParcours);
                  }
                });
              }
              if (items.isEmpty) {
                // Un seul point d'entrée : « + Nouveau parcours »
                // dans l'en-tête, toujours visible (maquette écran 5).
                return EmptyState(
                  icon: Icons.route_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun parcours.'
                      : 'Aucun parcours ne correspond à la recherche.',
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final p = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.route_outlined),
                      ),
                      title: Text(noms[p.memberId] ?? p.memberId, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        'Étape : ${_etapes[p.etape] ?? p.etape}'
                        '${p.note != null ? ' · ${p.note}' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: TextButton(
                        onPressed: () => _avancerEtape(p),
                        child: const Text('Avancer', style: TextStyle(fontSize: 12.5)),
                      ),
                    );
                  },
                );
            },
          ),
      ],
    );
  }

  Widget _sectionVisites(Map<String, String> noms) {
    return Column(
      children: [
        _enTeteSection(
          'Visites',
          onAjouter: () => _nouveau(2),
          libelleAjouter: 'Nouvelle visite',
        ),
        if (!_visitesVides)
          searchField(
            controller: _rechercheVisitesController,
            onChanged: (v) => setState(() => _queryVisites = v.trim()),
            label: 'Rechercher une visite',
          ),
        if (!_visitesVides)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _filtreChips(
              valeurs: const [null, 'domicile', 'hopital'],
              selection: _visiteType,
              label: (v) => v == null ? 'Toutes' : _typesVisite[v]!,
              onSelect: (v) => setState(() => _visiteType = v),
            ),
          ),
        FutureBuilder<List<VisitePastorale>>(
            future: _visitesFuture,
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
                  .where((v) =>
                      _matches(noms[v.memberId] ?? v.memberId, _queryVisites))
                  .toList();
              // Vide brut (avant recherche) : une recherche sans
              // résultat ne masque ni la recherche ni les filtres.
              final videVisites = snapshot.data!.isEmpty;
              if (videVisites != _visitesVides) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _visitesVides != videVisites) {
                    setState(() => _visitesVides = videVisites);
                  }
                });
              }
              if (items.isEmpty) {
                // Un seul point d'entrée : « + Nouvelle visite »
                // dans l'en-tête, toujours visible (maquette écran 5).
                return EmptyState(
                  icon: Icons.home_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune visite.'
                      : 'Aucune visite ne correspond à la recherche.',
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final v = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.home_outlined),
                      ),
                      title: Text(noms[v.memberId] ?? v.memberId, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        '${afficherDate(v.dateVisite)} · ${v.typeLabel}'
                        '${v.lieu != null ? ' · ${v.lieu}' : ''} · ${v.motif ?? '—'}'
                        '${v.compteRendu != null ? ' · ${v.compteRendu}' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: StatusChip(
                        label: v.statutLabel,
                        color: v.statut == 'realisee'
                            ? AppTheme.violetProfond
                            : v.statut == 'annulee'
                                ? AppTheme.rougeErreur
                                : Colors.orange,
                      ),
                    );
                  },
                );
            },
          ),
      ],
    );
  }

  Widget _sectionAccompagnements(Map<String, String> noms) {
    return Column(
      children: [
        _enTeteSection(
          'Accompagnements',
          onAjouter: () => _nouveau(3),
          libelleAjouter: 'Nouvel accompagnement',
        ),
        if (!_accompagnementsVides)
          searchField(
            controller: _rechercheAccompagnementsController,
            onChanged: (v) =>
                setState(() => _queryAccompagnements = v.trim()),
            label: 'Rechercher un accompagnement',
          ),
        if (!_accompagnementsVides)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _filtreChips(
              valeurs: const [null, 'ouverts'],
              selection: _casOuverts ? 'ouverts' : null,
              label: (v) => v == null ? 'Tous' : 'Cas ouverts',
              onSelect: (v) => setState(() => _casOuverts = v == 'ouverts'),
            ),
          ),
        FutureBuilder<List<Accompagnement>>(
            future: _accompagnementsFuture,
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
                  .where((a) => _matches(
                      noms[a.memberId] ?? a.memberId, _queryAccompagnements))
                  .toList();
              // Vide brut (avant recherche) : une recherche sans
              // résultat ne masque ni la recherche ni les filtres.
              final videAccompagnements = snapshot.data!.isEmpty;
              if (videAccompagnements != _accompagnementsVides) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      _accompagnementsVides != videAccompagnements) {
                    setState(() =>
                        _accompagnementsVides = videAccompagnements);
                  }
                });
              }
              if (items.isEmpty) {
                // Un seul point d'entrée : « + Nouvel accompagnement »
                // dans l'en-tête, toujours visible (maquette écran 5).
                return EmptyState(
                  icon: Icons.handshake_outlined,
                  message: snapshot.data!.isEmpty
                      ? (_casOuverts
                          ? 'Aucun cas ouvert.'
                          : 'Aucun accompagnement.')
                      : 'Aucun accompagnement ne correspond à la recherche.',
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final a = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.handshake_outlined),
                      ),
                      title: Text(noms[a.memberId] ?? a.memberId, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                          '${a.typeLabel} · ${a.description ?? '—'}',
                          style: const TextStyle(fontSize: 11.5)),
                      trailing: StatusChip(
                        label: a.prioriteLabel,
                        color: _prioriteColor(a.priorite),
                      ),
                      onTap: () => _showAccompagnement(a, noms),
                    );
                  },
                );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Projection : un seul écran à défiler, 4 sections en ligne
    // (Radar, Parcours, Visites, Accompagnements), pas d'onglets. E-R2.
    return Scaffold(
      // Maquette, écrans 5 et 39 : « Événements de vie » hors de
      // l'AppBar, lien texte violet en tête du contenu (même motif
      // que « Ouvrir les rendez-vous » en bas d'écran).
      appBar: AppBar(
        title: const Text('Suivi pastoral'),
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
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // Maquette, écrans 5 et 39 : « Événements de vie »
                  // hors de l'AppBar, lien texte violet en tête du
                  // contenu, un seul point d'entrée vers cet écran.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const EvenementsVieScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.violetProfond,
                          padding: EdgeInsets.zero,
                        ),
                        icon:
                            const Icon(Icons.cake_outlined, size: 18),
                        label: const Text(
                          'Événements de vie',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  _sectionRadar(),
                  _sectionParcours(noms),
                  _sectionVisites(noms),
                  _sectionAccompagnements(noms),
                  // Maquette, écran 39 : lien texte violet, pas un bouton.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const RendezVousAdminScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.violetProfond,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ouvrir les rendez-vous',
                              // Maquette, écran 39 : 13 px.
                              style: TextStyle(fontSize: 13),
                            ),
                            Icon(Icons.chevron_right, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
