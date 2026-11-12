import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Prendre rendez-vous (tranche P4) : demande auprès du pasteur de
/// son église. Date souhaitée, créneau à compléter, motif. Aucun
/// pasteur nommé, aucun créneau inventé : les créneaux du pasteur
/// s'afficheront ici quand ils seront définis.
class RendezVousScreen extends StatefulWidget {
  const RendezVousScreen({super.key});

  @override
  State<RendezVousScreen> createState() => _RendezVousScreenState();
}

class _RendezVousScreenState extends State<RendezVousScreen> {
  final _motifController = TextEditingController();
  DateTime? _date;
  var _envoi = false;
  var _envoye = false;

  @override
  void dispose() {
    _motifController.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date ?? maintenant,
      firstDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      lastDate:
          DateTime(maintenant.year + 1, maintenant.month, maintenant.day),
    );
    if (choisie != null) setState(() => _date = choisie);
  }

  String get _dateTexte {
    if (_date == null) return 'Choisir une date';
    return formatDateSeule(_date);
  }

  Future<void> _demander() async {
    final apercu = context.read<AppState>().apercuFidele;
    if (apercu) {
      showApiError(
        context,
        'Connectez-vous avec un compte fidèle pour demander '
        'un rendez-vous.',
      );
      return;
    }
    if (_date == null) {
      showApiError(context, 'Choisissez une date souhaitée.');
      return;
    }
    final motif = _motifController.text.trim();
    if (motif.length < 2) {
      showApiError(context, 'Écrivez le motif de votre rendez-vous.');
      return;
    }
    setState(() => _envoi = true);
    try {
      final date = _date!;
      final iso =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await context.read<AppState>().api.demanderRendezVous(
            dateSouhaitee: iso,
            motif: motif,
          );
      if (!mounted) return;
      setState(() => _envoye = true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _nouvelleDemande() {
    setState(() {
      _envoye = false;
      _date = null;
      _motifController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prendre rendez-vous')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Retour au menu'),
                  ),
                ),
                const Text(
                  'Demandez un rendez-vous auprès de votre pasteur local.',
                ),
                const SizedBox(height: 16),
                if (_envoye) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                color: AppTheme.orFonce,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Demande envoyée à votre pasteur',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Votre pasteur recevra votre demande dans '
                            'son espace.',
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _nouvelleDemande,
                            child: const Text('Faire une autre demande'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SectionTitle(title: 'Votre pasteur'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Le rendez-vous se fait avec le pasteur de '
                          'votre église.',
                        ),
                        SizedBox(height: 12),
                        Chip(label: Text('Pasteur de mon église')),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Date et créneau'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Date souhaitée'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _choisirDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(_dateTexte),
                        ),
                        const SizedBox(height: 12),
                        const Text('Créneau'),
                        const SizedBox(height: 8),
                        const Chip(label: Text('À compléter')),
                        const SizedBox(height: 8),
                        const Text(
                          'Les créneaux de votre pasteur s’afficheront ici.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Motif du rendez-vous'),
                TextField(
                  controller: _motifController,
                  decoration: const InputDecoration(
                    labelText: 'Motif du rendez-vous',
                    hintText: 'Motif du rendez-vous',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                if (!_envoye)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _envoi ? null : _demander,
                      child: Text(
                        _envoi ? 'Envoi…' : 'Demander ce rendez-vous',
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Tu es un don de Dieu',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.orFonce,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
