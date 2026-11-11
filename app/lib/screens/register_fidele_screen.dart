import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Inscription membre par code d'église : « Je suis membre d'une église »
/// (nom et prénom, e-mail, téléphone, mot de passe, code de l'église).
/// Le code fait foi : aucune validation par l'administrateur, le matricule
/// est attribué automatiquement, la fiche membre et la carte sont créées
/// tout de suite, le compte est lié immédiatement et la session démarre.
/// L'ancien parcours par matricule n'est plus proposé ici (il reste
/// disponible côté serveur pour les membres déjà fichés).
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
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nomPrenomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                    'Créez votre compte avec le code de votre église. '
                    'Le code fait foi : aucune validation n’est nécessaire. '
                    'Votre matricule vous est attribué automatiquement et '
                    'votre carte de membre est créée tout de suite.',
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
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Code de l’église (ex. ESC-XXXXXX)',
                      helperText:
                          'Demandez le code à votre pasteur ou à un '
                          'responsable, il ressemble à ESC-XXXXXX.',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 4) {
                        return 'Saisissez le code de votre église.';
                      }
                      return null;
                    },
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
