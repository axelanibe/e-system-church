import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';

/// Ma Bible (tranche P1) : coquille de lecteur, Ancien et Nouveau
/// Testament, liste des livres, recherche. Aucun texte biblique réel
/// ici : le texte sera branché depuis la source fournie par la
/// structure, jamais inventé. La liste complète des livres
/// s'affichera ici.
class BibleFideleScreen extends StatefulWidget {
  const BibleFideleScreen({super.key});

  @override
  State<BibleFideleScreen> createState() => _BibleFideleScreenState();
}

/// Livres affichés dans la projection, par testament. Ce ne sont pas
/// les canons complets : la liste complète s'affichera ici.
const _livresAncienTestament = [
  'Genèse',
  'Exode',
  'Lévitique',
  'Nombres',
  'Deutéronome',
  'Josué',
  'Juges',
  'Ruth',
  'Psaumes',
  'Proverbes',
  'Ésaïe',
  'Jérémie',
];

const _livresNouveauTestament = [
  'Matthieu',
  'Marc',
  'Luc',
  'Jean',
  'Actes',
  'Romains',
  'Galates',
  'Éphésiens',
  'Philippiens',
  'Hébreux',
  'Jacques',
  'Apocalypse',
];

class _BibleFideleScreenState extends State<BibleFideleScreen> {
  int _testament = 0; // 0 = Ancien, 1 = Nouveau
  String _recherche = '';
  String? _livreChoisi;
  final _chapitreController = TextEditingController();
  final _versetController = TextEditingController();
  final _rechercheController = TextEditingController();

  @override
  void dispose() {
    _chapitreController.dispose();
    _versetController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  List<String> _livresVisibles() {
    final livres =
        _testament == 0 ? _livresAncienTestament : _livresNouveauTestament;
    final q = _recherche.trim().toLowerCase();
    if (q.isEmpty) return livres;
    return livres.where((l) => l.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final livres = _livresVisibles();
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
                  'Votre Bible, dans votre interface. Choisissez un '
                  'testament, puis un livre.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _rechercheController,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher un livre ou un passage',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _recherche = v),
                ),
                const SizedBox(height: 16),
                SegmentedButton<int>(
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
                  }),
                ),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Liste des livres'),
                if (livres.isEmpty)
                  const EmptyState(
                    icon: Icons.menu_book_outlined,
                    message: 'Aucun livre avec ce nom dans cette liste.',
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: livres
                        .map((livre) => ChoiceChip(
                              label: Text(livre),
                              selected: _livreChoisi == livre,
                              onSelected: (_) => setState(() {
                                _livreChoisi = livre;
                                _chapitreController.clear();
                                _versetController.clear();
                              }),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Text(
                  _testament == 0
                      ? 'La liste complète des livres de l’Ancien Testament '
                          's’affichera ici.'
                      : 'La liste complète des livres du Nouveau Testament '
                          's’affichera ici.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Passage'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _livreChoisi == null
                              ? 'Sélectionnez un livre, puis un chapitre, '
                                  'pour lire le passage.'
                              : _livreChoisi!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chapitreController,
                                decoration: const InputDecoration(
                                  labelText: 'Chapitre',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _versetController,
                                decoration: const InputDecoration(
                                  labelText: 'Verset',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Le texte de la Bible s’affichera ici.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
