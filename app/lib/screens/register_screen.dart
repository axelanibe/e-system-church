import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Inscription en deux choix :
/// - « Créer une église mère » : l'église naît active, sans mère.
/// - « Rejoindre une église mère » : code d'invitation de la mère ;
///   la demande reste en attente jusqu'à acceptation par la mère.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _joinMother = false;

  final _churchNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _churchPhoneController = TextEditingController();
  final _parentCodeController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  // Logo choisi à l'inscription (facultatif) : téléversé après la création
  // de l'église, comme dans Mon église. Sans logo, les initiales de
  // l'église s'affichent sur fond bleu nuit.
  Uint8List? _logoBytes;
  String? _logoName;

  @override
  void dispose() {
    _churchNameController.dispose();
    _cityController.dispose();
    _churchPhoneController.dispose();
    _parentCodeController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  /// Choix du logo (PNG/JPG, max 2 Mo), avec aperçu. Facultatif.
  Future<void> _choisirLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      if (file.size > 2 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error = 'Le logo doit peser 2 Mo au maximum.');
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
        _logoBytes = file.bytes;
        _logoName = file.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AppState>().register(
            churchName: _churchNameController.text.trim(),
            city: _cityController.text.trim(),
            churchPhone: _churchPhoneController.text.trim().isEmpty
                ? null
                : _churchPhoneController.text.trim(),
            adminName: _adminNameController.text.trim(),
            adminEmail: _adminEmailController.text.trim(),
            password: _passwordController.text,
            parentCode: _joinMother
                ? _parentCodeController.text.trim().toUpperCase()
                : null,
            logoBase64: _logoBytes == null
                ? null
                : base64Encode(_logoBytes!),
            logoFilename: _logoName,
          );
      if (!mounted) return;
      if (result.rattachement != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Église créée. Votre demande de rattachement est en attente de validation par l’église mère.'),
          ),
        );
      }
      // La connexion est automatique : l'écran d'accueil prend le relais
      // (AppState notifie, MaterialApp bascule sur HomeScreen).
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = messageErreurSimple(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _choiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Radio<bool>(
                value: title.startsWith('Créer') ? false : true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inscrire mon église')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: RadioGroup<bool>(
                groupValue: _joinMother,
                onChanged: (value) {
                  if (value != null) setState(() => _joinMother = value);
                },
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _choiceCard(
                    title: 'Créer une église mère',
                    subtitle:
                        'Mon église devient la tête d’un nouveau réseau. Je pourrai ensuite créer des sous-églises.',
                    icon: Icons.church,
                    selected: !_joinMother,
                    onTap: () => setState(() => _joinMother = false),
                  ),
                  const SizedBox(height: 8),
                  _choiceCard(
                    title: 'Rejoindre une église mère',
                    subtitle:
                        'Mon église rejoint un réseau existant avec le code d’invitation de la mère. La demande devra être validée.',
                    icon: Icons.group_add_outlined,
                    selected: _joinMother,
                    onTap: () => setState(() => _joinMother = true),
                  ),
                  const SizedBox(height: 24),
                  Text('Votre église',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _churchNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nom de l’église *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Nom requis (2 caractères minimum).'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Ville *',
                      hintText: 'Ex. Abidjan',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Ville requise.'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _churchPhoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone de l’église',
                      hintText: 'Ex. +225 07 00 00 00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_joinMother) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _parentCodeController,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Code d’invitation de l’église mère *',
                        hintText: 'Ex. GD-PLAT',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (_joinMother &&
                              (v == null || v.trim().length < 4))
                          ? 'Code d’invitation requis.'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Logo de l’église (optionnel)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: _logoBytes == null
                            ? null
                            : MemoryImage(_logoBytes!),
                        child: _logoBytes == null
                            ? const Icon(Icons.church_outlined, size: 32)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _choisirLogo,
                              icon: const Icon(Icons.image_outlined),
                              label: const Text(
                                  'Choisir un logo (PNG/JPG, max 2 Mo)'),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Sans logo, vos initiales s’affichent '
                              'sur fond bleu nuit.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Vous, administrateur de l’église',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminNameController,
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
                  TextFormField(
                    controller: _adminEmailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'E-mail *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'E-mail requis.';
                      }
                      if (!v.contains('@')) return 'E-mail invalide.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe * (8 caractères minimum)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Mot de passe trop court (8 caractères minimum).'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordConfirmController,
                    obscureText: _obscurePassword,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le mot de passe *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v != _passwordController.text
                        ? 'Les mots de passe ne correspondent pas.'
                        : null,
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _register,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Créer mon église'),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
