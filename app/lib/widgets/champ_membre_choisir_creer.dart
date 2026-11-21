import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../utils/validation.dart';
import 'selecteur_recherche.dart';

/// Création d'un membre via l'API existante (même appel que le
/// formulaire membre) : nom, téléphone, e-mail. Renvoie le membre
/// créé (avec son id et son matricule serveur).
typedef CreerMembre = Future<Member> Function({
  required String fullName,
  String? phone,
  String? email,
});

/// Mini-formulaire intégré de création d'un membre, sans quitter le
/// formulaire en cours : nom, téléphone, e-mail. La personne créée
/// devient la sélection — aucune donnée inventée, la création reste
/// un acte explicite de l'utilisateur.
class _MiniFormulaireMembre extends StatefulWidget {
  const _MiniFormulaireMembre({
    required this.onCreer,
    required this.onCree,
    required this.onAnnuler,
  });

  final CreerMembre onCreer;
  final ValueChanged<Member> onCree;
  final VoidCallback onAnnuler;

  @override
  State<_MiniFormulaireMembre> createState() => _MiniFormulaireMembreState();
}

class _MiniFormulaireMembreState extends State<_MiniFormulaireMembre> {
  final _nomController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    final nom = _nomController.text.trim();
    if (nom.length < 2) {
      setState(
          () => _erreur = 'Entrez un nom complet (2 lettres au minimum).');
      return;
    }
    final erreurTelephone =
        validerTelephoneCI(_telephoneController.text.trim());
    if (erreurTelephone != null) {
      setState(() => _erreur = erreurTelephone);
      return;
    }
    final erreurEmail = validerEmailSimple(_emailController.text.trim());
    if (erreurEmail != null) {
      setState(() => _erreur = erreurEmail);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final membre = await widget.onCreer(
        fullName: nom,
        phone: _telephoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );
      if (mounted) widget.onCree(membre);
    } catch (e) {
      if (mounted) {
        setState(() => _erreur = 'Impossible de créer ce membre : $e');
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppTheme.fondPapier,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nouveau membre',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.violetProfond,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Ses données sont créées dans la base de l’église.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.texteSecondaire,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nomController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nom complet *',
                hintText: 'Ex. Koné Aminata',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telephoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Téléphone *',
                hintText: 'Ex. 07 07 07 07 07',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail (facultatif)',
                hintText: 'Ex. prenom.nom@mail.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(
                _erreur!,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.rougeErreur,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _enCours ? null : widget.onAnnuler,
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _enCours ? null : _creer,
                    child: _enCours
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Créer et sélectionner'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Champ « choisir dans la base ou créer » pour un membre désigné par
/// son id (responsable de famille ou de cellule, conducteur de culte,
/// membre visité ou accompagné, membre concerné d'une prière,
/// destinataire d'un message, membre d'une contribution).
///
/// (a) Choisir : le sélecteur avec recherche du § 2.1 sur la base
/// existante. (b) Créer : le mini-formulaire intégré ci-dessus ;
/// la personne créée devient la sélection. Effacer la sélection
/// remet le champ à vide (null).
class ChampMembreChoisirCreer extends StatefulWidget {
  const ChampMembreChoisirCreer({
    super.key,
    required this.membres,
    required this.valeur,
    required this.onChanged,
    required this.onCreerMembre,
    required this.label,
    this.aide,
    this.obligatoire = false,
    this.onMembreCree,
    this.placeholder = 'Choisir un membre…',
    this.texteVide =
        'Aucun membre pour l’instant — créez-en un ci-dessous.',
  });

  /// Membres de la base (la liste est relue à chaque reconstruction :
  /// un membre créé sur place y est ajouté par [onMembreCree]).
  final List<Member> membres;

  /// Id du membre sélectionné (null = aucune sélection).
  final String? valeur;

  final ValueChanged<String?> onChanged;

  /// Création sur place (même appel API que le formulaire membre).
  final CreerMembre onCreerMembre;

  /// Appelé avec le membre créé, pour l'ajouter à la liste du parent.
  final ValueChanged<Member>? onMembreCree;

  final String label;
  final String? aide;
  final bool obligatoire;
  final String placeholder;
  final String texteVide;

  @override
  State<ChampMembreChoisirCreer> createState() =>
      _ChampMembreChoisirCreerState();
}

class _ChampMembreChoisirCreerState extends State<ChampMembreChoisirCreer> {
  late String? _selectionId;
  bool _creationOuverte = false;

  /// Membres affichés : la liste du parent, plus ceux créés sur place
  /// ici — même si le parent oublie de les ajouter lui-même, la
  /// sélection reste affichable (le sélecteur cherche le libellé
  /// dans ses options).
  late List<Member> _membres;
  final List<Member> _crees = [];

  @override
  void initState() {
    super.initState();
    _selectionId = widget.valeur;
    _membres = List.of(widget.membres);
  }

  @override
  void didUpdateWidget(ChampMembreChoisirCreer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valeur != _selectionId) _selectionId = widget.valeur;
    // La liste du parent peut avoir grandi (membre créé ajouté par
    // onMembreCree) : on fusionne sans doublon avec les créés ici.
    final parId = {for (final m in widget.membres) m.id: m};
    for (final m in _crees) {
      parId.putIfAbsent(m.id, () => m);
    }
    _membres = parId.values.toList();
  }

  void _selectionner(String? id) {
    setState(() => _selectionId = id);
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelecteurRecherche<String>(
          options: [
            for (final m in _membres)
              OptionSelecteur(
                valeur: m.id,
                libelle: m.fullName,
                detail: m.matricule,
              ),
          ],
          valeur: _selectionId,
          onChanged: _selectionner,
          label: widget.label,
          aide: widget.aide,
          placeholder: widget.placeholder,
          obligatoire: widget.obligatoire,
          texteVide: widget.texteVide,
          texteRecherche: 'Rechercher un membre…',
        ),
        const SizedBox(height: 8),
        if (!_creationOuverte)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _creationOuverte = true),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text(
                'Créer un membre',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
          )
        else
          _MiniFormulaireMembre(
            onCreer: widget.onCreerMembre,
            onCree: (membre) {
              widget.onMembreCree?.call(membre);
              _crees.add(membre);
              setState(() {
                _membres = [..._membres, membre];
                _creationOuverte = false;
              });
              _selectionner(membre.id);
            },
            onAnnuler: () => setState(() => _creationOuverte = false),
          ),
      ],
    );
  }
}

