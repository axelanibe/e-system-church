import 'package:flutter/material.dart';

import '../widgets/code_input_formatter.dart';
import '../widgets/selecteur_indicatif_pays.dart';

/// Inscription membre par code fidèle : « Rejoindre mon église »
/// (maquette, écran 27). Le code fait foi : aucune validation par
/// l'administrateur, le matricule est attribué automatiquement, la
/// fiche membre et la carte sont créées tout de suite. Le code fidèle
/// (ESC-F-…) désigne une seule église, sans ambiguïté — le code de
/// tutelle (ESC-…) ne sert qu'aux églises qui se rattachent à une mère.
/// Champs hors maquette retirés (date de naissance, sexe, département,
/// fonction) : tous facultatifs côté serveur (`inscriptionMembreSchema`
/// dans server/src/auth.ts), ils n'entrent que dans le matricule ou
/// la fiche, jamais dans l'obligation d'inscription.
/// Blocage signalé : la maquette ne montre qu'un seul champ
/// « Téléphone ou e-mail * », mais l'API exige aujourd'hui les deux
/// (`email` valide ET `telephone` min 8 caractères). L'envoi attend
/// donc une évolution du serveur (rendre l'un des deux optionnel) ;
/// le bouton l'explique au lieu d'envoyer une inscription incomplète.
class RegisterFideleScreen extends StatefulWidget {
  const RegisterFideleScreen({super.key});

  @override
  State<RegisterFideleScreen> createState() => _RegisterFideleScreenState();
}

class _RegisterFideleScreenState extends State<RegisterFideleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _contactController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  // Indicatif du champ « Téléphone ou e-mail » : Côte d’Ivoire au
  // départ. L’envoi est bloqué côté serveur (voir _submit) : quand
  // il sera possible, l’indicatif sera préfixé au numéro, ignoré
  // pour un e-mail, comme sur la connexion.
  String _indicatifIso = 'CI';

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _contactController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // Un seul contact saisi, l'API en exige deux : impossible
    // d'appeler l'inscription sans inventer l'autre. On l'explique.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Création impossible pour l’instant : l’inscription exige '
          'aujourd’hui un e-mail et un téléphone, la maquette n’en '
          'montre qu’un seul. Aucun compte n’a été créé.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre mon église')),
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
                    'Avec le code reçu de votre église, créez votre '
                    'compte membre.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      CodeInputFormatter(expectedPrefix: 'ESC-F-'),
                    ],
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Code de l’église *',
                      helperText: 'Code reçu de votre église',
                      helperStyle: TextStyle(fontSize: 13.5),
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
                    controller: _nomController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Nom *',
                      helperText: 'Nom de famille',
                      helperStyle: TextStyle(fontSize: 13.5),
                      prefixIcon: Icon(Icons.person_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 2) {
                        return 'Saisissez votre nom.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _prenomController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Prénom *',
                      helperText: 'Prénom',
                      helperStyle: TextStyle(fontSize: 13.5),
                      prefixIcon: Icon(Icons.person_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 2) {
                        return 'Saisissez votre prénom.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contactController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Téléphone ou e-mail *',
                      helperText: 'Votre contact',
                      helperStyle: const TextStyle(fontSize: 13.5),
                      prefixIcon:
                          const Icon(Icons.contact_mail_outlined),
                      prefix: SelecteurIndicatifPays(
                        iso: _indicatifIso,
                        onChanged: (iso) =>
                            setState(() => _indicatifIso = iso),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Saisissez votre téléphone ou votre e-mail.';
                      }
                      if (v.contains('@')) {
                        if (!v.contains('.')) return 'E-mail invalide.';
                      } else {
                        final chiffres =
                            v.replaceAll(RegExp(r'[^0-9]'), '');
                        if (chiffres.length < 8) {
                          return 'Téléphone ou e-mail invalide.';
                        }
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
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe *',
                      helperText: '••••••••',
                      helperStyle: const TextStyle(fontSize: 13.5),
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
                  const SizedBox(height: 12),
                  const Text(
                    'Le code est vérifié avant la création ; le matricule '
                    'et la carte de membre sont délivrés immédiatement.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Créer mon compte', style: TextStyle(fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('← Retour à la connexion',
                        style: TextStyle(fontSize: 13)),
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
