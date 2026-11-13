// Écran Cultes en direct (tranche T5).
// Quatre sections reprises de la projection, mot pour mot, application
// vierge : conducteur chronométré, transposition, compteur de portes,
// pointage QR. Aucune donnée inventée. Le conducteur et le pointage
// lisent les vraies données du serveur, la transposition et le compteur
// de portes sont des réglages de séance, gardés en mémoire de l'écran.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cultes.dart';
import '../models/cultes_direct.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../config/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'qr_scan_screen.dart';

class CultesDirectScreen extends StatefulWidget {
  const CultesDirectScreen({super.key});

  @override
  State<CultesDirectScreen> createState() => _CultesDirectScreenState();
}

class _CultesDirectScreenState extends State<CultesDirectScreen> {
  List<Culte> _cultes = [];
  String? _culteId;
  List<OrdreCulteItem> _moments = [];
  int _presents = 0;
  bool _chargement = true;
  String? _erreur;

  Timer? _minuteur;
  bool _enMarche = false;
  int _ecoule = 0;
  int _debutMoment = 0;
  int _momentIndex = 0;

  int _transposition = 0;
  int _entrees = 0;

  // Compléments T5 r3, mémoire de séance uniquement, jamais envoyés.
  final _retourRegieController = TextEditingController();
  final _capaciteController = TextEditingController();
  int? _capacite;
  PresenceStats? _stats;
  bool _statsErreur = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _retourRegieController.dispose();
    _capaciteController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final api = context.read<AppState>().api;
      final cultes = await api.getCultes();
      final culteId = _culteId ?? (cultes.isNotEmpty ? cultes.first.id : null);
      List<OrdreCulteItem> moments = [];
      int presents = 0;
      if (culteId != null) {
        moments = await api.getOrdreCulte(culteId);
        final presences = await api.getPresences(culteId: culteId);
        presents = compterPresents(presences);
      }
      // Statistiques globales : un échec ne bloque pas l'écran.
      PresenceStats? stats;
      var statsErreur = false;
      try {
        stats = await api.getPresenceStats();
      } catch (_) {
        statsErreur = true;
      }
      if (!mounted) return;
      setState(() {
        _cultes = cultes;
        _culteId = culteId;
        _moments = moments;
        _presents = presents;
        _stats = stats;
        _statsErreur = statsErreur;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.toString();
        _chargement = false;
      });
    }
  }

  Future<void> _changerCulte(String? culteId) async {
    if (culteId == null || culteId == _culteId) return;
    _arreter();
    _retourRegieController.clear();
    _capaciteController.clear();
    setState(() {
      _culteId = culteId;
      _ecoule = 0;
      _debutMoment = 0;
      _momentIndex = 0;
      _transposition = 0;
      _entrees = 0;
      _capacite = null;
    });
    try {
      final api = context.read<AppState>().api;
      final moments = await api.getOrdreCulte(culteId);
      final presences = await api.getPresences(culteId: culteId);
      if (!mounted) return;
      setState(() {
        _moments = moments;
        _presents = compterPresents(presences);
      });
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  Future<void> _rafraichirPresences() async {
    final culteId = _culteId;
    if (culteId == null) return;
    try {
      final api = context.read<AppState>().api;
      final presences = await api.getPresences(culteId: culteId);
      final stats = await api.getPresenceStats();
      if (!mounted) return;
      setState(() {
        _presents = compterPresents(presences);
        _stats = stats;
        _statsErreur = false;
      });
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  void _tick(Timer timer) {
    setState(() {
      _ecoule += 1;
      if (_moments.isEmpty || _momentIndex >= _moments.length) return;
      final moment = _moments[_momentIndex];
      if (momentTermine(_ecoule - _debutMoment, moment.dureeMinutes)) {
        if (_momentIndex + 1 < _moments.length) {
          _momentIndex += 1;
          _debutMoment = _ecoule;
        } else {
          _arreter();
        }
      }
    });
  }

  void _demarrer() {
    _minuteur?.cancel();
    _minuteur = Timer.periodic(const Duration(seconds: 1), _tick);
    setState(() => _enMarche = true);
  }

  void _arreter() {
    _minuteur?.cancel();
    _minuteur = null;
    setState(() => _enMarche = false);
  }

  void _remettreAZero() {
    _arreter();
    setState(() {
      _ecoule = 0;
      _debutMoment = 0;
      _momentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cultes en direct')),
      body: _chargement
          ? const AppLoading()
          : _erreur != null
              ? AppError(message: _erreur!, onRetry: _charger)
              : _cultes.isEmpty
                  ? const EmptyState(
                      icon: Icons.event_outlined,
                      message: 'Aucun culte planifié pour l’instant.',
                    )
                  : _contenu(),
    );
  }

  Widget _contenu() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: _culteId,
            decoration: const InputDecoration(labelText: 'Culte en cours'),
            items: _cultes
                .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.titre, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: _changerCulte,
          ),
        ),
        const SectionTitle(title: 'Conducteur chronométré'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Chaque moment du culte avance avec son temps prévu.'),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      formatDureeChrono(_ecoule),
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(color: AppTheme.bleuNuit),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _enMarche ? 'Chronomètre en marche' : 'Chronomètre en pause',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _enMarche ? _arreter : _demarrer,
                          child: Text(_enMarche ? 'Pause' : 'Démarrer'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _remettreAZero,
                          child: const Text('Remettre à zéro'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_moments.isEmpty)
                    const Text('Aucun moment au conducteur.\n'
                        'Les moments du culte, louange, parole, offrandes, '
                        's’ajouteront ici dans l’ordre.')
                  else
                    ..._moments.asMap().entries.map((e) {
                      final index = e.key;
                      final moment = e.value;
                      final courant = index == _momentIndex;
                      final passe = index < _momentIndex;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: courant
                              ? AppTheme.orFonce
                              : passe
                                  ? AppTheme.bleuNuit
                                  : AppTheme.bleuNuit.withValues(alpha: 0.15),
                          child: Text(
                            '${moment.ordre}',
                            style: TextStyle(
                              color: courant || passe
                                  ? Colors.white
                                  : AppTheme.bleuNuit,
                            ),
                          ),
                        ),
                        title: Text(moment.titre),
                        subtitle: moment.intervenant == null
                            ? null
                            : Text(moment.intervenant!),
                        trailing: moment.dureeMinutes == null
                            ? null
                            : Text('${moment.dureeMinutes} min'),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
        const SectionTitle(title: 'Transposition'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Décalez la tonalité des chants pour l’équipe de louange.'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _transposition =
                            transpositionSuivante(_transposition, -1)),
                        icon: const Icon(Icons.remove),
                        tooltip: 'Baisser d’un demi-ton',
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          _transposition > 0
                              ? '+$_transposition'
                              : '$_transposition',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _transposition =
                            transpositionSuivante(_transposition, 1)),
                        icon: const Icon(Icons.add),
                        tooltip: 'Monter d’un demi-ton',
                      ),
                    ],
                  ),
                  const Center(child: Text('DEMI-TONS')),
                ],
              ),
            ),
          ),
        ),
        const SectionTitle(title: 'Compteur de portes'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Comptage des entrées pendant le culte, porte par porte.'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => setState(
                            () => _entrees = compteurSuivant(_entrees, -1)),
                        icon: const Icon(Icons.remove),
                        tooltip: 'Retirer une entrée',
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          '$_entrees',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(
                            () => _entrees = compteurSuivant(_entrees, 1)),
                        icon: const Icon(Icons.add),
                        tooltip: 'Ajouter une entrée',
                      ),
                    ],
                  ),
                  const Center(child: Text('ENTRÉES')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _capaciteController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Capacité',
                      hintText: 'Nombre de places pour ce culte',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (texte) => setState(
                        () => _capacite = capaciteValide(texte)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Jauge',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        _capacite == null
                            ? 'Aucune capacité saisie.'
                            : '$_entrees / $_capacite '
                                '(${pourcentageJauge(_entrees, _capacite)} %)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progressionJauge(_entrees, _capacite),
                    color: AppTheme.orFonce,
                    backgroundColor: AppTheme.bleuNuit.withValues(alpha: 0.15),
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SectionTitle(title: 'Pointage QR'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Les présences sont pointées en scannant la carte de membre.'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Présences pointées',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        '$_presents',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _culteId == null
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      QrScanScreen(culteId: _culteId!),
                                ),
                              );
                              await _rafraichirPresences();
                            },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scanner une carte'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SectionTitle(title: 'Retour régie'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Note courte de la régie après le culte, gardée sur cet écran seulement.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retourRegieController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Retour régie',
                      hintText: 'Saisissez une courte note…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SectionTitle(title: 'Statistiques'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _statsErreur
                  ? const Text('Statistiques indisponibles pour l’instant.')
                  : _stats == null
                      ? const Text(
                          'Aucune présence enregistrée pour l’instant.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statistiques par culte',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            if (_stats!.parCulte.isEmpty)
                              const Text(
                                  'Aucune présence enregistrée pour l’instant.')
                            else
                              ..._stats!.parCulte.map((entree) {
                                final presents = presentsStat(entree);
                                final date = entree['date_heure'];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(titreStatCulte(entree)),
                                  subtitle: date == null
                                      ? null
                                      : Text(afficherDateTime(date)),
                                  trailing: Text(
                                    '$presents '
                                    '${presents > 1 ? 'présents' : 'présent'}',
                                  ),
                                );
                              }),
                            const SizedBox(height: 12),
                            Text(
                              'Statistiques par membre',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            if (_stats!.parMembre.isEmpty)
                              const Text(
                                  'Aucune présence enregistrée pour l’instant.')
                            else
                              ..._stats!.parMembre.map((entree) {
                                final presents = presentsStat(entree);
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(nomStatMembre(entree)),
                                  trailing: Text(
                                    '$presents '
                                    '${presents > 1 ? 'cultes' : 'culte'}',
                                  ),
                                );
                              }),
                          ],
                        ),
            ),
          ),
        ),
      ],
    );
  }
}