/// Champ « choisir dans la base ou créer » pour un responsable désigné
/// par son nom libre (activité, événement spécial) : le nom reste un
/// texte libre — un responsable hors base ou historique se tape
/// toujours — mais on peut le remplir en choisissant un membre de la
/// base, ou en créant le membre sur place.
class ChampResponsableNomLibre extends StatefulWidget {
  const ChampResponsableNomLibre({
    super.key,
    required this.membres,
    required this.valeurInitiale,
    required this.onChanged,
    required this.onCreerMembre,
    required this.label,
    this.aide,
    this.obligatoire = false,
    this.onMembreCree,
  });

  final List<Member> membres;

  /// Nom déjà saisi (ex. à la modification d'une activité).
  final String? valeurInitiale;

  /// Nom choisi, créé ou tapé (null quand le champ est vidé).
  final ValueChanged<String?> onChanged;

  final CreerMembre onCreerMembre;
  final ValueChanged<Member>? onMembreCree;

  final String label;
  final String? aide;
  final bool obligatoire;

  @override
  State<ChampResponsableNomLibre> createState() =>
      _ChampResponsableNomLibreState();
}

class _ChampResponsableNomLibreState extends State<ChampResponsableNomLibre> {
  late final TextEditingController _nomController;
  bool _creationOuverte = false;

  /// Membres affichés par le sélecteur : liste du parent + créés ici
  /// (même motif que [ChampMembreChoisirCreer]).
  late List<Member> _membres;
  final List<Member> _crees = [];

  /// Clé du sélecteur : on le reconstruit après chaque choix, pour
  /// qu'il redevienne un simple outil de remplissage (il ne garde
  /// pas le membre choisi affiché : le nom est dans le champ).
  int _cleSelecteur = 0;

  @override
  void initState() {
    super.initState();
    _nomController =
        TextEditingController(text: widget.valeurInitiale ?? '');
    _membres = List.of(widget.membres);
  }

  @override
  void didUpdateWidget(ChampResponsableNomLibre oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parId = {for (final m in widget.membres) m.id: m};
    for (final m in _crees) {
      parId.putIfAbsent(m.id, () => m);
    }
    _membres = parId.values.toList();
  }

  @override
  void dispose() {
    _nomController.dispose();
    super.dispose();
  }

  void _remplir(String nom) {
    _nomController.text = nom;
    widget.onChanged(nom);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        etiquetteChamp(
          label: widget.label,
          aide: widget.aide,
          obligatoire: widget.obligatoire,
        ),
        TextField(
          controller: _nomController,
          onChanged: (v) =>
              widget.onChanged(v.trim().isEmpty ? null : v.trim()),
          decoration: const InputDecoration(
            hintText: 'Ex. Koné Aminata',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SelecteurRecherche<String>(
                key: ValueKey(_cleSelecteur),
                options: [
                  for (final m in _membres)
                    OptionSelecteur(
                      valeur: m.id,
                      libelle: m.fullName,
                      detail: m.matricule,
                    ),
                ],
                valeur: null,
                onChanged: (id) {
                  if (id == null) return;
                  final membre = _membres.firstWhere((m) => m.id == id);
                  _remplir(membre.fullName);
                  setState(() => _cleSelecteur++);
                },
                label: 'Choisir dans la base',
                placeholder: 'Rechercher un membre…',
                texteVide:
                    'Aucun membre pour l’instant — créez-en un ci-dessous.',
                texteRecherche: 'Rechercher un membre…',
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _creationOuverte
                  ? null
                  : () => setState(() => _creationOuverte = true),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Créer', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
        if (_creationOuverte) ...[
          const SizedBox(height: 8),
          _MiniFormulaireMembre(
            onCreer: widget.onCreerMembre,
            onCree: (membre) {
              widget.onMembreCree?.call(membre);
              _crees.add(membre);
              _remplir(membre.fullName);
              setState(() {
                _membres = [..._membres, membre];
                _creationOuverte = false;
              });
            },
            onAnnuler: () => setState(() => _creationOuverte = false),
          ),
        ],
      ],
    );
  }
}
