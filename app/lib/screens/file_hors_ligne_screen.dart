import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../services/api_service.dart';
import '../services/file_hors_ligne_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// T11 — File hors ligne : la file du serveur (actions soumises,
/// rejouées dans l'ordre) et la file locale de l'appareil (pointages
/// et saisies enregistrés sans réseau, rejoués à la reconnexion).
class FileHorsLigneScreen extends StatefulWidget {
  const FileHorsLigneScreen({super.key});

  @override
  State<FileHorsLigneScreen> createState() => _FileHorsLigneScreenState();
}

class _FileHorsLigneScreenState extends State<FileHorsLigneScreen> {
  final _fileLocale = FileHorsLigneService();
  List<ActionHorsLigne> _actionsServeur = [];
  List<ActionEnFile> _actionsLocales = [];
  bool _chargement = true;
  String? _erreur;
  String? _message;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final state = context.read<AppState>();
      final serveur = await state.api.getActionsHorsLigne();
      final userId = state.user?.id;
      final locales =
          userId == null ? <ActionEnFile>[] : await _fileLocale.lire(userId);
      if (!mounted) return;
      setState(() {
        _actionsServeur = serveur;
        _actionsLocales = locales;
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

  Future<void> _rejouerServeur() async {
    try {
      final resultat =
          await context.read<AppState>().api.rejouerFileHorsLigne();
      if (!mounted) return;
      setState(() {
        _message =
            '${resultat.rejouees} action(s) rejouée(s), ${resultat.echouees} en échec.';
      });
      await _charger();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Future<void> _rejouerLocale() async {
    final state = context.read<AppState>();
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final resultat = await _fileLocale.rejouer(userId, state.api);
      if (!mounted) return;
      setState(() {
        _message =
            'File locale : ${resultat.envoyees} envoyée(s), ${resultat.echecs} en échec.';
      });
      await _charger();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Widget _carteAction(ActionHorsLigne action) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: action.statut == 'echouee'
              ? AppTheme.rougeErreur.withValues(alpha: 0.08)
              : AppTheme.orClair,
          child: Icon(
            action.statut == 'echouee'
                ? Icons.error_outline
                : Icons.cloud_upload_outlined,
            color: action.statut == 'echouee'
                ? AppTheme.rougeErreur
                : AppTheme.orFonce,
          ),
        ),
        title: Text(action.typeLabel),
        subtitle: Text(
          '${action.statutLabel} · ${formatDateTime(action.createdAt)}'
          '${action.erreur == null ? '' : '\n${action.erreur}'}',
        ),
        isThreeLine: action.erreur != null,
      ),
    );
  }

  Widget _carteLocale(ActionEnFile action) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppTheme.orClair,
          child: Icon(Icons.smartphone_outlined, color: AppTheme.orFonce),
        ),
        title: Text(
            action.typeAction == 'presence.pointer' ? 'Pointage' : 'Saisie'),
        subtitle: Text(
          '${formatDateTime(action.createdAt)}'
          '${action.erreur == null ? '' : '\n${action.erreur}'}',
        ),
        isThreeLine: action.erreur != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File hors ligne')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _rejouerServeur,
                          icon: const Icon(Icons.replay_outlined),
                          label: const Text('Rejouer la file'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _rejouerLocale,
                          icon: const Icon(Icons.smartphone_outlined),
                          label: const Text('Rejouer le téléphone'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'File du serveur',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_actionsServeur.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune action en attente sur le serveur.'),
                      ),
                    ),
                  for (final action in _actionsServeur) _carteAction(action),
                  const SizedBox(height: 16),
                  const Text(
                    'File de cet appareil',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_actionsLocales.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Aucune action en attente sur cet appareil.'),
                      ),
                    ),
                  for (final action in _actionsLocales) _carteLocale(action),
                ],
              ),
            ),
    );
  }
}
