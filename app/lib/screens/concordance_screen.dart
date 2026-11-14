import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bible.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Concordance Strong (tranche T9) : lexiques hébreu et grec de James
/// Strong (domaine public, données Open Scriptures, CC-BY-SA).
/// Recherche par numéro (G1234, H1234) ou par mot (lemme,
/// translittération, définitions). La concordance est un lexique
/// consultable : aucun lien mot à mot avec les versets — la LS1910
/// française n'a pas de numéros Strong natifs.
class ConcordanceScreen extends StatefulWidget {
  const ConcordanceScreen({super.key});

  @override
  State<ConcordanceScreen> createState() => _ConcordanceScreenState();
}

class _ConcordanceScreenState extends State<ConcordanceScreen> {
  String _recherche = '';
  EntreeStrong? _entreeChoisie;
  Future<List<EntreeStrong>>? _resultatsFuture;

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
      _entreeChoisie = null;
      _resultatsFuture = _api.rechercherStrong(q);
    });
  }

  void _choisirEntree(EntreeStrong entree) {
    setState(() => _entreeChoisie = entree);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Concordance Strong')),
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
                    'Lexiques hébreu et grec de James Strong. Cherchez '
                    'par numéro (ex. H1, G1) ou par mot (ex. father, '
                    'amour, logos).',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rechercheController,
                    decoration: const InputDecoration(
                      labelText: 'Numéro Strong ou mot (ex. H1, father)',
                      prefixIcon: Icon(Icons.search),
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
                  if (_resultatsFuture != null && _entreeChoisie == null)
                    _resultatsRecherche(),
                  if (_entreeChoisie != null) _detailEntree(_entreeChoisie!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultatsRecherche() {
    return FutureBuilder<List<EntreeStrong>>(
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
            message: 'Aucune entrée trouvée.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title: '${resultats.length} entrée(s) trouvée(s)'),
            const SizedBox(height: 8),
            ...resultats.map((e) => Card(
                  child: ListTile(
                    title: Text('${e.numero} — ${e.lemma} (${e.translit})'),
                    subtitle: Text(
                      e.definition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _choisirEntree(e),
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _detailEntree(EntreeStrong entree) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _entreeChoisie = null),
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
                  '${entree.numero} — ${entree.lemma}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${entree.langue == 'hebreu' ? 'Hébreu' : 'Grec'} · '
                  'translittération : ${entree.translit}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (entree.pron != null && entree.pron!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Prononciation : ${entree.pron}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 12),
                const SectionTitle(title: 'Définition'),
                Text(entree.definition,
                    style: Theme.of(context).textTheme.bodyLarge),
                if (entree.derivation != null &&
                    entree.derivation!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionTitle(title: 'Dérivation'),
                  Text(entree.derivation!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (entree.kjvDef != null &&
                    entree.kjvDef!.isNotEmpty &&
                    entree.strongsDef != null &&
                    entree.strongsDef!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionTitle(title: 'Définition KJV'),
                  Text(entree.kjvDef!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
