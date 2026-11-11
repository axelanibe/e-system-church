import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/paiements.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Module 14 — « Mon église → Paiements » : l'admin choisit son pays,
/// active ses moyens de paiement et saisit ses identifiants.
///
/// Les identifiants ne sont jamais affichés : les champs secrets sont
/// masqués à la saisie, jamais pré-remplis, et l'API ne renvoie que
/// l'aperçu masqué (`••••1234`) et l'état « configuré ».
class PaiementsScreen extends StatefulWidget {
  const PaiementsScreen({super.key});

  @override
  State<PaiementsScreen> createState() => _PaiementsScreenState();
}

const Map<String, String> _paysLabels = {
  'CI': 'Côte d’Ivoire',
  'SN': 'Sénégal',
  'KE': 'Kenya',
  'INTL': 'International',
};

class _PaiementsScreenState extends State<PaiementsScreen> {
  String _pays = 'CI';
  bool _loading = true;
  String? _error;
  List<FournisseurPaiement> _fournisseurs = [];
  List<EglisePaiement> _configs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fournisseurs =
          await state.api.getFournisseursPaiement(pays: _pays);
      final configs = await state.api.getMesPaiements(state.church!.id);
      if (mounted) {
        setState(() {
          _fournisseurs = fournisseurs;
          _configs = configs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  EglisePaiement? _configPour(String code) =>
      _configs.where((c) => c.fournisseurCode == code).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAdmin = state.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Paiements')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _pays,
              decoration: const InputDecoration(
                labelText: 'Pays de l’église *',
                border: OutlineInputBorder(),
              ),
              items: _paysLabels.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _pays = v);
                _load();
              },
            ),
          ),
          if (!isAdmin)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Consultation seulement : seul un administrateur de '
                'l’église peut configurer les moyens de paiement.',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _loading
                ? const AppLoading()
                : _error != null
                    ? AppError(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _fournisseurs.isEmpty
                            ? const EmptyState(
                                icon: Icons.payments_outlined,
                                message:
                                    'Aucun fournisseur disponible pour ce pays pour l’instant.',
                              )
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  if (_configs.isEmpty)
                                    const EmptyState(
                                      icon: Icons.payments_outlined,
                                      message:
                                          'Aucun moyen de paiement configuré pour l’instant.',
                                    ),
                                  for (final f in _fournisseurs)
                                    _FournisseurCard(
                                      fournisseur: f,
                                      config: _configPour(f.code),
                                      pays: _pays,
                                      churchId: state.church!.id,
                                      readOnly: !isAdmin,
                                      onChanged: _load,
                                    ),
                                ],
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'un fournisseur : état, aperçu masqué et formulaire de saisie
/// de ses identifiants (jamais pré-remplis, jamais ré-affichés).
class _FournisseurCard extends StatefulWidget {
  final FournisseurPaiement fournisseur;
  final EglisePaiement? config;
  final String pays;
  final String churchId;
  final bool readOnly;
  final VoidCallback onChanged;

