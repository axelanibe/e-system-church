import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/membres_complement.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

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
  final _nameController = TextEditingController();
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
  // Catalogues de l'église (départements, fonctions, postes) : listes
  // déroulantes quand ils sont chargés, champ libre sinon (département).
  List<String>? _departements;
  List<String>? _fonctions;
  List<String>? _postes;
  String _fonction = 'Aucun';
  String? _poste;
  bool _loading = false;
  String? _error;
  /// Création guidée : 1 Identité, 2 Coordonnées, 3 Église et parcours.
  int _etape = 0;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    if (member != null) {
      _nameController.text = member.fullName;
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
  Widget _ligneDate({
    required IconData icone,
    required String libelle,
    required DateTime? valeur,
    required VoidCallback onTap,
    required VoidCallback onEffacer,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone),
      title: Text(
        valeur == null ? '$libelle (optionnel)' : '$libelle : ${formatDate(valeur)}',
      ),
      trailing: valeur == null
          ? const Icon(Icons.calendar_today_outlined)
          : TextButton(
              onPressed: onEffacer,
              child: const Text('Effacer'),
            ),
      onTap: onTap,
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
    _nameController.dispose();
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
    try {
      if (_isEditing) {
        await context.read<AppState>().api.updateMember(
              widget.member!.id,
              fullName: _nameController.text.trim(),
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
              fullName: _nameController.text.trim(),
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
                  Stepper(
                    currentStep: _etape,
                    onStepTapped: (i) => setState(() => _etape = i),
                    onStepContinue: () {
                      if (_etape == 0) {
                        // Seule l'étape Identité bloque : le nom est requis.
                        if (_nameController.text.trim().length < 2) {
                          setState(() => _error = 'Nom requis.');
                          return;
                        }
                        setState(() {
                          _error = null;
                          _etape = 1;
                        });
                      } else if (_etape == 1) {
                        setState(() => _etape = 2);
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
                                    : Text(_etape == 2
                                        ? (_isEditing
                                            ? 'Enregistrer les modifications'
                                            : 'Ajouter le membre')
                                        : 'Suivant'),
                              ),
                            ),
                            if (_etape > 0) ...[
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed:
                                    _loading ? null : details.onStepCancel,
                                child: const Text('Précédent'),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(
                        title: const Text('Identité'),
                        isActive: _etape >= 0,
                        state: _etape > 0
                            ? StepState.complete
                            : StepState.indexed,
                        content: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Nom complet *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                      ? 'Nom requis.'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            _ligneDate(
                              icone: Icons.cake_outlined,
                              libelle: 'Date de naissance',
                              valeur: _birthDate,
                              onTap: _choisirDateNaissance,
                              onEffacer: () =>
                                  setState(() => _birthDate = null),
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
                        title: const Text('Coordonnées'),
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
                                labelText: 'Téléphone',
                                hintText: 'Ex. +225 07 00 00 00',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v != null &&
                                    v.trim().isNotEmpty &&
                                    !v.contains('@')) {
                                  return 'E-mail invalide.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      Step(
                        title: const Text('Église et parcours'),
                        isActive: _etape >= 2,
                        state: StepState.indexed,
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
                            ),
                          ],
                        ),
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
