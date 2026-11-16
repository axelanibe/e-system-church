import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';
import 'forgot_password_screen.dart';
import 'login_plateforme_screen.dart';
import 'register_fidele_screen.dart';
import 'register_screen.dart';

/// Validation de l'identifiant de connexion : e-mail (contient @) ou
/// numéro de téléphone (au moins 8 chiffres). Le serveur normalise le
/// téléphone et met l'e-mail en minuscules.
String? validerIdentifiant(String? v) {
  if (v == null || v.trim().isEmpty) {
    return 'Saisissez votre e-mail ou votre téléphone.';
  }
  final s = v.trim();
  if (s.contains('@')) {
    if (!s.contains('.')) return 'E-mail invalide.';
    return null;
  }
  final chiffres = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.length < 8) return 'E-mail ou numéro invalide.';
  return null;
}

/// Rembourrage de l'écran de connexion, partagé par le défilement
/// et le calcul de la hauteur minimale de la boîte.
const _rembourrage = EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0);

/// Écran de connexion : e-mail ou téléphone + mot de passe, JWT stocké
/// en sécurité. La connexion exige un compte réel créé sur le serveur.
/// Mise en page d'après la maquette (écran 27) : logo 76x76, « Bienvenue »
/// et son sous-titre, libellés au-dessus des champs avec l'aide en
/// dessous, note de verrouillage après 5 mots de passe incorrects,
/// « Mot de passe oublié » sous la note, deux cartes d'action, accès
/// administrateur de la plateforme discret en pied de page. Le logo est
/// la vraie image (LogoApp), jamais le texte « ESC » de la maquette.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifiantController = TextEditingController();
  final _passwordController = TextEditingController();
  final _code2faController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _demande2fa = false;

  @override
  void dispose() {
    _identifiantController.dispose();
    _passwordController.dispose();
    _code2faController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(
            identifiant: _identifiantController.text.trim(),
            password: _passwordController.text,
            code2fa: _demande2fa ? _code2faController.text.trim() : null,
          );
    } catch (e) {
      if (mounted) {
        // 2FA active : le serveur demande le code, on affiche le champ.
        if (e is ApiException && e.code == 'code_2fa_requis') {
          setState(() {
            _demande2fa = true;
            _error = 'Saisissez votre code à 6 chiffres.';
          });
        } else {
          setState(() => _error = messageErreurSimple(e));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Unifie la barre d'état avec le fond clair de la page.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppTheme.fondPapier,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.fondPapier,
        body: SafeArea(
          child: Center(
            // La boîte garde la hauteur disponible : quand le clavier
            // s'ouvre, le contenu reste centré dans l'espace restant
            // au lieu de basculer brutalement en haut de l'écran.
            // Le Center est gardé : sans lui, la boîte de 420 px
            // serait collée à gauche sur écran large.
            child: LayoutBuilder(
              builder: (context, contraintes) => SingleChildScrollView(
                padding: _rembourrage,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: contraintes.maxHeight - _rembourrage.vertical,
                    maxWidth: 420,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. En-tête (logo + titre).
                        Center(
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.violetProfond
                                      .withValues(alpha: 0.15),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const LogoApp(taille: 76),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bienvenue',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connectez-vous pour retrouver votre église, '
                          'vos cultes et votre parcours.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 32),

                        // 2. Formulaire de connexion : libellé au-dessus
                        // du champ, aide en dessous (maquette, écran 27),
                        // pas de libellé flottant.
                        _buildTextField(
                          context: context,
                          controller: _identifiantController,
                          label: 'E-mail ou téléphone *',
                          helper: 'E-mail ou numéro de téléphone',
                          icon: Icons.person_outline,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: validerIdentifiant,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          context: context,
                          controller: _passwordController,
                          label: 'Mot de passe *',
                          helper: '••••••••',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: scheme.onSurfaceVariant,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Saisissez votre mot de passe.';
                            }
                            return null;
                          },
                        ),
                        if (_demande2fa) ...[
                          const SizedBox(height: 14),
                          _buildTextField(
                            context: context,
                            controller: _code2faController,
                            label: 'Code à 6 chiffres',
                            icon: Icons.phonelink_lock_outlined,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            validator: (v) {
                              if (v == null || v.trim().length != 6) {
                                return 'Le code compte 6 chiffres.';
                              }
                              return null;
                            },
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(color: scheme.error),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        // Bouton principal.
                        FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor:
                                scheme.primary.withValues(alpha: 0.4),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        // Verrouillage après 5 mots de passe incorrects
                        // (maquette, écran 27) : la note ne dit jamais
                        // quel champ est faux.
                        Text(
                          'Après 5 mots de passe incorrects, la connexion '
                          'se verrouille temporairement — sans indiquer '
                          'quel champ est faux.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        // Mot de passe oublié, sous la note.
                        Center(
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Mot de passe oublié',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                        // 3. Séparateur visuel.
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 26),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                      child: Divider(
                                          color: AppTheme.bordure,
                                          thickness: 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Text(
                                      'Nouveau sur e-System Church',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                      child: Divider(
                                          color: AppTheme.bordure,
                                          thickness: 1)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choisissez votre situation pour commencer.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 4. Cartes d'action secondaires.
                        _buildActionCard(
                          context: context,
                          icon: Icons.church_outlined,
                          title: 'Inscrire mon église',
                          subtitle: 'Pour créer une nouvelle église.',
                          onTap: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                        ),
                        const SizedBox(height: 12),
                        _buildActionCard(
                          context: context,
                          icon: Icons.group_add_outlined,
                          title: 'Je suis membre d’une église',
                          subtitle: 'Pour rejoindre votre église avec son code.',
                          onTap: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RegisterFideleScreen(),
                                    ),
                                  ),
                        ),
                        const SizedBox(height: 28),

                        // 5. Accès administration discret en pied de page.
                        Center(
                          child: InkWell(
                            onTap: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LoginPlateformeScreen(),
                                      ),
                                    ),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      Icons.admin_panel_settings_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Accès administrateur de la plateforme',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? helper,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onFieldSubmitted: onFieldSubmitted,
            validator: validator,
            // 16 px minimum : en dessous, Safari sur iPhone zoome sur le
            // champ, le zoom reste après la connexion et l'accueil est
            // coupé à droite (page penchée d'un côté).
            style: TextStyle(fontSize: 16, color: scheme.onSurface),
            decoration: InputDecoration(
              helperText: helper,
              helperStyle: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13.5,
              ),
              prefixIcon:
                  Icon(icon, color: scheme.onSurfaceVariant, size: 20),
              suffixIcon: suffixIcon,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppTheme.bordure, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.primary, width: 1.6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.bordure, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: scheme.onSurfaceVariant, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
