import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bible.dart';
import '../models/ecole_biblique.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'concordance_screen.dart';
import 'dictionnaire_screen.dart';
import 'ecole_biblique_screen.dart';

/// Ma Bible (tranches P1 + T9) : lecture de la Bible en deux versions
/// (Louis Segond 1910, français, par défaut ; King James Version,
/// anglais), canon complet des 66 livres, chapitres, versets numérotés
/// et recherche plein texte sur la version active. Le texte vient de
/// l'API (mode réel) ou des assets bundlés (mode démo) ; il n'est
/// jamais inventé. La concordance Strong et le dictionnaire biblique
/// sont accessibles depuis cet écran (la langue du dictionnaire suit
/// celle de la version choisie).
class BibleFideleScreen extends StatefulWidget {
  const BibleFideleScreen({super.key});

  @override
  State<BibleFideleScreen> createState() => _BibleFideleScreenState();
}

class _BibleFideleScreenState extends State<BibleFideleScreen> {
  int _testament = 0; // 0 = Ancien, 1 = Nouveau
  String _version = 'lsg1910';
  String _rechercheLivre = '';
  String _rechercheTexte = '';
  LivreBible? _livreChoisi;
  int _chapitreChoisi = 1;
  bool _modeRecherche = false;

  final _rechercheLivreController = TextEditingController();
  final _rechercheTexteController = TextEditingController();

  late Future<List<VersionBible>> _versionsFuture;
  late Future<List<LivreBible>> _livresFuture;
  Future<ChapitreBible>? _chapitreFuture;
  Future<List<ResultatRechercheBible>>? _resultatsFuture;

