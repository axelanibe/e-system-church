import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/validation.dart';

/// Formulaire d'ajout d'un membre (le matricule est généré par le serveur).
/// Si [member] est fourni, le formulaire pré-remplit ses champs et
/// enregistre une modification (statut compris).
class MemberFormScreen extends StatefulWidget {
  final Member? member;

  const MemberFormScreen({super.key, this.member});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  // Nom et prénom séparés (maquette écran 25) : le serveur ne stocke
  // qu'un seul `full_name`, recomposé « Prénom Nom » à l'envoi.
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _departmentController = TextEditingController();
  final _cellController = TextEditingController();
  String _status = 'actif';
  DateTime? _birthDate;
  /// Dates d'événements de vie (US7, migration 019) : NULL tant que non
  /// renseignées, jamais inventées.
  DateTime? _dateConversion;
  DateTime? _dateMariage;
  /// Sexe du membre ('M', 'F' ou null = non précisé) : il entre dans le
  /// matricule québécois (règle +50 au mois pour les femmes).
  String? _sexe;
  /// Photo choisie (maquette écran 25) : octets lus sur le web
  /// (FilePicker, `withData`), aperçu local. L'API de création ne
  /// prend pas de photo et le serveur n'a pas d'envoi binaire pour
  /// les membres : la photo n'est pas envoyée, elle attend une
  /// tranche serveur (voir rapport).
  Uint8List? _photoBytes;
  String? _photoName;
  // Catalogues de l'église (départements, fonctions, postes) : listes
  // déroulantes quand ils sont chargés, champ libre sinon (département).
  List<String>? _departements;
  List<String>? _fonctions;
  List<String>? _postes;
  String _fonction = 'Aucun';
  String? _poste;
  bool _loading = false;
  String? _error;
  /// Création guidée : 1 Identité, 2 Contacts, 3 Rattachement
  /// (maquette écran 25).
  int _etape = 0;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    if (member != null) {
      // Prénom = premier mot, nom = le reste (« Prénom Nom »).
      // Un seul mot va dans le nom, le prénom reste à compléter.
      final parties = member.fullName
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (parties.length >= 2) {
        _prenomController.text = parties.first;
        _nomController.text = parties.sublist(1).join(' ');
      } else if (parties.length == 1) {
        _nomController.text = parties.first;
      }
      _phoneController.text = member.phone ?? '';
      _emailController.text = member.email ?? '';
      _departmentController.text = member.department ?? '';
      _cellController.text = member.cellGroup ?? '';
      _status = member.status;
      _birthDate = member.birthDate == null
          ? null
          : DateTime.tryParse(member.birthDate!);
      _dateConversion = member.dateConversion == null
          ? null
          : DateTime.tryParse(member.dateConversion!);
      _dateMariage = member.dateMariage == null
          ? null
          : DateTime.tryParse(member.dateMariage!);
      _sexe = member.sexe;
      _fonction = member.fonction ?? 'Aucun';
      _poste = member.poste;
    }
    final api = context.read<AppState>().api;
    api.getDepartements().then((ds) {
      if (mounted) setState(() => _departements = ds.map((d) => d.nom).toList());
    }).catchError((_) {});
    api.getFonctions().then((fs) {
      if (mounted) setState(() => _fonctions = fs.map((f) => f.nom).toList());
    }).catchError((_) {});
    api.getPostes().then((ps) {
      if (mounted) setState(() => _postes = ps.map((p) => p.nom).toList());
    }).catchError((_) {});
  }

  Future<void> _choisirDateNaissance() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date de naissance',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  /// Photo à afficher dans l'aperçu : la photo choisie, sinon la
  /// photo existante du membre en modification, sinon rien.
  ImageProvider? get _photoAffichee {
    if (_photoBytes != null) return MemoryImage(_photoBytes!);
    final url = widget.member?.photoUrl;
    if (url != null) return NetworkImage(url);
    return null;
  }

  /// Choix de la photo (PNG/JPG, max 2 Mo), avec aperçu. Même motif
  /// que le logo à l'inscription : FilePicker, lecture des octets
  /// sur le web (`withData: true`).
  Future<void> _choisirPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      if (file.size > 2 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error = 'La photo doit peser 2 Mo au maximum.');
        }
        return;
      }
      if (file.bytes == null) {
        if (mounted) {
          setState(() => _error = 'Impossible de lire ce fichier.');
        }
        return;
      }
      setState(() {
        _photoBytes = file.bytes;
        _photoName = file.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Choix d'une date d'événement de vie (conversion ou mariage) : dans
  /// le passé seulement, effaçable.
  Future<void> _choisirDateEvenement(
      {required String aide,
      required DateTime? actuelle,
      required void Function(DateTime?) choisir}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: actuelle ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: aide,
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked != null) setState(() => choisir(picked));
  }

  /// Ligne de choix de date (naissance, conversion, mariage) : libellé,
  /// valeur affichée, effacement, ouverture du sélecteur au toucher.
  /// [aide] : aide concrète sous le libellé (Tranche Formulaires P0).
  Widget _ligneDate({
    required IconData icone,
    required String libelle,
    required DateTime? valeur,
    required VoidCallback onTap,
    required VoidCallback onEffacer,
    String? aide,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone),
      title: Text(
        valeur == null ? '$libelle (optionnel)' : '$libelle : ${formatDate(valeur)}',
      ),
      subtitle: aide == null
          ? null
          : Text(aide, style: const TextStyle(fontSize: 12.5)),
      trailing: valeur == null
          ? const Icon(Icons.calendar_today_outlined)
          : TextButton(
              onPressed: onEffacer,
              child: const Text('Effacer'),
            ),
      onTap: onTap,
    );
  }

  /// Récapitulatif avant envoi (Tranche Formulaires P0, étape 4) :
  /// tout ce qui sera enregistré, relu d'un coup d'œil — le matricule
  /// est calculé à partir du nom, du prénom, du sexe et de la date de
  /// naissance, d'où l'importance de les vérifier ici.
  Widget _recapitulatif() {
    final nomComplet =
        '${_prenomController.text.trim()} ${_nomController.text.trim()}'
            .trim();
    final lignes = <(String, String)>[
      ('Nom complet', nomComplet.isEmpty ? '—' : nomComplet),
      (
        'Téléphone',
        _phoneController.text.trim().isEmpty
            ? '—'
            : _phoneController.text.trim()
      ),
      (
        'E-mail',
        _emailController.text.trim().isEmpty
            ? '—'
            : _emailController.text.trim()
      ),
      (
        'Date de naissance',
        _birthDate == null ? '—' : formatDate(_birthDate!)
      ),
      (
        'Sexe',
        _sexe == 'F'
            ? 'Femme'
            : _sexe == 'M'
                ? 'Homme'
                : 'Non précisé'
      ),
      (
        'Département',
        _departmentController.text.trim().isEmpty
            ? '—'
            : _departmentController.text.trim()
      ),
      ('Fonction', _fonction),
      ('Poste', _poste ?? 'Aucun poste'),
      (
        'Cellule / groupe',
        _cellController.text.trim().isEmpty
            ? '—'
            : _cellController.text.trim()
      ),
      ('Statut', Member.labelForStatus(_status)),
      (
        'Date de conversion',
        _dateConversion == null ? '—' : formatDate(_dateConversion!)
      ),
      (
        'Date de mariage',
        _dateMariage == null ? '—' : formatDate(_dateMariage!)
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vérifiez avant de créer : le matricule est calculé à partir '
          'du nom, du prénom, du sexe et de la date de naissance.',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final (libelle, valeur) in lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    libelle,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    valeur,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Date au format « AAAA-MM-JJ » attendu par l'API.
  String? _iso(DateTime? d) {
    if (d == null) return null;
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _departmentController.dispose();
    _cellController.dispose();
    super.dispose();
  }

  /// Départements proposés : le catalogue, plus le département actuel du
  /// membre s'il n'y est plus (on ne perd pas la valeur enregistrée).
  List<String> get _departementChoix {
    final choix = List<String>.from(_departements ?? []);
    final actuel = _departmentController.text.trim();
    if (actuel.isNotEmpty && !choix.contains(actuel)) choix.add(actuel);
    return choix;
  }

  String? get _departementValeur {
    final actuel = _departmentController.text.trim();
    if (actuel.isEmpty) return null;
    return _departementChoix.contains(actuel) ? actuel : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Nom complet recomposé « Prénom Nom » pour le serveur.
    final fullName =
        '${_prenomController.text.trim()} ${_nomController.text.trim()}'
            .trim();
    try {
      if (_isEditing) {
        await context.read<AppState>().api.updateMember(
              widget.member!.id,
              fullName: fullName,
              phone: _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              email: _emailController.text.trim().isEmpty
                  ? null
                  : _emailController.text.trim(),
              birthDate: _iso(_birthDate),
              sexe: _sexe,
              department: _departmentController.text.trim().isEmpty
                  ? null
                  : _departmentController.text.trim(),
              fonction: _fonction == 'Aucun' ? null : _fonction,
              poste: _poste,
              cellGroup: _cellController.text.trim().isEmpty
                  ? null
                  : _cellController.text.trim(),
              status: _status,
              dateMariage: _iso(_dateMariage),
              dateConversion: _iso(_dateConversion),
            );
      } else {
        await context.read<AppState>().api.createMember(
              fullName: fullName,
              phone: _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              email: _emailController.text.trim().isEmpty
                  ? null
                  : _emailController.text.trim(),
              birthDate: _iso(_birthDate),
              sexe: _sexe,
              department: _departmentController.text.trim().isEmpty
                  ? null
                  : _departmentController.text.trim(),
              fonction: _fonction == 'Aucun' ? null : _fonction,
              poste: _poste,
              cellGroup: _cellController.text.trim().isEmpty
                  ? null
                  : _cellController.text.trim(),
              status: _status,
              dateMariage: _iso(_dateMariage),
              dateConversion: _iso(_dateConversion),
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Modifier le membre' : 'Nouveau membre')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tranche Formulaires P0 : mention des champs
                  // obligatoires + aides sous les libellés + messages
                  // d'erreur précis. Création guidée en quatre étapes
                  // (maquette écran 25, + récapitulatif).
                  const Text(
                    '(*) Champs obligatoires',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (!_isEditing) ...[
                    const Text(
                      'Création guidée en quatre étapes : identité, contacts, rattachement, récapitulatif.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Stepper(
                    currentStep: _etape,
                    onStepTapped: (i) => setState(() => _etape = i),
                    onStepContinue: () {
                      if (_etape == 0) {
                        // Étape Identité : nom et prénom requis.
                        if (_nomController.text.trim().length < 2 ||
                            _prenomController.text.trim().length < 2) {
                          setState(
                              () => _error = 'Nom et prénom requis.');
                          return;
                        }
                        setState(() {
                          _error = null;
                          _etape = 1;
                        });
                      } else if (_etape == 1) {
                        // Étape Contacts : téléphone obligatoire, 10 chiffres.
                        final erreurTelephone = validerTelephoneCI(
                            _phoneController.text.trim());
                        if (erreurTelephone != null) {
                          setState(() => _error = erreurTelephone);
                          return;
                        }
                        setState(() {
                          _error = null;
                          _etape = 2;
                        });
                      } else if (_etape == 2) {
                        // Étape Rattachement : on relit avant d'envoyer.
                        setState(() {
                          _error = null;
                          _etape = 3;
                        });
                      } else {
                        _submit();
                      }
                    },
                    onStepCancel: () {
                      if (_etape > 0) setState(() => _etape -= 1);
                    },
                    controlsBuilder: (context, details) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          children: [
                            FilledButton(
                              onPressed:
                                  _loading ? null : details.onStepContinue,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: _loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                      : Text(
                                          _etape == 3
                                              ? (_isEditing
                                                  ? 'Enregistrer les modifications'
                                                  : 'Créer le membre')
                                              : 'Suivant',
                                          style: const TextStyle(
                                              fontSize: 13.5),
                                        ),
                              ),
                            ),
                            if (_etape > 0) ...[
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed:
                                    _loading ? null : details.onStepCancel,
                                child: const Text(
                                  'Précédent',
                                  style: TextStyle(fontSize: 13.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(
                        title: const Text(
                          'Identité',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        isActive: _etape >= 0,
                        state: _etape > 0
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            TextFormField(
                              controller: _nomController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Nom *',
                                hintText: 'Nom de famille',
                                helperText:
                                    'Tel que sur la pièce d’identité.',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                      ? 'Entrez un nom de 2 lettres au minimum.'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _prenomController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Prénom *',
                                hintText: 'Prénom',
                                helperText:
                                    'Tel que sur la pièce d’identité.',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                      ? 'Entrez un prénom de 2 lettres au minimum.'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            // Ajouter une photo (maquette écran 25) :
                            // aperçu rond, photo existante en
                            // modification, photo choisie sinon.
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundImage: _photoAffichee,
                                  child: _photoAffichee == null
                                      ? const Icon(
                                          Icons.person_outline,
                                          size: 28,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _choisirPhoto,
                                        icon: const Icon(
                                            Icons.photo_camera_outlined),
                                        label: const Text(
                                          'Ajouter une photo',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      if (_photoBytes != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _photoName ??
                                              'Photo sélectionnée',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 16),
                                        ),
                                        const Text(
                                          'Photo sélectionnée : l’envoi au serveur n’est pas encore branché.',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        TextButton(
                                          onPressed: () => setState(() {
                                            _photoBytes = null;
                                            _photoName = null;
                                          }),
                                          child: const Text('Retirer'),
                                        ),
                                      ] else
                                        const Text(
                                          'PNG ou JPG, 2 Mo au maximum.',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _ligneDate(
                              icone: Icons.cake_outlined,
                              libelle: 'Date de naissance',
                              valeur: _birthDate,
                              onTap: _choisirDateNaissance,
                              onEffacer: () =>
                                  setState(() => _birthDate = null),
                              aide: 'Telle que sur la pièce d’identité — '
                                  'elle entre dans le matricule.',
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _sexe,
                              decoration: const InputDecoration(
                                labelText: 'Sexe (optionnel)',
                                hintText: 'Non précisé',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: null,
                                    child: Text('Non précisé')),
                                DropdownMenuItem(
                                    value: 'F', child: Text('Femme')),
                                DropdownMenuItem(
                                    value: 'M', child: Text('Homme')),
                              ],
                              onChanged: (v) => setState(() => _sexe = v),
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text(
                          'Contacts',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        isActive: _etape >= 1,
                        state: _etape > 1
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Téléphone *',
                                hintText: 'Numéro de téléphone',
                                helperText: '10 chiffres, ex. 07 07 07 07 07.',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => validerTelephoneCI(v),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-mail (facultatif)',
                                hintText: 'Adresse e-mail',
                                helperText: 'Ex. prenom.nom@mail.com',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => validerEmailSimple(v),
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text(
                          'Rattachement',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        isActive: _etape >= 2,
                        state: _etape > 2
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            if (_departements == null ||
                                    _departements!.isEmpty)
                              TextFormField(
                                controller: _departmentController,
                                decoration: const InputDecoration(
                                  labelText: 'Département',
                                  hintText:
                                      'Ex. Louange, Jeunesse, Protocole…',
                                  border: OutlineInputBorder(),
                                ),
                              )
                            else
                              DropdownButtonFormField<String>(
                                initialValue: _departementValeur,
                                decoration: const InputDecoration(
                                  labelText: 'Département',
                                  border: OutlineInputBorder(),
                                ),
                                items: _departementChoix
                                    .map((d) => DropdownMenuItem(
                                        value: d, child: Text(d)))
                                    .toList(),
                                onChanged: (v) => setState(() =>
                                    _departmentController.text = v ?? ''),
                              ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _fonction,
                              decoration: const InputDecoration(
                                labelText: 'Fonction',
                                border: OutlineInputBorder(),
                              ),
                              items: (_fonctions ?? fonctionsParDefaut)
                                  .map((f) => DropdownMenuItem(
                                      value: f, child: Text(f)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _fonction = v ?? 'Aucun'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String?>(
                              initialValue: _poste,
                              decoration: const InputDecoration(
                                labelText: 'Poste',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null,
                                    child: Text('Aucun poste')),
                                ...(_postes ?? postesParDefaut).map((p) =>
                                    DropdownMenuItem(
                                        value: p, child: Text(p))),
                              ],
                              onChanged: (v) => setState(() => _poste = v),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _cellController,
                              decoration: const InputDecoration(
                                labelText: 'Cellule / groupe',
                                hintText: 'Ex. Cellule de Yopougon',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _status,
                              decoration: const InputDecoration(
                                labelText: 'Statut',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'actif', child: Text('Actif')),
                                DropdownMenuItem(
                                    value: 'nouveau_converti',
                                    child: Text('Nouveau converti')),
                                DropdownMenuItem(
                                    value: 'inactif',
                                    child: Text('Inactif')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _status = v ?? 'actif'),
                            ),
                            const SizedBox(height: 12),
                            _ligneDate(
                              icone: Icons.favorite_outline,
                              libelle: 'Date de conversion',
                              valeur: _dateConversion,
                              onTap: () => _choisirDateEvenement(
                                aide: 'Date de conversion',
                                actuelle: _dateConversion,
                                choisir: (d) => _dateConversion = d,
                              ),
                              onEffacer: () =>
                                  setState(() => _dateConversion = null),
                              aide: 'Date de la conversion, si elle est connue.',
                            ),
                            _ligneDate(
                              icone: Icons.people_outline,
                              libelle: 'Date de mariage',
                              valeur: _dateMariage,
                              onTap: () => _choisirDateEvenement(
                                aide: 'Date de mariage',
                                actuelle: _dateMariage,
                                choisir: (d) => _dateMariage = d,
                              ),
                              onEffacer: () =>
                                  setState(() => _dateMariage = null),
                              aide: 'Date du mariage, si elle est connue.',
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text(
                          'Récapitulatif',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        isActive: _etape >= 3,
                        state: StepState.indexed,
                        content: _recapitulatif(),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
