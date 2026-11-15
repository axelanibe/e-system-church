import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bible.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Dictionnaire biblique (tranche T9) : articles encyclopédiques
/// (personnes, lieux, termes) — « Aquifer Open Bible Dictionary »
/// (© 2026 Mission Mutual, CC BY-SA 4.0, adaptation du Tyndale Open
/// Bible Dictionary © 2023). Recherche par mot, lecture d'un article.
/// La langue suit celle de la version biblique choisie (LS1910 ->
/// français, KJV -> anglais).
class DictionnaireScreen extends StatefulWidget {
  final String langue; // fra | eng

  const DictionnaireScreen({super.key, this.langue = 'fra'});

  @override
  State<DictionnaireScreen> createState() => _DictionnaireScreenState();
}

class _DictionnaireScreenState extends State<DictionnaireScreen> {
  String _recherche = '';
  ArticleDictionnaire? _articleChoisi;
  Future<List<ArticleDictionnaire>>? _resultatsFuture;

  final _rechercheController = TextEditingController();

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<AppState>().api;

  void _lancerRecherche() {
    final q = _recherche.trim();
    if (q.length < 2) return;
    setState(() {
      _articleChoisi = null;
      _resultatsFuture =
          _api.rechercherDictionnaire(q, langue: widget.langue);
    });
  }

  Future<void> _ouvrirArticle(ArticleDictionnaire article) async {
    setState(() => _articleChoisi = article);
  }

  @override
  Widget build(BuildContext context) {
    final enFrancais = widget.langue == 'fra';
    return Scaffold(
      appBar: AppBar(
          title: Text(
              'Dictionnaire biblique (${enFrancais ? 'français' : 'anglais'})')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    enFrancais
                        ? 'Dictionnaire biblique en français (Aquifer Open '
                            'Bible Dictionary). Cherchez une personne, un '
                            'lieu ou un terme.'
                        : 'Bible dictionary in English (Aquifer Open Bible '
                            'Dictionary). Search for a person, a place or a '
                            'term.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rechercheController,
                    decoration: InputDecoration(
                      labelText: enFrancais
                          ? 'Rechercher un mot (ex. Moïse)'
                          : 'Search for a word (e.g. Moses)',
                      prefixIcon: const Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => _recherche = v,
                    onSubmitted: (_) => _lancerRecherche(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _lancerRecherche,
                      icon: const Icon(Icons.search),
                      label: const Text('Rechercher'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_resultatsFuture != null && _articleChoisi == null)
                    _resultatsRecherche(),
                  if (_articleChoisi != null) _detailArticle(_articleChoisi!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultatsRecherche() {
    return FutureBuilder<List<ArticleDictionnaire>>(
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
            message: 'Aucun article trouvé.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title: '${resultats.length} article(s) trouvé(s)'),
            const SizedBox(height: 8),
            ...resultats.map((a) => Card(
                  child: ListTile(
                    title: Text(a.titre),
                    subtitle: Text(
                      a.texte.split('\n\n').length > 1
                          ? a.texte.split('\n\n')[1]
                          : a.texte,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrirArticle(a),
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _detailArticle(ArticleDictionnaire article) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _articleChoisi = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour aux résultats'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.titre,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(article.texte,
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
