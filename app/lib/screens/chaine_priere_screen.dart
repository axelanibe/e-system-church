import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/chaine_priere.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Chaîne de prière (lot 3d) : 24 créneaux d'une heure par jour, un
/// membre par créneau, un créneau par membre et par jour. Adapté de
/// Connexion Prophétique (maquette : carte hero, compteur des heures
/// couvertes, filtres par moment, créneaux Libre, Couvert ou Votre
/// créneau, badge « En cours », jours passés en lecture seule), avec
/// la palette violet/or d'e-System Church. Les prénoms viennent du
/// serveur, jamais inventés ; sans créneau pris, l'état vide est
/// explicite (« Aucune heure couverte pour ce jour. »).
///
/// Entrée dans l'application : 3e onglet de l'écran Prières
/// (Modules → Prières), une seule entrée par fonctionnalité.
class ChainePriereScreen extends StatelessWidget {
  const ChainePriereScreen({super.key, this.jourInitial});

  /// Jour affiché au départ, pour les tests, aujourd'hui sinon.
  final DateTime? jourInitial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chaîne de prière')),
      body: ChainePriereContenu(jourInitial: jourInitial),
    );
  }
}

/// Contenu de la chaîne, sans Scaffold : réutilisé par l'onglet
/// « Chaîne de prière » de l'écran Prières.
class ChainePriereContenu extends StatefulWidget {
  const ChainePriereContenu({super.key, this.jourInitial});

  /// Jour affiché au départ, pour les tests, aujourd'hui sinon.
  final DateTime? jourInitial;

  @override
  State<ChainePriereContenu> createState() => _ChainePriereContenuState();
}

class _ChainePriereContenuState extends State<ChainePriereContenu> {
  late DateTime _selection;
  ChainePriereJour? _jour;
  bool _charge = false;
  bool _enCours = false;
  MomentChaine? _filtre;

  String get _selectionIso => jourIsoChaine(_selection);

  @override
  void initState() {
    super.initState();
    _selection = jourSeulChaine(widget.jourInitial ?? DateTime.now());
    _charger();
  }

  Future<void> _charger() async {
    try {
      final jour = await context
          .read<AppState>()
          .api
          .getChainePriere(jour: _selectionIso);
      if (!mounted) return;
      setState(() {
        _jour = jour;
        _charge = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _charge = true);
      showApiError(context, e);
    }
  }

  void _changerJour(int jours) {
    setState(() {
      _selection = jourSeulChaine(_selection.add(Duration(days: jours)));
      _jour = null;
      _charge = false;
    });
    _charger();
  }

  Future<void> _prendre(CreneauPriere creneau) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prendre ce créneau ?'),
        content: Text(
          'Vous vous engagez à prier de ${creneau.heure} h à '
          '${(creneau.heure + 1) % 24} h, '
          '${libelleDateChaine(_selection)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Prendre'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _enCours = true);
    try {
      await context.read<AppState>().api.prendreCreneauPriere(
            heure: creneau.heure,
            jour: _selectionIso,
          );
      if (mounted) showSuccess(context, 'Créneau pris. Merci !');
      await _charger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _liberer(CreneauPriere creneau) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Libérer votre créneau ?'),
        content: Text(
          'Votre créneau de ${creneau.heure} h à '
          '${(creneau.heure + 1) % 24} h, '
          '${libelleDateChaine(_selection)}, redeviendra libre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Libérer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _enCours = true);
    try {
      await context.read<AppState>().api.libererCreneauPriere(
            heure: creneau.heure,
            jour: _selectionIso,
          );
      if (mounted) showSuccess(context, 'Créneau libéré.');
      await _charger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Widget _enTete(ChainePriereJour jour) {
    final aujourdHui = DateTime.tryParse(jour.aujourdHui) ?? DateTime.now();
    final estAujourdHui = jour.estAujourdHui;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.violetProfond,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                tooltip: 'Jour précédent',
                onPressed: () => _changerJour(-1),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      libelleDateChaine(_selection),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      libelleRelatifChaine(_selection, aujourdHui),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (!estAujourdHui)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selection = jourSeulChaine(aujourdHui);
                      _jour = null;
                      _charge = false;
                    });
                    _charger();
                  },
                  child: const Text(
                    'Aujourd’hui',
                    style: TextStyle(color: AppTheme.or),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                tooltip: 'Jour suivant',
                onPressed: () => _changerJour(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${jour.heuresCouvertes} / $nbCreneauxPriere heures couvertes',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: jour.heuresCouvertes / nbCreneauxPriere,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.or),
            ),
          ),
          const SizedBox(height: 8),
          if (jour.heuresCouvertes == 0)
            const Text(
              'Aucune heure couverte pour ce jour.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          if (jour.estPasse)
            const Text(
              'Jour passé — lecture seule.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _filtres() {
    const choix = <(String, MomentChaine?)>[
      ('Toutes', null),
      ('Nuit', MomentChaine.nuit),
      ('Matin', MomentChaine.matin),
      ('Après-midi', MomentChaine.apresMidi),
      ('Soir', MomentChaine.soir),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, moment) in choix)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filtre == moment,
                  onSelected: (_) => setState(() => _filtre = moment),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ligne(CreneauPriere creneau, ChainePriereJour jour) {
    final mien = creneau.estMien(jour.monMemberId);
    final enCours = jour.estAujourdHui && creneau.heure == DateTime.now().hour;
    final lectureSeule = jour.estPasse || _enCours;
    return Card(
      color: mien ? const Color(0xFFFFF7E0) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              mien ? AppTheme.or : AppTheme.violetProfond.withValues(alpha: 0.12),
          foregroundColor:
              mien ? AppTheme.violetProfond : AppTheme.violetProfond,
          child: creneau.estLibre
              ? const Icon(Icons.schedule_outlined)
              : Text(initialesDepuisPrenom(creneau.prenom)),
        ),
        title: Text(libelleCreneauPriere(creneau.heure)),
        subtitle: Text(
          creneau.estLibre
              ? 'Libre'
              : mien
                  ? 'Votre créneau'
                  : 'Couvert par ${creneau.prenom}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enCours)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Text(
                  'En cours',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            if (!creneau.estLibre && !mien)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: StatusChip(label: 'Couvert', color: AppTheme.vertFonce),
              ),
            if (creneau.estLibre && !lectureSeule)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(
                  key: Key('prendre-${creneau.heure}'),
                  onPressed: () => _prendre(creneau),
                  child: const Text('Prendre'),
                ),
              ),
            if (mien && !lectureSeule)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(
                  key: Key('liberer-${creneau.heure}'),
                  onPressed: () => _liberer(creneau),
                  child: const Text('Libérer'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) return const AppLoading();
    final jour = _jour;
    if (jour == null) {
      return AppError(
        message: 'Impossible de charger la chaîne de prière.',
        onRetry: _charger,
      );
    }
    final creneaux = creneauxFiltresChaine(jour.creneaux, _filtre);
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _enTete(jour),
          _filtres(),
          const SizedBox(height: 8),
          for (final creneau in creneaux)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _ligne(creneau, jour),
            ),
        ],
      ),
    );
  }
}