  const _FournisseurCard({
    required this.fournisseur,
    required this.config,
    required this.pays,
    required this.churchId,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<_FournisseurCard> createState() => _FournisseurCardState();
}

class _FournisseurCardState extends State<_FournisseurCard> {
  late final TextEditingController _libelleController;
  late final Map<String, TextEditingController> _champControllers;
  late bool _actif;
  bool _saving = false;
  bool _testing = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _libelleController =
        TextEditingController(text: widget.config?.libelle ?? '');
    _champControllers = {
      for (final c in widget.fournisseur.champsRequis)
        c.nom: TextEditingController(),
    };
    _actif = widget.config?.actif ?? true;
  }

  @override
  void dispose() {
    _libelleController.dispose();
    for (final c in _champControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  /// Message d'erreur lisible pour un 403 (non-admin) ou toute autre erreur.
  String _friendlyError(Object e) {
    if (e is ApiException && e.statusCode == 403) {
      return 'Seul un administrateur de l’église peut modifier les moyens de paiement.';
    }
    return e.toString();
  }

  Future<void> _save() async {
    final api = context.read<AppState>().api;
    final isCreation = widget.config == null;
    final secrets = <Map<String, String>>[];
    for (final champ in widget.fournisseur.champsRequis) {
      final valeur = _champControllers[champ.nom]!.text.trim();
      if (valeur.isEmpty) {
        if (isCreation) {
          _showMessage(
              'Champ obligatoire manquant : ${champ.label}.',
              isError: true);
          return;
        }
        continue;
      }
      secrets.add({'nom_champ': champ.nom, 'valeur': valeur});
    }
    setState(() => _saving = true);
    try {
      await api.configurerPaiement(
        churchId: widget.churchId,
        fournisseurCode: widget.fournisseur.code,
        pays: widget.pays,
        libelle: _libelleController.text.trim().isEmpty
            ? null
            : _libelleController.text.trim(),
        actif: _actif,
        secrets: secrets,
      );
      for (final c in _champControllers.values) {
        c.clear();
      }
      _showMessage('Moyen de paiement enregistré.');
      widget.onChanged();
    } catch (e) {
      _showMessage(_friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final api = context.read<AppState>().api;
    setState(() => _testing = true);
    try {
      final result = await api.testerPaiement(
        churchId: widget.churchId,
        fournisseurCode: widget.fournisseur.code,
      );
      _showMessage(result.message, isError: !result.ok);
    } catch (e) {
      _showMessage(_friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete() async {
    final api = context.read<AppState>().api;
    final confirme = await confirmDelete(
      context,
      'Retirer ${widget.fournisseur.nom} des moyens de paiement de '
      'l’église ? Ses identifiants seront supprimés.',
    );
    if (!confirme) return;
    try {
      await api.supprimerPaiement(
        churchId: widget.churchId,
        fournisseurCode: widget.fournisseur.code,
      );
      if (mounted) showSuccess(context, 'Moyen de paiement retiré.');
      widget.onChanged();
    } catch (e) {
      _showMessage(_friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fournisseur;
    final config = widget.config;
    final scheme = Theme.of(context).colorScheme;
    final statut = config == null
        ? 'Non configuré'
        : config.actif
            ? 'Actif'
            : 'Configuré — inactif';
    final statutColor = config == null
        ? scheme.onSurfaceVariant
        : config.actif
            ? AppTheme.vertFonce
            : Colors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    f.nom,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(label: statut, color: statutColor),
              ],
            ),
            if (f.type.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  f.type,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (config != null) ...[
              const SizedBox(height: 8),
              if (config.libelle != null && config.libelle!.isNotEmpty)
                Text('Libellé : ${config.libelle}'),
              if (config.apercu != null && config.apercu!.isNotEmpty)
                Text('Identifiant : ${config.apercu}'),
              for (final champ in config.champs)
                Text(
                  '${champ.label} : ${champ.configure ? 'configuré' : 'non configuré'}',
                ),
            ],
            if (!widget.readOnly) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _libelleController,
                decoration: const InputDecoration(
                  labelText: 'Libellé (facultatif)',
                  hintText: 'Ex. compte principal',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final champ in f.champsRequis) ...[
                TextField(
                  controller: _champControllers[champ.nom]!,
                  obscureText: champ.secret,
                  enableSuggestions: !champ.secret,
                  autocorrect: !champ.secret,
                  decoration: InputDecoration(
                    labelText: champ.label,
                    hintText: config == null
                        ? null
                        : 'Laisser vide pour garder la valeur actuelle',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SwitchListTile(
                title: const Text('Moyen actif'),
                value: _actif,
                onChanged: (v) => setState(() => _actif = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError
                          ? scheme.error
                          : AppTheme.vertFonce,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ),
                  if (config != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testing ? null : _test,
                        child: _testing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Tester la connexion'),
                      ),
                    ),
                  ],
                ],
              ),
              if (config != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer ce moyen'),
                  style: TextButton.styleFrom(
                      foregroundColor: scheme.error),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                'Les identifiants sont chiffrés sur le serveur et ne sont '
                'jamais affichés.',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
