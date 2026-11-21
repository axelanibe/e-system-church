import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/messagerie.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// File de modération de la messagerie (T-Msg-4, administrateur de
/// l'église seulement).
///
/// Liste des signalements avec filtres par motif et statut, détail
/// (contenu figé au moment du signalement, rapporteur, historique
/// des actions, recours), actions de modération avec note motivée
/// obligatoire (rejeter, avertir, sourdine, suspendre — durée pour
/// les deux dernières) et escalade vers l'église mère ou le référent
/// protection de l'enfance. Un signalement transmis par une église
/// fille est en lecture seule, sans nom de rapporteur.
class MessagerieModerationScreen extends StatefulWidget {
  const MessagerieModerationScreen({super.key});

  @override
  State<MessagerieModerationScreen> createState() =>
      _MessagerieModerationScreenState();
}

class _MessagerieModerationScreenState
    extends State<MessagerieModerationScreen> {
  List<Signalement> _signalements = [];
  bool _chargement = true;
  String? _erreur;
  String? _filtreStatut;
  String? _filtreMotif;

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
      final liste = await context.read<AppState>().api.getSignalementsModeration(
            statut: _filtreStatut,
            motif: _filtreMotif,
          );
      if (!mounted) return;
      setState(() {
        _signalements = liste;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.toString();
      });
    }
  }

  Future<void> _ouvrirDossier(Signalement signalement) async {
    final api = context.read<AppState>().api;
    Signalement detail = signalement;
    try {
      detail = await api.getSignalement(signalement.id);
    } catch (e) {
      if (mounted) showApiError(context, e);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FeuilleDossier(
        api: api,
        signalement: detail,
        onChange: _charger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modération'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: AppTheme.or),
        ),
      ),
      body: _chargement
          ? const AppLoading()
          : _erreur != null
              ? AppError(message: _erreur!, onRetry: _charger)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _filtreStatut,
                              decoration: const InputDecoration(
                                labelText: 'Statut',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    'Tous les statuts',
                                    style: TextStyle(fontSize: 13.5),
                                  ),
                                ),
                                for (final statut in [
                                  'pending',
                                  'in_review',
                                  'resolved',
                                  'dismissed',
                                  'escalated',
                                  'appealed',
                                ])
                                  DropdownMenuItem<String?>(
                                    value: statut,
                                    child: Text(
                                      libelleStatutSignalement(statut),
                                      style: const TextStyle(fontSize: 13.5),
                                    ),
                                  ),
                              ],
                              onChanged: (valeur) {
                                setState(() => _filtreStatut = valeur);
                                _charger();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _filtreMotif,
                              decoration: const InputDecoration(
                                labelText: 'Motif',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    'Tous les motifs',
                                    style: TextStyle(fontSize: 13.5),
                                  ),
                                ),
                                for (final motif in motifsSignalement)
                                  DropdownMenuItem<String?>(
                                    value: motif,
                                    child: Text(
                                      libelleMotifSignalement(motif),
                                      style: const TextStyle(fontSize: 13.5),
                                    ),
                                  ),
                              ],
                              onChanged: (valeur) {
                                setState(() => _filtreMotif = valeur);
                                _charger();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _signalements.isEmpty
                          ? const EmptyState(
                              icon: Icons.shield_outlined,
                              message:
                                  'Aucun signalement dans cette file.',
                            )
                          : RefreshIndicator(
                              onRefresh: _charger,
                              child: ListView.separated(
                                itemCount: _signalements.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final signalement = _signalements[index];
                                  return _TuileSignalement(
                                    signalement: signalement,
                                    onTap: () =>
                                        _ouvrirDossier(signalement),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// Une ligne de la file : motif, statut, date, rapporteur, aperçu
/// du contenu figé.
class _TuileSignalement extends StatelessWidget {
  const _TuileSignalement({required this.signalement, required this.onTap});

  final Signalement signalement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rapporteur = signalement.rapporteurNom ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.violetProfond,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    libelleMotifSignalement(signalement.motif),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.or,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    libelleStatutSignalement(signalement.statut),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.violetProfond,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  heureCourteConversation(signalement.createdAt),
                  style: const TextStyle(fontSize: 12, color: AppTheme.orFonce),
                ),
              ],
            ),
            if (signalement.evidenceContenu.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                signalement.evidenceContenu,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            if (rapporteur.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Signalé par $rapporteur',
                style: const TextStyle(fontSize: 12, color: AppTheme.orFonce),
              ),
            ],
            if (signalement.escalade) ...[
              const SizedBox(height: 4),
              const Text(
                'Transmis par une église fille (lecture seule).',
                style: TextStyle(fontSize: 12, color: AppTheme.orFonce),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dossier de modération : contexte figé, actions avec note
/// obligatoire, escalade, recours visibles.
class _FeuilleDossier extends StatefulWidget {
  final ApiService api;
  final Signalement signalement;
  final VoidCallback onChange;

  const _FeuilleDossier({
    required this.api,
    required this.signalement,
    required this.onChange,
  });

  @override
  State<_FeuilleDossier> createState() => _FeuilleDossierState();
}

class _FeuilleDossierState extends State<_FeuilleDossier> {
  String _action = 'avertir';
  int _dureeHeures = 24;
  final _noteController = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _dureeRequise => _action == 'sourdine' || _action == 'suspendre';

  bool get _modifiable =>
      (widget.signalement.statut == 'pending' ||
          widget.signalement.statut == 'in_review') &&
      !widget.signalement.escalade;

  bool get _valide => _noteController.text.trim().isNotEmpty;

  Future<void> _appliquer() async {
    if (!_valide || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.api.traiterSignalement(
        widget.signalement.id,
        action: _action,
        dureeHeures: _dureeRequise ? _dureeHeures : null,
        notes: _noteController.text.trim(),
      );
      if (!mounted) return;
      widget.onChange();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décision enregistrée.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = e.toString();
        });
      }
    }
  }

  Future<void> _escalader(String destination) async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.api.escaladerSignalement(
        widget.signalement.id,
        destination: destination,
      );
      if (!mounted) return;
      widget.onChange();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement transmis.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = e.toString();
        });
      }
    }
  }

  Future<void> _traiterRecours(RecoursMessagerie recours, String statut) async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.api.traiterRecours(recours.id, statut: statut);
      if (!mounted) return;
      widget.onChange();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recours traité.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.signalement;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              libelleMotifSignalement(s.motif),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Signalé le ${heureCourteConversation(s.createdAt)} · ${libelleStatutSignalement(s.statut)}',
              style: const TextStyle(fontSize: 13, color: AppTheme.orFonce),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.fondPapier,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.bordure),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contenu figé au moment du signalement',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.orFonce,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.evidenceContenu.isNotEmpty
                        ? s.evidenceContenu
                        : 'Contenu non disponible.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (s.evidenceAuteur.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Auteur : ${s.evidenceAuteur} · ${heureCourteConversation(s.evidenceDate)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.orFonce,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (s.description != null && s.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Description du rapporteur : ${s.description!}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if ((s.rapporteurNom ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Signalé par ${s.rapporteurNom!}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (s.resolutionNotes != null && s.resolutionNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Décision : ${s.resolutionNotes!}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (s.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Actions de modération',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              for (final action in s.actions) ...[
                const SizedBox(height: 4),
                Text(
                  '· ${libelleActionModeration(action.action)} — ${action.notes ?? ''} (${heureCourteConversation(action.date)})',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
            if (s.recours.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Recours',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              for (final recours in s.recours) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '· ${recours.motif ?? 'Recours'} — ${recours.enCours ? 'en attente' : recours.statut}'
                        '${recours.repondreAvant != null ? ' · réponse avant le ${heureCourteConversation(recours.repondreAvant)}' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (recours.enCours && !_modifiable) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _enCours
                            ? null
                            : () => _traiterRecours(recours, 'resolved'),
                        child: const Text('Accepter'),
                      ),
                      TextButton(
                        onPressed: _enCours
                            ? null
                            : () => _traiterRecours(recours, 'dismissed'),
                        child: const Text('Rejeter'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
            if (_modifiable) ...[
              const SizedBox(height: 16),
              const Text(
                'Décision de modération',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _action,
                decoration: const InputDecoration(
                  labelText: 'Action *',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: [
                  for (final action in actionsModeration)
                    DropdownMenuItem<String>(
                      value: action,
                      child: Text(
                        libelleActionModeration(action),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (valeur) =>
                    setState(() => _action = valeur ?? 'avertir'),
              ),
              if (_dureeRequise) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _dureeHeures,
                  decoration: const InputDecoration(
                    labelText: 'Durée *',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: [
                    for (final duree in dureesModerationHeures)
                      DropdownMenuItem<int>(
                        value: duree,
                        child: Text(
                          libelleDureeModeration(duree),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                  onChanged: (valeur) =>
                      setState(() => _dureeHeures = valeur ?? 24),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note motivée *',
                  hintText: 'Pourquoi cette décision ?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_valide && !_enCours) ? _appliquer : null,
                  child: const Text('Appliquer la décision'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _enCours ? null : () => _escalader('mother'),
                      child: const Text('Transmettre à l’église mère'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _enCours
                          ? null
                          : () => _escalader('child_safety_referent'),
                      child: const Text('Transmettre au référent'),
                    ),
                  ),
                ],
              ),
            ],
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(
                _erreur!,
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
