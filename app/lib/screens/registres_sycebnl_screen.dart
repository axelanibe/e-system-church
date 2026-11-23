import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/depot_sycebnl.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';

/// Écran « Registres SYCEBNL » (tranche dépôt SYCEBNL, migration 043) :
/// quatre onglets pour saisir et gérer les registres qui rendent les
/// états SYCEBNL complets : immobilisations, dettes, créances, notes
/// annexes. Écriture réservée à l'admin de l'église ; le trésorier
/// lit les registres.
class RegistresSycebnlScreen extends StatelessWidget {
  const RegistresSycebnlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registres SYCEBNL'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Immobilisations'),
              Tab(text: 'Dettes'),
              Tab(text: 'Créances'),
              Tab(text: 'Notes annexes'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OngletImmobilisations(),
            _OngletDettes(),
            _OngletCreances(),
            _OngletNotesAnnexes(),
          ],
        ),
      ),
    );
  }
}

int? _entier(String texte) {
  final v = int.tryParse(texte.trim().replaceAll(' ', ''));
  return v;
}

/// Dialogue « Nouvelle immobilisation » (ou modification) : libellé,
/// date d'acquisition, valeur d'acquisition, amortissement cumulé.
/// La valeur nette se calcule (valeur moins amortissement).
Future<void> _ouvrirImmobilisation(
  BuildContext context, {
  Immobilisation? immobilisation,
  VoidCallback? onEnregistre,
}) async {
  final api = context.read<AppState>().api;
  final libelleController =
      TextEditingController(text: immobilisation?.libelle ?? '');
  final dateController = TextEditingController(
    text: immobilisation?.dateAcquisition ?? '',
  );
  final valeurController = TextEditingController(
    text: immobilisation == null
        ? ''
        : immobilisation.valeurAcquisition.toString(),
  );
  final amortissementController = TextEditingController(
    text: immobilisation == null
        ? '0'
        : immobilisation.amortissementCumule.toString(),
  );
  await showCreateDialog(
    context: context,
    title: immobilisation == null
        ? 'Nouvelle immobilisation'
        : 'Modifier l’immobilisation',
    saveLabel:
        immobilisation == null ? 'Créer l’immobilisation' : 'Enregistrer',
    fields: [
      mentionChampsObligatoires,
      dialogTextField(
        controller: libelleController,
        label: 'Libellé *',
        aide: 'Ex. Temple, terrain, véhicule',
      ),
      dialogDateField(
        context: context,
        controller: dateController,
        label: 'Date d’acquisition *',
      ),
      dialogTextField(
        controller: valeurController,
        label: 'Valeur d’acquisition (FCFA) *',
        aide: 'Ex. 10000000',
        keyboardType: TextInputType.number,
      ),
      dialogTextField(
        controller: amortissementController,
        label: 'Amortissement cumulé (FCFA)',
        aide: '0 si le bien n’est pas amorti.',
        keyboardType: TextInputType.number,
      ),
    ],
    isValid: () {
      final valeur = _entier(valeurController.text);
      final amortissement = _entier(amortissementController.text) ?? 0;
      return libelleController.text.trim().length >= 2 &&
          dateController.text.trim().isNotEmpty &&
          valeur != null &&
          valeur > 0 &&
          amortissement >= 0 &&
          amortissement <= valeur;
    },
    messageInvalide:
        'Entrez un libellé (2 lettres au minimum), une date, une valeur positive, et un amortissement inférieur ou égal à la valeur.',
    onSave: () async {
      try {
        final valeur = _entier(valeurController.text)!;
        final amortissement = _entier(amortissementController.text) ?? 0;
        if (immobilisation == null) {
          await api.createImmobilisation(
            libelle: libelleController.text.trim(),
            dateAcquisition: dateController.text.trim(),
            valeurAcquisition: valeur,
            amortissementCumule: amortissement,
          );
          if (context.mounted) {
            showSuccess(context, 'Immobilisation créée.');
          }
        } else {
          await api.updateImmobilisation(
            immobilisation.id,
            libelle: libelleController.text.trim(),
            dateAcquisition: dateController.text.trim(),
            valeurAcquisition: valeur,
            amortissementCumule: amortissement,
          );
          if (context.mounted) {
            showSuccess(context, 'Immobilisation mise à jour.');
          }
        }
        onEnregistre?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}

class _OngletImmobilisations extends StatefulWidget {
  const _OngletImmobilisations();

  @override
  State<_OngletImmobilisations> createState() =>
      _OngletImmobilisationsState();
}

class _OngletImmobilisationsState extends State<_OngletImmobilisations> {
  late Future<List<Immobilisation>> _future;
  bool _listeVide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getImmobilisations();
    });
  }

  Future<void> _supprimer(Immobilisation immobilisation) async {
    final confirme = await confirmDelete(
      context,
      'Supprimer définitivement l’immobilisation « ${immobilisation.libelle} » ?',
    );
    if (!confirme || !mounted) return;
    try {
      await context.read<AppState>().api.deleteImmobilisation(
        immobilisation.id,
      );
      if (mounted) showSuccess(context, 'Immobilisation supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise =
        context.read<AppState>().devise;
    return Scaffold(
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  _ouvrirImmobilisation(context, onEnregistre: _refresh),
              icon: const Icon(Icons.add),
              label: const Text(
                'Nouvelle immobilisation',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
      body: ListeAvecFab(
        child: FutureBuilder<List<Immobilisation>>(
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
            final immobilisations = snapshot.data ?? [];
            if (immobilisations.isEmpty != _listeVide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _listeVide != immobilisations.isEmpty) {
                  setState(() => _listeVide = immobilisations.isEmpty);
                }
              });
            }
            if (immobilisations.isEmpty) {
              return EmptyState(
                icon: Icons.home_work_outlined,
                message: 'Aucune immobilisation enregistrée',
                actionLabel: 'Nouvelle immobilisation',
                onAction: () => _ouvrirImmobilisation(
                  context,
                  onEnregistre: _refresh,
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: immobilisations.length,
                itemBuilder: (context, index) {
                  final immo = immobilisations[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.home_work_outlined),
                      title: Text(
                        immo.libelle,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        [
                          immo.dateAffichee,
                          'Valeur nette : ${formatMontant(immo.valeurNette, devise)}',
                          'Amortissement : ${formatMontant(immo.amortissementCumule, devise)}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Modifier',
                            onPressed: () => _ouvrirImmobilisation(
                              context,
                              immobilisation: immo,
                              onEnregistre: _refresh,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(immo),
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

/// Dialogue « Nouvelle dette » (ou modification) : libellé, montant,
/// échéance facultative, statut en cours ou soldée.
Future<void> _ouvrirDette(
  BuildContext context, {
  Dette? dette,
  VoidCallback? onEnregistre,
}) async {
  final api = context.read<AppState>().api;
  final libelleController =
      TextEditingController(text: dette?.libelle ?? '');
  final montantController = TextEditingController(
    text: dette == null ? '' : dette.montant.toString(),
  );
  final echeanceController = TextEditingController(
    text: dette?.echeance ?? '',
  );
  String statut = dette?.statut ?? 'en_cours';
  await showCreateDialog(
    context: context,
    title: dette == null ? 'Nouvelle dette' : 'Modifier la dette',
    saveLabel: dette == null ? 'Créer la dette' : 'Enregistrer',
    fields: [
      mentionChampsObligatoires,
      dialogTextField(
        controller: libelleController,
        label: 'Libellé *',
        aide: 'Ex. Emprunt travaux, fournisseur',
      ),
      dialogTextField(
        controller: montantController,
        label: 'Montant (FCFA) *',
        aide: 'Ex. 500000',
        keyboardType: TextInputType.number,
      ),
      dialogDateField(
        context: context,
        controller: echeanceController,
        label: 'Échéance',
      ),
      dialogDropdown<String>(
        value: statut,
        label: 'Statut',
        options: const {'en_cours': 'En cours', 'soldee': 'Soldée'},
        onChanged: (v) => statut = v ?? 'en_cours',
      ),
    ],
    isValid: () {
      final montant = _entier(montantController.text);
      return libelleController.text.trim().length >= 2 &&
          montant != null &&
          montant > 0;
    },
    messageInvalide:
        'Entrez un libellé (2 lettres au minimum) et un montant positif.',
    onSave: () async {
      try {
        final montant = _entier(montantController.text)!;
        final echeance = echeanceController.text.trim();
        if (dette == null) {
          await api.createDette(
            libelle: libelleController.text.trim(),
            montant: montant,
            echeance: echeance.isEmpty ? null : echeance,
            statut: statut,
          );
          if (context.mounted) showSuccess(context, 'Dette créée.');
        } else {
          await api.updateDette(
            dette.id,
            libelle: libelleController.text.trim(),
            montant: montant,
            echeance: echeance.isEmpty ? null : echeance,
            statut: statut,
          );
          if (context.mounted) showSuccess(context, 'Dette mise à jour.');
        }
        onEnregistre?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}

class _OngletDettes extends StatefulWidget {
  const _OngletDettes();

  @override
  State<_OngletDettes> createState() => _OngletDettesState();
}

class _OngletDettesState extends State<_OngletDettes> {
  late Future<List<Dette>> _future;
  bool _listeVide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getDettes();
    });
  }

  Future<void> _supprimer(Dette dette) async {
    final confirme = await confirmDelete(
      context,
      'Supprimer définitivement la dette « ${dette.libelle} » ?',
    );
    if (!confirme || !mounted) return;
    try {
      await context.read<AppState>().api.deleteDette(dette.id);
      if (mounted) showSuccess(context, 'Dette supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise =
        context.read<AppState>().devise;
    return Scaffold(
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _ouvrirDette(context, onEnregistre: _refresh),
              icon: const Icon(Icons.add),
              label: const Text(
                'Nouvelle dette',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
      body: ListeAvecFab(
        child: FutureBuilder<List<Dette>>(
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
            final dettes = snapshot.data ?? [];
            if (dettes.isEmpty != _listeVide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _listeVide != dettes.isEmpty) {
                  setState(() => _listeVide = dettes.isEmpty);
                }
              });
            }
            if (dettes.isEmpty) {
              return EmptyState(
                icon: Icons.credit_card_outlined,
                message: 'Aucune dette enregistrée',
                actionLabel: 'Nouvelle dette',
                onAction: () =>
                    _ouvrirDette(context, onEnregistre: _refresh),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: dettes.length,
                itemBuilder: (context, index) {
                  final dette = dettes[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.credit_card_outlined),
                      title: Text(
                        dette.libelle,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        [
                          formatMontant(dette.montant, devise),
                          dette.echeanceAffichee,
                          dette.statutLibelle,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Modifier',
                            onPressed: () => _ouvrirDette(
                              context,
                              dette: dette,
                              onEnregistre: _refresh,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(dette),
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

/// Dialogue « Nouvelle créance » (ou modification) : libellé, montant,
/// échéance facultative, statut en cours ou soldée.
Future<void> _ouvrirCreance(
  BuildContext context, {
  Creance? creance,
  VoidCallback? onEnregistre,
}) async {
  final api = context.read<AppState>().api;
  final libelleController =
      TextEditingController(text: creance?.libelle ?? '');
  final montantController = TextEditingController(
    text: creance == null ? '' : creance.montant.toString(),
  );
  final echeanceController = TextEditingController(
    text: creance?.echeance ?? '',
  );
  String statut = creance?.statut ?? 'en_cours';
  await showCreateDialog(
    context: context,
    title: creance == null ? 'Nouvelle créance' : 'Modifier la créance',
    saveLabel: creance == null ? 'Créer la créance' : 'Enregistrer',
    fields: [
      mentionChampsObligatoires,
      dialogTextField(
        controller: libelleController,
        label: 'Libellé *',
        aide: 'Ex. Loyer à recevoir, avance',
      ),
      dialogTextField(
        controller: montantController,
        label: 'Montant (FCFA) *',
        aide: 'Ex. 100000',
        keyboardType: TextInputType.number,
      ),
      dialogDateField(
        context: context,
        controller: echeanceController,
        label: 'Échéance',
      ),
      dialogDropdown<String>(
        value: statut,
        label: 'Statut',
        options: const {'en_cours': 'En cours', 'soldee': 'Soldée'},
        onChanged: (v) => statut = v ?? 'en_cours',
      ),
    ],
    isValid: () {
      final montant = _entier(montantController.text);
      return libelleController.text.trim().length >= 2 &&
          montant != null &&
          montant > 0;
    },
    messageInvalide:
        'Entrez un libellé (2 lettres au minimum) et un montant positif.',
    onSave: () async {
      try {
        final montant = _entier(montantController.text)!;
        final echeance = echeanceController.text.trim();
        if (creance == null) {
          await api.createCreance(
            libelle: libelleController.text.trim(),
            montant: montant,
            echeance: echeance.isEmpty ? null : echeance,
            statut: statut,
          );
          if (context.mounted) showSuccess(context, 'Créance créée.');
        } else {
          await api.updateCreance(
            creance.id,
            libelle: libelleController.text.trim(),
            montant: montant,
            echeance: echeance.isEmpty ? null : echeance,
            statut: statut,
          );
          if (context.mounted) {
            showSuccess(context, 'Créance mise à jour.');
          }
        }
        onEnregistre?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}

class _OngletCreances extends StatefulWidget {
  const _OngletCreances();

  @override
  State<_OngletCreances> createState() => _OngletCreancesState();
}

class _OngletCreancesState extends State<_OngletCreances> {
  late Future<List<Creance>> _future;
  bool _listeVide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getCreances();
    });
  }

  Future<void> _supprimer(Creance creance) async {
    final confirme = await confirmDelete(
      context,
      'Supprimer définitivement la créance « ${creance.libelle} » ?',
    );
    if (!confirme || !mounted) return;
    try {
      await context.read<AppState>().api.deleteCreance(creance.id);
      if (mounted) showSuccess(context, 'Créance supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise =
        context.read<AppState>().devise;
    return Scaffold(
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  _ouvrirCreance(context, onEnregistre: _refresh),
              icon: const Icon(Icons.add),
              label: const Text(
                'Nouvelle créance',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
      body: ListeAvecFab(
        child: FutureBuilder<List<Creance>>(
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
            final creances = snapshot.data ?? [];
            if (creances.isEmpty != _listeVide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _listeVide != creances.isEmpty) {
                  setState(() => _listeVide = creances.isEmpty);
                }
              });
            }
            if (creances.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'Aucune créance enregistrée',
                actionLabel: 'Nouvelle créance',
                onAction: () =>
                    _ouvrirCreance(context, onEnregistre: _refresh),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: creances.length,
                itemBuilder: (context, index) {
                  final creance = creances[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        creance.libelle,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        [
                          formatMontant(creance.montant, devise),
                          creance.echeanceAffichee,
                          creance.statutLibelle,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Modifier',
                            onPressed: () => _ouvrirCreance(
                              context,
                              creance: creance,
                              onEnregistre: _refresh,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(creance),
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

/// Dialogue « Nouvelle note annexe » (ou modification) : titre,
/// contenu, exercice.
Future<void> _ouvrirNoteAnnexe(
  BuildContext context, {
  NoteAnnexe? note,
  VoidCallback? onEnregistre,
}) async {
  final api = context.read<AppState>().api;
  final titreController = TextEditingController(text: note?.titre ?? '');
  final contenuController =
      TextEditingController(text: note?.contenu ?? '');
  final exerciceController = TextEditingController(
    text: (note?.exercice ?? DateTime.now().year).toString(),
  );
  await showCreateDialog(
    context: context,
    title: note == null ? 'Nouvelle note annexe' : 'Modifier la note',
    saveLabel: note == null ? 'Créer la note' : 'Enregistrer',
    fields: [
      mentionChampsObligatoires,
      dialogTextField(
        controller: titreController,
        label: 'Titre *',
        aide: 'Ex. Méthode comptable',
      ),
      dialogTextField(
        controller: contenuController,
        label: 'Contenu *',
        aide: 'Ce que la note explique, en une phrase ou plus.',
        maxLines: 5,
      ),
      dialogTextField(
        controller: exerciceController,
        label: 'Exercice *',
        aide: 'Ex. ${DateTime.now().year}',
        keyboardType: TextInputType.number,
      ),
    ],
    isValid: () {
      final exercice = _entier(exerciceController.text);
      return titreController.text.trim().length >= 2 &&
          contenuController.text.trim().isNotEmpty &&
          exercice != null &&
          exercice >= 2000 &&
          exercice <= 2100;
    },
    messageInvalide:
        'Entrez un titre (2 lettres au minimum), un contenu et un exercice entre 2000 et 2100.',
    onSave: () async {
      try {
        final exercice = _entier(exerciceController.text)!;
        if (note == null) {
          await api.createNoteAnnexe(
            titre: titreController.text.trim(),
            contenu: contenuController.text.trim(),
            exercice: exercice,
          );
          if (context.mounted) showSuccess(context, 'Note créée.');
        } else {
          await api.updateNoteAnnexe(
            note.id,
            titre: titreController.text.trim(),
            contenu: contenuController.text.trim(),
            exercice: exercice,
          );
          if (context.mounted) showSuccess(context, 'Note mise à jour.');
        }
        onEnregistre?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}

class _OngletNotesAnnexes extends StatefulWidget {
  const _OngletNotesAnnexes();

  @override
  State<_OngletNotesAnnexes> createState() => _OngletNotesAnnexesState();
}

class _OngletNotesAnnexesState extends State<_OngletNotesAnnexes> {
  late Future<List<NoteAnnexe>> _future;
  bool _listeVide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.getNotesAnnexes();
    });
  }

  Future<void> _supprimer(NoteAnnexe note) async {
    final confirme = await confirmDelete(
      context,
      'Supprimer définitivement la note « ${note.titre} » ?',
    );
    if (!confirme || !mounted) return;
    try {
      await context.read<AppState>().api.deleteNoteAnnexe(note.id);
      if (mounted) showSuccess(context, 'Note supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _listeVide
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  _ouvrirNoteAnnexe(context, onEnregistre: _refresh),
              icon: const Icon(Icons.add),
              label: const Text(
                'Nouvelle note annexe',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
      body: ListeAvecFab(
        child: FutureBuilder<List<NoteAnnexe>>(
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
            final notes = snapshot.data ?? [];
            if (notes.isEmpty != _listeVide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _listeVide != notes.isEmpty) {
                  setState(() => _listeVide = notes.isEmpty);
                }
              });
            }
            if (notes.isEmpty) {
              return EmptyState(
                icon: Icons.note_alt_outlined,
                message: 'Aucune note annexe rédigée',
                actionLabel: 'Nouvelle note annexe',
                onAction: () =>
                    _ouvrirNoteAnnexe(context, onEnregistre: _refresh),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.note_alt_outlined),
                      title: Text(
                        note.titre,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        'Exercice ${note.exercice} · ${note.contenu}',
                        style: const TextStyle(fontSize: 11.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Modifier',
                            onPressed: () => _ouvrirNoteAnnexe(
                              context,
                              note: note,
                              onEnregistre: _refresh,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(note),
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
