import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/membres_complement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/code_input_formatter.dart';
import '../widgets/common_widgets.dart';

/// Inscription membre par code fidèle : « Je suis membre d'une église »
/// (nom et prénom, e-mail, téléphone, mot de passe, code fidèle de
/// l'église). Le code fait foi : aucune validation par l'administrateur,
/// le matricule est attribué automatiquement, la fiche membre et la carte
/// sont créées tout de suite, le compte est lié immédiatement et la
/// session démarre. Le code fidèle (ESC-F-…) désigne une seule église,
/// sans ambiguïté — le code de tutelle (ESC-…) ne sert qu'aux églises
/// qui se rattachent à une mère. L'ancien parcours par matricule n'est
/// plus proposé ici (il reste disponible côté serveur pour les membres
/// déjà fichés).
class RegisterFideleScreen extends StatefulWidget {
  const RegisterFideleScreen({super.key});

  @override
  State<RegisterFideleScreen> createState() => _RegisterFideleScreenState();
}

class _RegisterFideleScreenState extends State<RegisterFideleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomPrenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _departementController = TextEditingController();
  final _passwordController = TextEditingController();
  String _fonction = 'Aucun';
  /// Date de naissance et sexe (optionnels) : ils entrent dans le
  /// matricule québécois (initiales + JJMMAA + séquence, règle +50 au
  /// mois pour les femmes). Sans eux, le matricule est quand même
  /// attribué (segment 000000, mois tel quel).
  DateTime? _birthDate;
  String? _sexe;
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nomPrenomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _codeController.dispose();
    _departementController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  /// Date au format « AAAA-MM-JJ » attendu par l'API (`birth_date`).
  String? get _birthDateIso {
    final d = _birthDate;
    if (d == null) return null;
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AppState>().registerMembreParCode(
            nomPrenom: _nomPrenomController.text.trim(),
            email: _emailController.text.trim(),
            telephone: _telephoneController.text.trim(),
            password: _passwordController.text,
            codeEglise: _codeController.text.trim().toUpperCase(),
            birthDate: _birthDateIso,
            sexe: _sexe,
            department: _departementController.text.trim().isEmpty
                ? null
                : _departementController.text.trim(),
            fonction: _fonction == 'Aucun' ? null : _fonction,
          );
      if (!mounted) return;
      if (result.lie) {
        // Session appliquée par AppState : MaterialApp bascule sur
        // l'accueil fidèle. Rien à faire ici.
        return;
      }
      setState(() => _error = messageErreurSimple(result.message));
    } catch (e) {
      if (mounted) setState(() => _error = messageErreurSimple(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Je suis membre d’une église')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Créez votre compte avec le code fidèle de votre '
                    'église. Le code fait foi : aucune validation n’est '
                    'nécessaire. Votre matricule vous est attribué '
                    'automatiquement et votre carte de membre est créée '
                    'tout de suite.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nomPrenomController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nom et prénom',
                      prefixIcon: Icon(Icons.person_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 2) {
                        return 'Saisissez votre nom et prénom.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Saisissez votre e-mail.';
                      }
                      if (!v.contains('@')) return 'E-mail invalide.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telephoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 8) {
                        return 'Saisissez votre téléphone.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake_outlined),
                    title: Text(
                      _birthDate == null
                          ? 'Date de naissance (optionnel)'
                          : 'Date de naissance : ${formatDate(_birthDate)}',
                    ),
                    trailing: _birthDate == null
                        ? const Icon(Icons.calendar_today_outlined)
                        : TextButton(
                            onPressed: () =>
                                setState(() => _birthDate = null),
                            child: const Text('Effacer'),
                          ),
                    onTap: _choisirDateNaissance,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _sexe,
                    decoration: const InputDecoration(
                      labelText: 'Sexe (optionnel)',
                      hintText: 'Non précisé',
                      helperText:
                          'Votre matricule est construit à partir de votre '
                          'nom, de votre date de naissance et de votre sexe '
                          '(système du permis du Québec).',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: null, child: Text('Non précisé')),
                      DropdownMenuItem(value: 'F', child: Text('Femme')),
                      DropdownMenuItem(value: 'M', child: Text('Homme')),
                    ],
                    onChanged: (v) => setState(() => _sexe = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      CodeInputFormatter(expectedPrefix: 'ESC-F-'),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Code fidèle de l’église (ex. ESC-F-0411)',
                      helperText:
                          'Demandez le code fidèle à votre pasteur ou à un '
                          'responsable, il ressemble à ESC-F-0411. Le tiret '
                          's’ajoute tout seul : tapez seulement les caractères.',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 4) {
                        return 'Saisissez le code fidèle de votre église.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _departementController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Département (optionnel)',
                      hintText: 'Ex. Louange et adoration, Jeunesse…',
                      prefixIcon: Icon(Icons.group_work_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _fonction,
                    decoration: const InputDecoration(
                      labelText: 'Fonction',
                      prefixIcon: Icon(Icons.work_outline),
                      border: OutlineInputBorder(),
                    ),
                    items: fonctionsParDefaut
                        .map((f) => DropdownMenuItem(
                            value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _fonction = v ?? 'Aucun'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() =>
                            _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return '8 caractères minimum.';
                      }
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Text('Créer mon compte fidèle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