  /// École biblique (maquette, écran 40) : cours et progression sous
  /// la lecture, mêmes sources que l'écran École biblique.
  late Future<List<CoursEcole>> _coursFuture;
  late Future<List<ProgressionCours>> _progressionsFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _versionsFuture = api.getVersionsBible();
    _livresFuture = _chargerLivres();
    _coursFuture = api.getCoursEcole();
    _progressionsFuture = api.getInscriptionsEcole().then(
      (inscriptions) => Future.wait(
          inscriptions.map((i) => api.getProgressionEcole(i.id))),
    );
  }

  Future<List<LivreBible>> _chargerLivres() =>
      context.read<AppState>().api.getLivresBible(version: _version);

  @override
  void dispose() {
    _rechercheLivreController.dispose();
    _rechercheTexteController.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<AppState>().api;

  void _choisirVersion(String version) {
    if (version == _version) return;
    setState(() {
      _version = version;
      _livreChoisi = null;
      _chapitreFuture = null;
      _resultatsFuture = null;
      _modeRecherche = false;
      _livresFuture = _chargerLivres();
    });
  }

  void _choisirLivre(LivreBible livre) {
    setState(() {
      _livreChoisi = livre;
      _chapitreChoisi = 1;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: livre.code, chapitre: 1, version: _version);
    });
  }

  void _choisirChapitre(int chapitre) {
    final livre = _livreChoisi;
    if (livre == null) return;
    setState(() {
      _chapitreChoisi = chapitre;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: livre.code, chapitre: chapitre, version: _version);
    });
  }

  void _lancerRechercheTexte() {
    final q = _rechercheTexte.trim();
    if (q.length < 2) return;
    setState(() {
      _modeRecherche = true;
      _resultatsFuture = _api.rechercherBible(q, version: _version);
    });
  }

  /// Langue du dictionnaire : celle de la version choisie.
  String get _langueDictionnaire => _version == 'kjv' ? 'eng' : 'fra';

  void _ouvrirConcordance() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConcordanceScreen()),
    );
  }

  void _ouvrirDictionnaire() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              DictionnaireScreen(langue: _langueDictionnaire)),
    );
  }

  Future<void> _ouvrirResultat(ResultatRechercheBible resultat) async {
    // Le nombre de chapitres du livre vient du canon déjà chargé :
    // sinon les pastilles de chapitres seraient vides après une recherche.
    final livres = await _livresFuture;
    final livre = livres.firstWhere(
      (l) => l.code == resultat.code,
      orElse: () => LivreBible(
        code: resultat.code,
        nom: resultat.livre,
        testament: '',
        chapitres: 0,
      ),
    );
    if (!mounted) return;
    setState(() {
      _livreChoisi = livre;
      _chapitreChoisi = resultat.chapitre;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: resultat.code, chapitre: resultat.chapitre, version: _version);
    });
  }

  List<LivreBible> _livresVisibles(List<LivreBible> livres) {
    final testament = _testament == 0 ? 'ancien' : 'nouveau';
    var liste = livres.where((l) => l.testament == testament).toList();
    final q = _rechercheLivre.trim().toLowerCase();
    if (q.isNotEmpty) {
      liste = liste.where((l) => l.nom.toLowerCase().contains(q)).toList();
    }
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lisez, cherchez un passage, puis choisissez un livre '
                  'et un chapitre. Deux versions : Louis Segond 1910 '
                  '(français) et King James Version (anglais).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<VersionBible>>(
                  future: _versionsFuture,
                  builder: (context, snapshot) {
                    final versions = snapshot.data ?? const <VersionBible>[];
                    if (versions.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return SegmentedButton<String>(
                      style: SegmentedButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 12.5)),
                      segments: versions
                          .map((v) => ButtonSegment(
                                value: v.id,
                                label: Text(v.id == 'kjv'
                                    ? 'King James'
                                    : 'Louis Segond 1910'),
                              ))
                          .toList(),
                      selected: {_version},
                      onSelectionChanged: (s) =>
                          _choisirVersion(s.first),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _ouvrirConcordance,
                        icon: const Icon(Icons.translate_outlined),
                        label: const Text('Concordance Strong', style: TextStyle(fontSize: 13.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _ouvrirDictionnaire,
                        icon: const Icon(Icons.book_outlined),
                        label: const Text('Dictionnaire', style: TextStyle(fontSize: 13.5)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _rechercheTexteController,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher un livre ou un passage',
                    prefixIcon: Icon(Icons.search),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => _rechercheTexte = v,
                  onSubmitted: (_) => _lancerRechercheTexte(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _lancerRechercheTexte,
                    icon: const Icon(Icons.search),
                    label: const Text('Rechercher', style: TextStyle(fontSize: 13.5)),
                  ),
                ),
                const SizedBox(height: 16),
                if (_modeRecherche) _resultatsRecherche(),
                if (!_modeRecherche) ...[
                  SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 12.5)),
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Ancien Testament'),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Nouveau Testament'),
                      ),
                    ],
                    selected: {_testament},
                    onSelectionChanged: (s) => setState(() {
                      _testament = s.first;
                      _livreChoisi = null;
                      _chapitreFuture = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rechercheLivreController,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher un livre',
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                    onChanged: (v) => setState(() => _rechercheLivre = v),
                  ),
                  const SizedBox(height: 16),
                  const SectionTitle(title: 'Liste des livres'),
                  FutureBuilder<List<LivreBible>>(
                    future: _livresFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          message:
                              'Impossible de charger la Bible : ${snapshot.error}',
                        );
                      }
                      final livres = _livresVisibles(snapshot.data ?? []);
                      if (livres.isEmpty) {
                        return const EmptyState(
                          icon: Icons.menu_book_outlined,
                          message: 'Aucun livre avec ce nom.',
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: livres
                            .map((livre) => ChoiceChip(
                                  label: Text(livre.nom, style: const TextStyle(fontSize: 12.5)),
                                  selected:
                                      _livreChoisi?.code == livre.code,
                                  onSelected: (_) => _choisirLivre(livre),
                                ))
                            .toList(),
                      );
                    },
                  ),
                  if (_livreChoisi != null) ...[
                    const SizedBox(height: 16),
                    SectionTitle(
                        title:
                            '${_livreChoisi!.nom} — chapitre $_chapitreChoisi'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(
                        _livreChoisi!.chapitres,
                        (i) => ChoiceChip(
                          label: Text('${i + 1}', style: const TextStyle(fontSize: 12.5)),
                          selected: _chapitreChoisi == i + 1,
                          onSelected: (_) => _choisirChapitre(i + 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _chapitre(),
                  ],
                ],
                const SizedBox(height: 24),
                const SectionTitle(title: 'École biblique, cours', taille: 15),
                _EcoleCoursSection(future: _coursFuture),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Ma progression', taille: 15),
                _MaProgressionBible(future: _progressionsFuture),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultatsRecherche() {
    return FutureBuilder<List<ResultatRechercheBible>>(
      future: _resultatsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: 'Recherche impossible : ${snapshot.error}',
          );
        }
        final resultats = snapshot.data ?? [];
        if (resultats.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_outlined,
            message: 'Aucun passage trouvé.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title: '${resultats.length} passage(s) trouvé(s)'),
            const SizedBox(height: 8),
            ...resultats.map((r) => Card(
                  child: ListTile(
                    title: Text(
                      r.texte,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(r.reference, style: const TextStyle(fontSize: 11.5)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrirResultat(r),
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _chapitre() {
    final future = _chapitreFuture;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<ChapitreBible>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: 'Impossible de charger ce chapitre : ${snapshot.error}',
          );
        }
        final chapitre = snapshot.data;
        if (chapitre == null) {
          return const EmptyState(
            icon: Icons.menu_book_outlined,
            message: 'Chapitre introuvable.',
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: chapitre.versets
                  .map((v) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyLarge,
                            children: [
                              TextSpan(
                                text: '${v.numero} ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                              ),
                              TextSpan(text: v.texte),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

/// École biblique, cours (maquette, écran 40) : cours publiés par la
/// structure, leçon par leçon. Même source que l'écran École
/// biblique ; un cours s'ouvre sur son détail.
class _EcoleCoursSection extends StatelessWidget {
  final Future<List<CoursEcole>> future;

  const _EcoleCoursSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CoursEcole>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const EmptyState(
            icon: Icons.school_outlined,
            message: 'Cours indisponibles.',
          );
        }
        final cours = snapshot.data ?? const <CoursEcole>[];
        if (cours.isEmpty) {
          return const EmptyState(
            icon: Icons.school_outlined,
            message: 'Aucun cours publié. Les cours créés par la structure '
                'apparaîtront ici, leçon par leçon.',
          );
        }
        return Column(
          children: [
            for (final c in cours)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(c.titre, style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(c.niveauLabel, style: const TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EcoleCoursDetailScreen(cours: c),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EcoleBibliqueScreen(),
                ),
              ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('Ouvrir l’école biblique', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        );
      },
    );
  }
}

/// Ma progression (maquette, écran 40) : agrégat réel des
/// progressions des cours du membre connecté (leçons terminées /
/// total, %). Sans inscription : 0 % / 0 leçon sur 0.
class _MaProgressionBible extends StatelessWidget {
  final Future<List<ProgressionCours>> future;

  const _MaProgressionBible({required this.future});

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().apercuFidele) {
      return const EmptyState(
        icon: Icons.school_outlined,
        message: 'En aperçu, la progression d’un membre n’est pas visible. '
            'Connectez-vous avec un compte fidèle pour suivre votre '
            'progression.',
      );
    }
    return FutureBuilder<List<ProgressionCours>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: 'Progression indisponible : ${snapshot.error}',
          );
        }
        final progressions = snapshot.data ?? const <ProgressionCours>[];
        final total =
            progressions.fold<int>(0, (somme, p) => somme + p.total);
        final terminees =
            progressions.fold<int>(0, (somme, p) => somme + p.terminees);
        final pourcentage =
            total == 0 ? 0 : (terminees * 100 / total).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
                value: total == 0 ? 0 : terminees / total),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$pourcentage %',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: ' — $terminees leçon(s) terminée(s) sur $total.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
