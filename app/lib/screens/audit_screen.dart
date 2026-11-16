import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../models/parametres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// T11 — Journal d'audit : lecture seule, et lectures sensibles
/// journalisées (US17). Aucune route de suppression ou de
/// modification n'existe, côté serveur comme ici. La purge des
/// refus à 72 h est une décision serveur, pas un filtre de cet écran.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditEntree> _entrees = [];
  List<ConsultationSensible> _consultations = [];
  bool _chargement = true;
  String? _erreur;

  /// Pastille active (maquette, écran 15) : Toutes, Consultations,
  /// Authentification, Actions sensibles. Le filtre est côté écran :
  /// la route `/audit` ne filtre que sur une action exacte.
  String _pastille = 'toutes';

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
      final entrees = await api.getAudit();
      final consultations = await api.getConsultations();
      if (!mounted) return;
      setState(() {
        _entrees = entrees;
        _consultations = consultations;
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

  /// Entrées du journal visibles pour la pastille active.
  List<AuditEntree> get _entreesVisibles => switch (_pastille) {
        'auth' => _entrees
            .where((e) => e.action.startsWith('auth.'))
            .toList(),
        'sensibles' => _entrees
            .where((e) => !e.action.startsWith('auth.'))
            .toList(),
        _ => _entrees,
      };

  @override
  Widget build(BuildContext context) {
    // « Consultations » ne montre que les lectures sensibles, les
    // autres pastilles ne montrent que le journal.
    final montrerConsultations =
        _pastille == 'toutes' || _pastille == 'consultations';
    final montrerJournal = _pastille != 'consultations';
    final entrees = _entreesVisibles;
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d’audit')),
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in const <(String, String)>[
                          ('toutes', 'Toutes'),
                          ('consultations', 'Consultations'),
                          ('auth', 'Authentification'),
                          ('sensibles', 'Actions sensibles'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(entry.$2, style: const TextStyle(fontSize: 12.5)),
                              selected: _pastille == entry.$1,
                              onSelected: (_) =>
                                  setState(() => _pastille = entry.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (montrerJournal) ...[
                    const Text(
                      'Journal',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (entrees.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune ligne dans le journal.', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    for (final entree in entrees)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.orClair,
                            child: Icon(Icons.fact_check_outlined,
                                color: AppTheme.orFonce),
                          ),
                          title: Text(libelleActionAudit(entree.action), style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(
                            '${entree.utilisateur ?? '—'} · ${formatDateTime(entree.createdAt)}'
                            '${entree.hash == null ? '' : '\nHash : ${entree.hash!.substring(0, 12)}…'}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          isThreeLine: entree.hash != null,
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (montrerConsultations) ...[
                    const Text(
                      'Lectures sensibles',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_consultations.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune lecture sensible journalisée.', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    for (final consultation in _consultations)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.orClair,
                            child: Icon(Icons.visibility_outlined,
                                color: AppTheme.orFonce),
                          ),
                          title: Text(
                            '${consultation.ressourceLabel} · ${consultation.ressourceNom ?? '—'}',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            '${consultation.userNom ?? '—'} · ${formatDateTime(consultation.createdAt)}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
