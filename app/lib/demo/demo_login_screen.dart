// Écran de connexion de la version DÉMO.
//
// Copie de l'écran de connexion réel, avec en plus :
// - le bandeau « DÉMO — données fictives »,
// - les identifiants de démonstration pré-remplis,
// - un bouton « Entrer dans la démo » (compte admin, sans mot de passe
//   à saisir) et un bouton « Voir l'espace fidèle » (compte membre).
// L'écran réel (`lib/screens/login_screen.dart`) n'est pas modifié.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/register_fidele_screen.dart';
import '../screens/register_screen.dart';
import 'demo_banner.dart';
import 'mock_data.dart';

class DemoLoginScreen extends StatefulWidget {
  const DemoLoginScreen({super.key});

  @override
  State<DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<DemoLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController =
      TextEditingController(text: DemoAccounts.adminEmail);
  final _passwordController =
      TextEditingController(text: DemoAccounts.password);
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login({String? email, String? password}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(
            email: email ?? _emailController.text.trim(),
            password: password ?? _passwordController.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginForm() async {
    if (!_formKey.currentState!.validate()) return;
    await _login();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          const DemoBanner(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.church, size: 64, color: scheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          AppConfig.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppConfig.appSlogan,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: scheme.primary,
                              ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading
                              ? null
                              : () => _login(
                                    email: DemoAccounts.adminEmail,
                                    password: DemoAccounts.password,
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.secondary,
                            foregroundColor: const Color(0xFF083D2B),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Entrer dans la démo',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => _login(
                                    email: DemoAccounts.membreEmail,
                                    password: DemoAccounts.password,
                                  ),
                          child: const Text('Voir l’espace fidèle'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Données fictives du réseau « Grâce Divine » — '
                          'rien n’est envoyé à un serveur.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
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
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _loginForm(),
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Saisissez votre mot de passe.';
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
                          onPressed: _loading ? null : _loginForm,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Se connecter'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  ),
                          child: const Text('Mot de passe oublié ?'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                          child: const Text('Inscrire mon église'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RegisterFideleScreen(),
                                    ),
                                  ),
                          child: const Text('Je suis membre d’une église'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
