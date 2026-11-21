import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/messagerie.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Mes sanctions (T-Msg-4) : les actions de modération qui me
/// concernent, avec le délai de recours (15 jours pour contester).
/// L'identité du rapporteur n'y figure jamais. Un recours accepté
/// annule la sanction ; le modérateur a 30 jours pour répondre.
class MesSanctionsScreen extends StatefulWidget {
  const MesSanctionsScreen({super.key});

  @override
  State<MesSanctionsScreen> createState() => _MesSanctionsScreenState();
}

class _MesSanctionsScreenState extends State<MesSanctionsScreen> {
  List<SanctionMessagerie> _sanctions = [];
  bool _chargement = true;
  String? _erreur;

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
      final liste = await context.read<AppState>().api.getMesSanctions();
      if (!mounted) return;
      setState(() {
        _sanctions = liste;
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

  Future<void> _contester(SanctionMessagerie sanction) async {
    final api = context.read<AppState>().api;
    final motifController = TextEditingController();
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contester cette sanction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Vous avez ${sanction.joursRestants} jour${sanction.joursRestants > 1 ? 's' : ''} pour contester. '
              'Le modérateur a $delaiReponseRecoursJours jours pour répondre.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motifController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Pourquoi contestez-vous ? (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Envoyer le recours'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    try {
      await api.contesterSanction(
        sanction.signalementId,
        moderationActionId: sanction.id,
        motif: motifController.text.trim().isEmpty
            ? null
            : motifController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recours envoyé.')),
      );
      _charger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes sanctions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: AppTheme.or),
        ),
      ),
      body: _chargement
          ? const AppLoading()
          : _erreur != null
              ? AppError(message: _erreur!, onRetry: _charger)
              : _sanctions.isEmpty
                  ? const EmptyState(
                      icon: Icons.gavel_outlined,
                      message: 'Aucune sanction ne vous concerne.',
                    )
                  : RefreshIndicator(
                      onRefresh: _charger,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _sanctions.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sanction = _sanctions[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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
                                        libelleActionModeration(
                                          sanction.action,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      heureCourteConversation(sanction.date),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.orFonce,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((sanction.notes ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    sanction.notes!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  sanction.appelEnCours
                                      ? 'Recours en cours — réponse du modérateur sous $delaiReponseRecoursJours jours.'
                                      : sanction.contestable
                                          ? 'Vous pouvez contester pendant encore ${sanction.joursRestants} jour${sanction.joursRestants > 1 ? 's' : ''}.'
                                          : 'Le délai de recours de $delaiRecoursJours jours est dépassé.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.orFonce,
                                  ),
                                ),
                                if (sanction.contestable &&
                                    !sanction.appelEnCours) ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed: () => _contester(sanction),
                                    child: const Text('Contester'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
