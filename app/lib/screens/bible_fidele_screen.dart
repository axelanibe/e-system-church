import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bible.dart';
import '../models/ecole_biblique.dart';
import '../services/api_service.dart';
import '../services/preferences_locales.dart';
import '../services/verset_du_jour.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/progression_ecole.dart';
import 'concordance_screen.dart';
import 'dictionnaire_screen.dart';
import 'ecole_biblique_screen.dart';

/// Ma Bible (tranches P1 + T9, refonte design écran 40) : trois cartes
/// distinctes sur fond clair, lecture d'abord, école ensuite,
/// progression ensuite. La carte Lecture porte seule la lecture :
/// recherche de passages à un seul métier, sélecteurs Livre et
/// Chapitre côte à côte, texte du chapitre dans la même carte avec
/// précédent et suivant. Le texte vient de l'API (mode réel) ou des
/// assets bundlés (mode démo) ; il n'est jamais inventé.
class BibleFideleScreen extends StatefulWidget {
  const BibleFideleScreen({super.key});

  @override
  State<BibleFideleScreen> createState() => _BibleFideleScreenState();
}

class _BibleFideleScreenState extends State<BibleFideleScreen> {
  int _testament = 0; // 0 = Ancien, 1 = Nouveau (filtre du sélecteur seul)
  String _version = 'lsg1910';
  String _rechercheTexte = '';
  LivreBible? _livreChoisi;
  int _chapitreChoisi = 1;
  bool _modeRecherche = false;

  final _rechercheTexteController = TextEditingController();
  final _defilement = ScrollController();
  final _cleTexte = GlobalKey();

  late Future<List<VersionBible>> _versionsFuture;
  late Future<List<LivreBible>> _livresFuture;
  Future<ChapitreBible>? _chapitreFuture;
  Future<List<ResultatRechercheBible>>? _resultatsFuture;
  late Future<VersetDuJour> _versetFuture;

  /// École et progression : un seul chargement par carte, mêmes
  /// sources que l'écran École biblique, sans recopier sa liste ni
  /// son widget de progression (voir ProgressionEcole partagé).
  late Future<List<CoursEcole>> _coursFuture;
  late Future<List<ProgressionCours>> _progressionsFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _versionsFuture = api.getVersionsBible();
    _livresFuture = _chargerLivres();
    _versetFuture = chargerVersetDuJour(api, version: _version);
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
    _rechercheTexteController.dispose();
    _defilement.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<AppState>().api;

  /// Mémorise la position de lecture en cours pour la carte
  /// « Reprendre ma lecture ». Sans livre ouvert, rien à mémoriser.
  void _memoriserLecture() {
    final livre = _livreChoisi;
    if (livre == null) return;
    context.read<PreferencesLocales>().definirLecture(
        code: livre.code, chapitre: _chapitreChoisi, version: _version);
  }

  /// Changer de version garde le livre et le chapitre quand le canon
  /// est le même (les deux versions ont les 66 livres) : la position
  /// de lecture est conservée, seul le texte est rechargé.
  void _choisirVersion(String version) {
    if (version == _version) return;
    final code = _livreChoisi?.code;
    final chapitre = _chapitreChoisi;
    setState(() {
      _version = version;
      _livresFuture = _chargerLivres();
      _versetFuture = chargerVersetDuJour(_api, version: version);
    });
    if (code == null) return;
    _livresFuture.then((livres) {
      if (!mounted) return;
      LivreBible? livreTrouve;
      for (final l in livres) {
        if (l.code == code) livreTrouve = l;
      }
      if (livreTrouve == null) return;
      final livre = livreTrouve;
      final chapitreGarde = chapitre.clamp(1, livre.chapitres);
      setState(() {
        _livreChoisi = livre;
        _chapitreChoisi = chapitreGarde;
        _chapitreFuture = _api.getChapitreBible(
            code: livre.code, chapitre: chapitreGarde, version: _version);
      });
      _memoriserLecture();
      _defilerVersTexte();
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
    _memoriserLecture();
    _defilerVersTexte();
  }

  void _choisirChapitre(int chapitre, {bool defiler = true}) {
    final livre = _livreChoisi;
    if (livre == null) return;
    final garde = chapitre.clamp(1, livre.chapitres);
    setState(() {
      _chapitreChoisi = garde;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: livre.code, chapitre: garde, version: _version);
    });
    _memoriserLecture();
    // Précédent, Suivant et grille ne défilent pas : le membre est
    // déjà en train de lire ce passage, un défilement animé à chaque
    // changement avalerait le tap suivant. Le défilement reste pour
    // les choix par dialogue (livre, numéro de chapitre).
    if (defiler) _defilerVersTexte();
  }

  /// Reprendre la dernière position lue : la version mémorisée est
  /// restaurée avec le livre et le chapitre, puis le texte est
  /// rechargé dans cette version.
  Future<void> _reprendreLecture(PositionLecture position) async {
    setState(() {
      _version = position.version;
      _livresFuture = _chargerLivres();
      _versetFuture =
          chargerVersetDuJour(_api, version: position.version);
    });
    final livres = await _livresFuture;
    if (!mounted) return;
    LivreBible? livreTrouve;
    for (final l in livres) {
      if (l.code == position.code) livreTrouve = l;
    }
    if (livreTrouve == null) return;
    final livre = livreTrouve;
    final chapitreGarde = position.chapitre.clamp(1, livre.chapitres);
    setState(() {
      _livreChoisi = livre;
      _chapitreChoisi = chapitreGarde;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: livre.code, chapitre: chapitreGarde, version: _version);
    });
    _memoriserLecture();
    _defilerVersTexte();
  }

