import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/activites.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/champ_membre_choisir_creer.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';

/// Ouvre le dialogue « Nouvelle activité » (ou la modification d'une
/// activité existante quand [activite] est fournie) : titre, description,
/// date et heure, lieu, responsable (nom libre), statut brouillon ou
/// publié. La date et l'heure sont combinées comme pour le culte
/// (« AAAA-MM-JJ HH:mm »).
Future<void> ouvrirActivite(
  BuildContext context, {
  Activite? activite,
  VoidCallback? onEnregistre,
}) async {
  final api = context.read<AppState>().api;
  final titreController = TextEditingController(text: activite?.titre ?? '');
  final descriptionController =
      TextEditingController(text: activite?.description ?? '');
  final dateController = TextEditingController(
    text: activite?.date != null
        ? '${activite!.date!.year}-${activite.date!.month.toString().padLeft(2, '0')}-${activite.date!.day.toString().padLeft(2, '0')}'
        : '',
  );
  final heureController = TextEditingController(
    text: activite?.date != null
        ? '${activite!.date!.hour.toString().padLeft(2, '0')}:${activite.date!.minute.toString().padLeft(2, '0')}'
        : '',
  );
  final lieuController = TextEditingController(text: activite?.lieu ?? '');
  final responsableController =
      TextEditingController(text: activite?.responsable ?? '');
  String statut = activite?.statut ?? 'brouillon';
  String? opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }
  // Membres de la base, pour « choisir ou créer » le responsable
  // (Tranche Formulaires P0). Sans eux, le nom reste un texte libre.
  List<Member> membres = [];
  try {
    membres = (await api.getMembers(limit: 100)).membres;
  } catch (_) {
    // La liste est facultative : le nom libre suffit.
  }
  if (!context.mounted) return;
  Future<Member> creerMembre({
    required String fullName,
    String? phone,
    String? email,
  }) =>
      api.createMember(fullName: fullName, phone: phone, email: email);
  String? responsableNom = opt(responsableController);

  await showCreateDialog(
    context: context,
    title: activite == null ? 'Nouvelle activité' : 'Modifier l’activité',
    saveLabel: activite == null ? 'Créer l’activité' : 'Enregistrer',
    fields: [
      mentionChampsObligatoires,
      dialogTextField(
        controller: titreController,
        label: 'Titre *',
        aide: 'Ex. Veillée de prière',
      ),
      dialogTextField(
        controller: descriptionController,
        label: 'Description',
        aide: 'Ce que les membres doivent savoir.',
        maxLines: 3,
      ),
      dialogDateField(
        context: context,
        controller: dateController,
        label: 'Date *',
      ),
      dialogTimeField(controller: heureController, label: 'Heure *'),
      dialogTextField(
        controller: lieuController,
        label: 'Lieu',
        aide: 'Ex. Temple principal',
      ),
      ChampResponsableNomLibre(
        membres: membres,
        valeurInitiale: opt(responsableController),
        onChanged: (v) => responsableNom = v,
        onCreerMembre: creerMembre,
        onMembreCree: (m) => membres.add(m),
        label: 'Responsable',
        aide: 'Choisissez un membre de la base, créez-le s’il n’y est '
            'pas, ou tapez un nom.',
      ),
      dialogDropdown<String>(
        value: statut,
        label: 'Statut',
        options: const {'brouillon': 'Brouillon', 'publié': 'Publié'},
        onChanged: (v) => statut = v ?? 'brouillon',
      ),
    ],
    isValid: () =>
        titreController.text.trim().length >= 2 &&
        dateController.text.trim().isNotEmpty &&
        heureController.text.trim().isNotEmpty,
    messageInvalide:
        'Entrez un titre (2 lettres au minimum), une date et une heure.',
    onSave: () async {
      try {
        final dateHeure =
            '${dateController.text.trim()} ${heureController.text.trim()}';
        if (activite == null) {
          await api.createActivite(
            titre: titreController.text.trim(),
            description: opt(descriptionController),
            dateHeure: dateHeure,
            lieu: opt(lieuController),
            responsable: responsableNom,
            statut: statut,
          );
          if (context.mounted) {
            showSuccess(context, 'Activité créée.');
          }
        } else {
          await api.updateActivite(
            activite.id,
            titre: titreController.text.trim(),
            description: opt(descriptionController),
            dateHeure: dateHeure,
            lieu: opt(lieuController),
            responsable: responsableNom,
            statut: statut,
          );
          if (context.mounted) {
            showSuccess(context, 'Activité mise à jour.');
          }
        }
        onEnregistre?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}

/// Écran « Activités » (V1, migration 039) : liste des activités de
/// l'église, triées par date, avec pastille de statut ; créer,
/// modifier, publier et dépublier, supprimer. Les brouillons ne sont
/// visibles que côté admin, jamais côté fidèle.
class ActivitesScreen extends StatefulWidget {
  const ActivitesScreen({super.key});

  @override
  State<ActivitesScreen> createState() => _ActivitesScreenState();
}

class _ActivitesScreenState extends State<ActivitesScreen> {
  late Future<List<Activite>> _future;

  // La liste est-elle vide ? Sert à masquer le FAB quand l'état vide
  // affiche déjà le bouton de création (un seul bouton, pas deux).
  bool _listeVide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getActivites();
    });
  }

  Future<void> _basculerStatut(Activite activite) async {
    final publier = !activite.publiee;
    try {
      await context.read<AppState>().api.updateActivite(
            activite.id,
            statut: publier ? 'publié' : 'brouillon',
          );
      if (mounted) {
        showSuccess(
          context,
          publier ? 'Activité publiée.' : 'Activité repassée en brouillon.',
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimer(Activite activite) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement l’activité « ${activite.titre} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteActivite(activite.id);
      if (mounted) showSuccess(context, 'Activité supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activités')),
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  ouvrirActivite(context, onEnregistre: _refresh),
              icon: const Icon(Icons.add),
              label: const Text(
                'Nouvelle activité',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
      body: ListeAvecFab(
        child: FutureBuilder<List<Activite>>(
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
            final activites = [...(snapshot.data ?? [])]
              ..sort((a, b) {
                final da = a.date;
                final db = b.date;
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return da.compareTo(db);
              });
            if (activites.isEmpty != _listeVide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _listeVide != activites.isEmpty) {
                  setState(() => _listeVide = activites.isEmpty);
                }
              });
            }
            if (activites.isEmpty) {
              return EmptyState(
                icon: Icons.event_outlined,
                message: 'Aucune activité planifiée',
                actionLabel: 'Nouvelle activité',
                onAction: () =>
                    ouvrirActivite(context, onEnregistre: _refresh),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: activites.length,
                itemBuilder: (context, index) {
                  final activite = activites[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        activite.titre,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        [
                          formatDateTimeSansDecalage(activite.date),
                          if (activite.lieu != null) activite.lieu,
                          if (activite.responsable != null)
                            'Avec ${activite.responsable}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: activite.publiee
                                  ? AppTheme.or
                                  : AppTheme.bordure,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              activite.publiee ? 'Publié' : 'Brouillon',
                              style: TextStyle(
                                color: activite.publiee
                                    ? AppTheme.violetProfond
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              activite.publiee
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            tooltip:
                                activite.publiee ? 'Dépublier' : 'Publier',
                            onPressed: () => _basculerStatut(activite),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Modifier',
                            onPressed: () => ouvrirActivite(
                              context,
                              activite: activite,
                              onEnregistre: _refresh,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(activite),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
