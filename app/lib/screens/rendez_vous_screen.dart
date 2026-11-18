import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../models/profil.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Prendre rendez-vous (tranche P4) : demande auprès du pasteur de
/// son église. Date souhaitée, créneau à compléter, motif. Nom du
/// pasteur affiché quand la présentation de l'église le fournit,
/// sinon le libellé seul, aucun nom inventé ; les créneaux du pasteur
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
  late Future<List<CreneauPasteur>> _creneauxFuture;
  Future<ProfilEglise>? _presentationFuture;
  String? _periodeChoisie;
  String? _creneauChoisi;

  @override
  void initState() {
    super.initState();
    _creneauxFuture = context.read<AppState>().api.getMesCreneaux();
    // Nom du pasteur : présentation publique de mon église
    // (pasteur_principal). Sans église, le libellé seul s'affiche.
    final code = context.read<AppState>().church?.code;
    _presentationFuture = code == null
        ? null
        : context.read<AppState>().api.getPresentation(code);
  }

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
    final appState = context.read<AppState>();

    if (_date == null) {
      if (!mounted) return;
      showApiError(context, 'Choisissez une date souhaitée.');
      return;
    }

    final creneaux = await _creneauxFuture;

    if (creneaux.where((c) => c.actif).isNotEmpty && _creneauChoisi == null) {
      if (!mounted) return;
      showApiError(context, 'Choisissez un créneau proposé par votre église.');
      return;
    }

    final motif = _motifController.text.trim();
    if (motif.length < 2) {
      if (!mounted) return;
      showApiError(context, 'Écrivez le motif de votre rendez-vous.');
      return;
    }

    setState(() => _envoi = true);

    try {
      final date = _date!;
      final iso =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      await appState.api.demanderRendezVous(
        dateSouhaitee: iso,
        creneau: _creneauChoisi,
        motif: motif,
      );

      if (!mounted) return;
      setState(() => _envoye = true);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _nouvelleDemande() {
    setState(() {
      _envoye = false;
      _date = null;
      _periodeChoisie = null;
      _creneauChoisi = null;
      _motifController.clear();
    });
  }

  /// Créneaux du pasteur (E-RV1) : rien tant qu'il n'a rien défini,
  /// sinon puces de période puis libellés de la période choisie.
  Widget _creneaux() {
    return FutureBuilder<List<CreneauPasteur>>(
      future: _creneauxFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        final creneaux = snapshot.data ?? const <CreneauPasteur>[];
        if (creneaux.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('À compléter', style: TextStyle(fontSize: 15)),
              SizedBox(height: 4),
              Text('Les créneaux de votre pasteur s’afficheront ici.', style: TextStyle(fontSize: 11.5)),
            ],
          );
        }
        const periodes = {
          'matin': 'Matin',
          'apres-midi': 'Après-midi',
          'soir': 'Soir',
        };
        final presentes = [
          for (final p in periodes.keys)
            if (creneaux.any((c) => c.periode == p)) p,
        ];
        final periode = _periodeChoisie ?? presentes.first;
        final libelles = [
          for (final c in creneaux.where((c) => c.periode == periode))
            c.libelle,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Un rendez-vous ne se confirme qu’avec un créneau proposé par l’église : le membre choisit parmi les créneaux, il ne réserve pas librement.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final p in presentes)
                  ChoiceChip(
                    label: Text(periodes[p]!, style: const TextStyle(fontSize: 12.5)),
                    selected: periode == p,
                    onSelected: (_) => setState(() {
                      _periodeChoisie = p;
                      _creneauChoisi = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final libelle in libelles)
                  ChoiceChip(
                    label: Text(libelle, style: const TextStyle(fontSize: 12.5)),
                    selected: _creneauChoisi == libelle,
                    onSelected: (_) => setState(() {
                      _creneauChoisi =
                          _creneauChoisi == libelle ? null : libelle;
                    }),
                  ),
              ],
            ),
          ],
        );
      },
    );
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
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text(
                      'Retour au menu',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
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
                            child: const Text('Faire une autre demande', style: TextStyle(fontSize: 13.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SectionTitle(title: 'Votre pasteur'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<ProfilEglise>(
                      future: _presentationFuture,
                      builder: (context, snapshot) {
                        final nom = snapshot.data?.pasteurPrincipal;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pasteur de mon église',
                              style: TextStyle(fontSize: 15),
                            ),
                            if (nom != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                nom,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                            ],
                          ],
                        );
                      },
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
                        const Text('Date souhaitée', style: TextStyle(fontSize: 10.5)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _choisirDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(_dateTexte, style: const TextStyle(fontSize: 13.5)),
                        ),
                        const SizedBox(height: 12),
                        const Text('Créneau', style: TextStyle(fontSize: 10.5)),
                        const SizedBox(height: 8),
                        _creneaux(),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Motif du rendez-vous'),
                TextField(
                  controller: _motifController,
                  decoration: const InputDecoration(
                    labelText: 'Motif du rendez-vous',
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
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Tu es un don de Dieu',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.orFonce,
                          fontSize: 12.5,
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