  /// Ouvrir le passage du verset du jour dans la version en cours.
  Future<void> _ouvrirVerset(VersetDuJour verset) async {
    final livres = await _livresFuture;
    if (!mounted) return;
    LivreBible? livreTrouve;
    for (final l in livres) {
      if (l.code == verset.code) livreTrouve = l;
    }
    if (livreTrouve == null) return;
    final livre = livreTrouve;
    final chapitreGarde = verset.chapitre.clamp(1, livre.chapitres);
    setState(() {
      _livreChoisi = livre;
      _chapitreChoisi = chapitreGarde;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: livre.code, chapitre: chapitreGarde, version: _version);
    });
    _memoriserLecture();
    _defilerVersTexte();
  }

  void _chapitrePrecedent() =>
      _choisirChapitre(_chapitreChoisi - 1, defiler: false);

  void _chapitreSuivant() =>
      _choisirChapitre(_chapitreChoisi + 1, defiler: false);

  void _defilerVersTexte() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexte = _cleTexte.currentContext;
      if (contexte != null && mounted) {
        Scrollable.ensureVisible(contexte,
            duration: const Duration(milliseconds: 300), alignment: 0.0);
      }
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
          builder: (_) => DictionnaireScreen(langue: _langueDictionnaire)),
    );
  }

  Future<void> _ouvrirResultat(ResultatRechercheBible resultat) async {
    final livres = await _livresFuture;
    LivreBible? livre;
    for (final l in livres) {
      if (l.code == resultat.code) livre = l;
    }
    livre ??= LivreBible(
      code: resultat.code,
      nom: resultat.livre,
      testament: '',
      chapitres: 0,
    );
    if (!mounted) return;
    setState(() {
      _livreChoisi = livre;
      _chapitreChoisi = resultat.chapitre;
      _modeRecherche = false;
      _chapitreFuture = _api.getChapitreBible(
          code: resultat.code, chapitre: resultat.chapitre, version: _version);
    });
    _memoriserLecture();
    _defilerVersTexte();
  }

  List<LivreBible> _livresParTestament(List<LivreBible> livres, int testament) {
    final code = testament == 0 ? 'ancien' : 'nouveau';
    return livres.where((l) => l.testament == code).toList();
  }

  /// Sélecteur de livre : liste uniforme, une ligne par livre, nom
  /// entier et nombre de chapitres en seconde ligne fixe. Le
  /// testament n'est qu'un filtre de cette liste : il n'efface jamais
  /// le livre en cours de lecture.
  Future<void> _ouvrirSelecteurLivre(List<LivreBible> livres) async {
    var testament = _livreChoisi == null
        ? _testament
        : (_livreChoisi!.testament == 'nouveau' ? 1 : 0);
    final choix = await showDialog<LivreBible>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Livre'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Ancien')),
                    ButtonSegment(value: 1, label: Text('Nouveau')),
                  ],
                  selected: {testament},
                  onSelectionChanged: (s) => setStateDialog(() {
                    testament = s.first;
                  }),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: _livresParTestament(livres, testament)
                        .map((livre) => ListTile(
                              title: Text(livre.nom),
                              subtitle: Text(
                                  '${livre.chapitres} chapitres'),
                              trailing: _livreChoisi?.code == livre.code
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () =>
                                  Navigator.of(context).pop(livre),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choix != null) {
      setState(() => _testament = choix.testament == 'nouveau' ? 1 : 0);
      _choisirLivre(choix);
    }
  }

  /// Sélecteur de chapitre : saisie du numéro, ou liste déroulante
  /// uniforme regroupée par dizaines. Aucune pastille étalée.
  Future<void> _ouvrirSelecteurChapitre() async {
    final livre = _livreChoisi;
    if (livre == null) return;
    final numeroController =
        TextEditingController(text: '$_chapitreChoisi');
    final choix = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${livre.nom} : chapitre'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              TextField(
                key: const Key('numero-chapitre'),
                controller: numeroController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Numéro du chapitre',
                  hintText: '1',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(context)
                    .pop(int.tryParse(v.trim())),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                      int.tryParse(numeroController.text.trim())),
                  child: const Text('Aller'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (var debut = 1;
                        debut <= livre.chapitres;
                        debut += 10) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Chapitres $debut à '
                          '${(debut + 9).clamp(1, livre.chapitres)}',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                        ),
                      ),
                      for (var n = debut;
                          n < debut + 10 && n <= livre.chapitres;
                          n++)
                        ListTile(
                          title: Text('Chapitre $n'),
                          trailing: _chapitreChoisi == n
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(n),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choix != null) _choisirChapitre(choix);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          controller: _defilement,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Lecture de la Bible, cours de l’école biblique et '
              'progression de chacun.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _carteReprendre(),
            _carteVersetDuJour(),
            _carteLecture(),
            const SizedBox(height: 12),
            _carteEcole(),
            const SizedBox(height: 12),
            _carteProgression(),
          ],
        ),
      ),
    );
  }

  /// Reprendre ma lecture : carte distincte de la Progression de
  /// l'École biblique, absente tant que rien n'a été lu. La
  /// progression est la position réelle dans le livre en cours
  /// (« Chapitre X sur N »), jamais un chiffre inventé : N vient
  /// du canon chargé, la carte disparaît si le livre est introuvable.
  Widget _carteReprendre() {
    return Consumer<PreferencesLocales>(
      builder: (context, preferences, _) {
        final position = preferences.derniereLecture;
        if (position == null) return const SizedBox.shrink();
        return FutureBuilder<List<LivreBible>>(
          future: _livresFuture,
          builder: (context, snapshot) {
            final livres = snapshot.data ?? const <LivreBible>[];
            LivreBible? livre;
            for (final l in livres) {
              if (l.code == position.code) livre = l;
            }
            if (livre == null) return const SizedBox.shrink();
            final chapitre =
                position.chapitre.clamp(1, livre.chapitres);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Reprendre ma lecture',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          '${livre.nom} — Chapitre $chapitre '
                          'sur ${livre.chapitres}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _reprendreLecture(position),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Reprendre'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }

  /// Verset du jour calendaire, dans la version en cours : un seul
  /// verset par jour, le même sur l'accueil fidèle et ici. Un
  /// toucher ouvre le passage. Si le verset ne charge pas, la carte
  /// se masque au lieu d'afficher une erreur.
  Widget _carteVersetDuJour() {
    return FutureBuilder<VersetDuJour>(
      future: _versetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              SizedBox(height: 12),
            ],
          );
        }
        final verset = snapshot.data;
        if (verset == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Verset du jour',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      '« ${verset.texte} »',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      verset.reference,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _ouvrirVerset(verset),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Lire ce passage'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  /// Carte Lecture (maquette, écran 40) : un seul état de chargement
  /// pour le canon, recherche de passages à un seul métier, Livre et
  /// Chapitre côte à côte, texte dans la même carte.
  Widget _carteLecture() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bible',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FutureBuilder<List<VersionBible>>(
              future: _versionsFuture,
              builder: (context, snapshot) {
                final versions = snapshot.data ?? const <VersionBible>[];
                if (versions.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String>(
                  key: const Key('selecteur-version'),
                  initialValue: _version,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Version'),
                  items: versions
                      .map((v) => DropdownMenuItem(
                          value: v.id, child: Text(v.nom)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _choisirVersion(v);
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recherche-passages'),
              controller: _rechercheTexteController,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Rechercher dans la Bible',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Rechercher',
                  onPressed: _lancerRechercheTexte,
                ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (v) => _rechercheTexte = v,
              onSubmitted: (_) => _lancerRechercheTexte(),
            ),
            const SizedBox(height: 12),
            if (_modeRecherche) _resultatsRecherche(),
            if (!_modeRecherche)
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
                  final livres = snapshot.data ?? const <LivreBible>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _BoutonSelecteur(
                              key: const Key('selecteur-livre'),
                              libelle: 'Livre',
                              valeur: _livreChoisi?.nom ?? 'Choisir',
                              onTap: () => _ouvrirSelecteurLivre(livres),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: _BoutonSelecteur(
                              key: const Key('selecteur-chapitre'),
                              libelle: 'Chapitre',
                              valeur: _livreChoisi == null
                                  ? 'Choisir'
                                  : '$_chapitreChoisi / ${_livreChoisi!.chapitres}',
                              onTap: _livreChoisi == null
                                  ? null
                                  : _ouvrirSelecteurChapitre,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        key: _cleTexte,
                        child: _livreChoisi == null
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Text(
                                  'Aucun texte chargé.\nChoisissez un livre '
                                  'et un chapitre pour lire.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _lectureChapitre(),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _ouvrirConcordance,
                  icon: const Icon(Icons.translate_outlined),
                  label: const Text('Concordance Strong'),
                ),
                TextButton.icon(
                  onPressed: _ouvrirDictionnaire,
                  icon: const Icon(Icons.book_outlined),
                  label: const Text('Dictionnaire'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Titre du chapitre, précédent et suivant, grille des chapitres,
  /// puis texte. La grille garde Précédent et Suivant, elle ajoute
  /// le saut direct par numéro.
  Widget _lectureChapitre() {
    final livre = _livreChoisi!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _chapitreChoisi > 1 ? _chapitrePrecedent : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Précédent'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _chapitreChoisi < livre.chapitres
                    ? _chapitreSuivant
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Suivant'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Chapitres', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var n = 1; n <= livre.chapitres; n++)
              _BoutonChapitre(
                key: Key('grille-chapitre-$n'),
                numero: n,
                actif: n == _chapitreChoisi,
                onTap: () => _choisirChapitre(n, defiler: false),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _chapitre(),
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
            Row(
              children: [
                Expanded(
                    child: SectionTitle(
                        title: '${resultats.length} passage(s) trouvé(s)')),
                TextButton(
                  onPressed: () => setState(() => _modeRecherche = false),
                  child: const Text('Retour à la lecture'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...resultats.map((r) => Card(
                  child: ListTile(
                    title: Text(
                      r.texte,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(r.reference,
                        style: const TextStyle(fontSize: 11.5)),
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
    final livre = _livreChoisi!;
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
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${livre.nom} — chapitre $_chapitreChoisi',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                _version == 'kjv'
                    ? 'King James Version'
                    : 'Louis Segond 1910',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ...chapitre.versets.map((v) => Padding(
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
                  )),
            ],
          ),
        );
      },
    );
  }

  /// Carte École (maquette, écran 40) : aperçu court des cours, un
  /// seul bouton vers l'écran complet. Aucune gestion de cours ici,
  /// elle reste dans EcoleBibliqueScreen.
  Widget _carteEcole() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('École biblique, cours',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FutureBuilder<List<CoursEcole>>(
              future: _coursFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
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
                    message: 'Aucun cours publié. Les cours créés par la '
                        'structure apparaîtront ici, leçon par leçon.',
                  );
                }
                return Column(
                  children: [
                    for (final c in cours.take(3))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.school_outlined),
                          title: Text(c.titre,
                              style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(c.niveauLabel,
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  EcoleCoursDetailScreen(cours: c),
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
                      label: const Text('Ouvrir l’école biblique',
                          style: TextStyle(fontSize: 13.5)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Carte Progression : le widget partagé avec l'écran École
  /// biblique, un seul chargement, aucune copie locale.
  Widget _carteProgression() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ProgressionEcole(future: _progressionsFuture),
      ),
    );
  }
}

/// Sélecteur compact, comme la maquette : libellé et valeur, bordure,
/// chevron. Hauteur et structure identiques pour Livre et Chapitre.
class _BoutonSelecteur extends StatelessWidget {
  final String libelle;
  final String valeur;
  final VoidCallback? onTap;

  const _BoutonSelecteur({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final desactive = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(libelle,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    valeur,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: desactive
                          ? Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.unfold_more, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Bouton numéroté de la grille des chapitres : le chapitre en cours
/// est plein, les autres ont une bordure. Taille fixe, 44 px de large
/// minimum pour rester touchable.
class _BoutonChapitre extends StatelessWidget {
  final int numero;
  final bool actif;
  final VoidCallback onTap;

  const _BoutonChapitre({
    super.key,
    required this.numero,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: actif ? couleurs.primary : null,
          border: Border.all(
              color: actif ? couleurs.primary : couleurs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$numero',
          style: TextStyle(
            fontSize: 13,
            fontWeight: actif ? FontWeight.bold : FontWeight.normal,
            color: actif ? couleurs.onPrimary : null,
          ),
        ),
      ),
    );
  }
}
