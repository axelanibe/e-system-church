import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Mode de l'écran : réinitialisation (lien « mot de passe oublié ») ou
/// initialisation (lien d'invitation de l'admin).
enum ResetMode { reinitialisation, initialisation }

/// Nouvel mot de passe par jeton : le même écran sert aux deux modes.
/// Sur le web, le jeton arrive dans `?token=` (main.dart l'y lit) ; sur
/// mobile, on colle le lien reçu ou le jeton.
class ResetPasswordScreen extends StatefulWidget {
  final String initialToken;
  final ResetMode mode;

  const ResetPasswordScreen({
    super.key,
    this.initialToken = '',
    this.mode = ResetMode.reinitialisation,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenController;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _done = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  bool get _isInitialisation => widget.mode == ResetMode.initialisation;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Accepte le jeton brut ou le lien complet (`...?token=...`) collé.
  String _extraireJeton(String saisi) {
    final texte = saisi.trim();
    final match = RegExp(r'[?&]token=([^&\s]+)').firstMatch(texte);
    return match?.group(1) ?? texte;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = _extraireJeton(_tokenController.text);
      final api = context.read<AppState>().api;
      if (_isInitialisation) {
        await api.initPassword(token: token, password: _passwordController.text);
      } else {
        await api.resetPassword(token: token, password: _passwordController.text);
      }
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = messageErreurSimple(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titre = _isInitialisation
        ? 'Initialiser mon mot de passe'
        : 'Réinitialiser mon mot de passe';
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _done
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: scheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        _isInitialisation
                            ? 'Mot de passe initialisé. Vous pouvez vous connecter.'
                            : 'Mot de passe réinitialisé. Vous pouvez vous connecter.',
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
                        Text(
                          _isInitialisation
                              ? 'Collez le lien d’invitation reçu de votre église, '
                                  'puis choisissez votre mot de passe.'
                              : 'Collez le lien reçu par e-mail (ou de votre '
                                  'administrateur), puis choisissez un nouveau '
                                  'mot de passe.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _tokenController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Lien reçu ou jeton',
                            prefixIcon: Icon(Icons.link_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Collez le lien ou le jeton reçu.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Nouveau mot de passe',
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
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Confirmer le mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() =>
                                  _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v != _passwordController.text) {
                              return 'Les deux mots de passe diffèrent.';
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
                                : const Text('Valider'),
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
