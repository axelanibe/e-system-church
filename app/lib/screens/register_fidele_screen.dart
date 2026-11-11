import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Inscription fidèle : « Je suis membre d'une église » (e-mail, mot de
/// passe, matricule). Si l'e-mail concorde avec la fiche membre, le compte
/// est lié immédiatement et la session démarre ; sinon, une demande est
/// envoyée à l'administrateur de l'église et l'écran l'explique.
class RegisterFideleScreen extends StatefulWidget {
  const RegisterFideleScreen({super.key});

  @override
  State<RegisterFideleScreen> createState() => _RegisterFideleScreenState();
}

class _RegisterFideleScreenState extends State<RegisterFideleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _matriculeController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  String? _messageDemande;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _matriculeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _messageDemande = null;
    });
    try {
      final result = await context.read<AppState>().registerFidele(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            matricule: _matriculeController.text.trim(),
          );
      if (!mounted) return;
      if (result.lie) {
        // Session appliquée par AppState : MaterialApp bascule sur
        // l'accueil fidèle. Rien à faire ici.
        return;
      }
      setState(() => _messageDemande = result.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
            child: _messageDemande != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          size: 64, color: scheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        _messageDemande!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Retour à la connexion'),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Créez votre compte avec le matricule de votre '
                          'carte de membre. Si votre e-mail est celui de '
                          'votre fiche membre, votre compte est lié tout de '
                          'suite ; sinon, l’administrateur de votre église '
                          'devra valider votre demande.',
                        ),
                        const SizedBox(height: 24),
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
                          controller: _matriculeController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Matricule (sur votre carte de membre)',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Saisissez votre matricule.';
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
