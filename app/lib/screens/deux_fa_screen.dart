import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// T11 — Double authentification (TOTP) : activation par QR + code à
/// 6 chiffres, désactivation avec code. Réservée aux rôles Pasteur,
/// Trésorier et Admin (le serveur refuse les autres rôles). Le secret
/// est chiffré côté serveur, jamais stocké en clair, et le code de
/// secours n'est affiché qu'une seule fois, à l'activation.
class DeuxFaScreen extends StatefulWidget {
  const DeuxFaScreen({super.key});

  @override
  State<DeuxFaScreen> createState() => _DeuxFaScreenState();
}

class _DeuxFaScreenState extends State<DeuxFaScreen> {
  bool? _actif;
  Demarrage2fa? _demarrage;
  final _codeController = TextEditingController();
  bool _chargement = true;
  bool _enCours = false;
  String? _erreur;
  String? _message;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final actif = await context.read<AppState>().api.getEtat2fa();
      if (!mounted) return;
      setState(() {
        _actif = actif;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _chargement = false;
      });
    }
  }

  Future<void> _demarrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final demarrage = await context.read<AppState>().api.demarrer2fa();
      if (!mounted) return;
      setState(() {
        _demarrage = demarrage;
        _enCours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _enCours = false;
      });
    }
  }

  Future<void> _confirmerActivation() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _erreur = 'Le code compte 6 chiffres.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await context.read<AppState>().api.verifier2fa(code);
      if (!mounted) return;
      setState(() {
        _actif = true;
        _demarrage = null;
        _enCours = false;
        _message = 'Double authentification activée.';
      });
      _codeController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _enCours = false;
      });
    }
  }

  Future<void> _desactiver() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _erreur = 'Le code compte 6 chiffres.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await context.read<AppState>().api.desactiver2fa(code);
      if (!mounted) return;
      setState(() {
        _actif = false;
        _enCours = false;
        _message = 'Double authentification désactivée.';
      });
      _codeController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Double authentification')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_erreur != null)
                  Card(
                    color: AppTheme.rougeErreur.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_erreur!),
                    ),
                  ),
                if (_message != null)
                  Card(
                    color: AppTheme.vertFonce.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_message!),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _actif == true
                                  ? Icons.verified_outlined
                                  : Icons.phonelink_lock_outlined,
                              color: _actif == true
                                  ? AppTheme.vertFonce
                                  : AppTheme.orFonce,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _actif == true ? 'Activée' : 'Désactivée',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Un code à 6 chiffres est demandé à chaque connexion. '
                          'Réservée aux rôles Pasteur, Trésorier et Admin.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_actif != true && _demarrage == null)
                  FilledButton.icon(
                    onPressed: _enCours ? null : _demarrer,
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('Activer la double authentification'),
                  ),
                if (_demarrage != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Scannez ce code avec votre application d’authentification, puis saisissez le code à 6 chiffres.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          QrImageView(
                            data: _demarrage!.otpauthUri,
                            version: QrVersions.auto,
                            size: 200,
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            _demarrage!.secret,
                            style: AppTheme.styleCode,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Gardez ce secret : il ne sera plus affiché.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Code à 6 chiffres',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _enCours ? null : _confirmerActivation,
                    child: const Text('Confirmer l’activation'),
                  ),
                ],
                if (_actif == true) ...[
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Code à 6 chiffres',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _enCours ? null : _desactiver,
                    child: const Text('Désactiver la double authentification'),
                  ),
                ],
              ],
            ),
    );
  }
}
