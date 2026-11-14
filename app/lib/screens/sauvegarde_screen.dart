import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// T11 — Sauvegardes : paramètres (fréquence, heure), création manuelle,
/// liste des sauvegardes chiffrées et restauration avec confirmation.
/// La restauration remet les données de l'église à l'état sauvegardé ;
/// le journal d'audit n'est jamais réécrit.
class SauvegardeScreen extends StatefulWidget {
  const SauvegardeScreen({super.key});

  @override
  State<SauvegardeScreen> createState() => _SauvegardeScreenState();
}

class _SauvegardeScreenState extends State<SauvegardeScreen> {
  ParametresConfiance? _parametres;
  List<Sauvegarde> _sauvegardes = [];
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
      final api = context.read<AppState>().api;
      final parametres = await api.getParametresConfiance();
      final sauvegardes = await api.getSauvegardes();
      if (!mounted) return;
      setState(() {
        _parametres = parametres;
        _sauvegardes = sauvegardes;
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

  Future<void> _creer() async {
    setState(() => _message = null);
    try {
      final sauvegarde =
          await context.read<AppState>().api.creerSauvegarde();
      if (!mounted) return;
      setState(() {
        _sauvegardes = [sauvegarde, ..._sauvegardes];
        _message = 'Sauvegarde créée (${sauvegarde.tailleLabel}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Future<void> _restaurer(Sauvegarde sauvegarde) async {
    final confirmer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: Text(
          'Les données de l’église reviennent à l’état du '
          '${formatDateTime(sauvegarde.createdAt)}. '
          'Les données ajoutées depuis seront perdues. '
          'Le journal d’audit n’est pas modifié.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (confirmer != true || !mounted) return;
    final api = context.read<AppState>().api;
    try {
      await api.restaurerSauvegarde(sauvegarde.id);
      if (!mounted) return;
      setState(() => _message = 'Sauvegarde restaurée.');
      await _charger();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Future<void> _changerFrequence(String? frequence) async {
    if (frequence == null || frequence == _parametres?.sauvegardeFrequence) {
      return;
    }
    try {
      final parametres = await context
          .read<AppState>()
          .api
          .patchParametresConfiance(sauvegardeFrequence: frequence);
      if (!mounted) return;
      setState(() => _parametres = parametres);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegardes')),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sauvegarde automatique',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _parametres?.sauvegardeFrequence,
                            decoration: const InputDecoration(
                              labelText: 'Fréquence',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'jamais',
                                  child: Text('Jamais')),
                              DropdownMenuItem(
                                  value: 'quotidienne',
                                  child: Text('Quotidienne')),
                              DropdownMenuItem(
                                  value: 'hebdomadaire',
                                  child: Text('Hebdomadaire')),
                            ],
                            onChanged: _changerFrequence,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _parametres?.sauvegardeAutoDerniereAt == null
                                ? 'Aucune sauvegarde automatique pour le moment.'
                                : 'Dernière sauvegarde automatique : '
                                    '${formatDateTime(_parametres!.sauvegardeAutoDerniereAt)}.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _creer,
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('Créer une sauvegarde'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_sauvegardes.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune sauvegarde pour le moment.'),
                      ),
                    ),
                  for (final sauvegarde in _sauvegardes)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.orClair,
                          child: Icon(Icons.backup_outlined,
                              color: AppTheme.orFonce),
                        ),
                        title: Text(formatDateTime(sauvegarde.createdAt)),
                        subtitle: Text(
                          '${sauvegarde.tailleLabel} · ${sauvegarde.nbTables} tables · ${sauvegarde.statutLabel}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _restaurer(sauvegarde),
                          child: const Text('Restaurer'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
