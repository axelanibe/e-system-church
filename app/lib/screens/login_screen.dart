import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';
import '../widgets/selecteur_indicatif_pays.dart';
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
/// et son sous-titre, libellés au-dessus des champs, texte d'aide
/// dans le champ (hintText), note de verrouillage après 5 mots de
/// passe incorrects (15 minutes),
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
  // Indicatif du champ « E-mail ou téléphone » : Côte d’Ivoire au
  // départ, l’utilisateur peut choisir un autre pays.
  String _indicatifIso = 'CI';
  // L’indicatif ne s’affiche que pour un numéro de téléphone. Dès
  // que la saisie ressemble à un e-mail (lettres ou @), il se
  // cache : un e-mail n’a pas d’indicatif pays.
  bool _estTelephone = true;

  @override
  void initState() {
    super.initState();
    _identifiantController.addListener(() {
      final estTel = estNumeroTelephone(_identifiantController.text);
      if (estTel != _estTelephone) {
        setState(() => _estTelephone = estTel);
      }
    });
  }

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
      // E-mail : l’indicatif est ignoré. Numéro : l’indicatif choisi
      // est préfixé, le serveur normalise ensuite.
      final identifiant = composerTelephoneAvecIndicatif(
        indicatifParIso(_indicatifIso).indicatif,
        _identifiantController.text.trim(),
      );
      await context.read<AppState>().login(
            identifiant: identifiant,
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
                        // du champ, aide dans le champ (hintText,
                        // maquette, écran 27), pas de libellé flottant.
                        _buildTextField(
                          context: context,
                          controller: _identifiantController,
                          label: 'E-mail ou téléphone *',
                          hint: 'E-mail ou numéro de téléphone',
                          icon: Icons.person_outline,
                          prefix: _estTelephone
                              ? SelecteurIndicatifPays(
                                  iso: _indicatifIso,
                                  onChanged: (iso) =>
                                      setState(() => _indicatifIso = iso),
                                )
                              : null,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: validerIdentifiant,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          context: context,
                          controller: _passwordController,
                          label: 'Mot de passe *',
                          hint: '••••••••',
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
                          'se verrouille pendant 15 minutes — sans indiquer '
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
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Mot de passe oublié',
                              style: TextStyle(
                                color: AppTheme.orFonce,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),

                        // 3. Carte « Nouveau sur e-System Church »
                        // (maquette, écran 27) : titre, sous-titre,
                        // bouton or « Inscrire mon église » puis bouton
                        // fantôme « Je suis membre d'une église ».
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Nouveau sur e-System Church',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Choisissez votre situation pour commencer.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _loading
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const RegisterScreen(),
                                            ),
                                          ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.or,
                                    foregroundColor: AppTheme.violetProfond,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Inscrire mon église',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 9),
                                OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const RegisterFideleScreen(),
                                            ),
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Je suis membre d’une église',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
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
    String? hint,
    required IconData icon,
    Widget? prefix,
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
        // Le conteneur ne porte que l’ombre : le fond blanc est
        // dans le champ (filled), pas dans le conteneur. Avant, le
        // fond blanc du conteneur débordait sous la bordure et le
        // texte d’aide (helperText) y apparaissait dans une seconde
        // boîte blanche ; un message d’erreur sous la bordure aurait
        // recréé la même seconde boîte. Le champ ne rend plus qu’une
        // seule boîte, en état normal comme en erreur.
        Container(
          decoration: BoxDecoration(
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
              filled: true,
              fillColor: scheme.surface,
              hintText: hint,
              hintStyle: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13.5,
              ),
              prefixIcon:
                  Icon(icon, color: scheme.onSurfaceVariant, size: 20),
              prefix: prefix,
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

}
