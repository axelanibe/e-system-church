import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/journal_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Mon journal (tranche P1) : notes privées du fidèle, conservées sur
/// l'appareil seulement, jamais envoyées. Export et import JSON par
/// fusion, comme dans CONNEXION PROPHÉTIQUE.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _service = JournalService();
  late Future<List<NoteJournal>> _future;
  String? _userId;
  bool _editeurOuvert = false;
  NoteJournal? _noteEnCours;
  final _titreController = TextEditingController();
  final _texteController = TextEditingController();
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AppState>().user?.id;
    _future = _charger();
  }

  Future<List<NoteJournal>> _charger() {
    final userId = _userId;
    if (userId == null) return Future.value([]);
    return _service.lire(userId);
  }

  void _refresh() => setState(() => _future = _charger());

  @override
  void dispose() {
    _titreController.dispose();
    _texteController.dispose();
    super.dispose();
  }

  void _ouvrirEditeur([NoteJournal? note]) {
    setState(() {
      _noteEnCours = note;
      _editeurOuvert = true;
      _titreController.text = note?.titre ?? '';
      _texteController.text = note?.texte ?? '';
    });
  }

  void _fermerEditeur() {
    setState(() {
      _editeurOuvert = false;
      _noteEnCours = null;
      _titreController.clear();
      _texteController.clear();
    });
  }

  Future<void> _enregistrer() async {
    final userId = _userId;
    if (userId == null) return;
    final titre = _titreController.text.trim();
    final texte = _texteController.text.trim();
    if (titre.isEmpty && texte.isEmpty) {
      showApiError(context, 'Écrivez votre note.');
      return;
    }
    setState(() => _enregistrement = true);
    try {
      final note = _noteEnCours;
      if (note == null) {
        await _service.ajouter(userId, titre: titre, texte: texte);
      } else {
        await _service.modifier(userId, note, titre: titre, texte: texte);
      }
      if (mounted) {
        _fermerEditeur();
        showSuccess(context, 'Note enregistrée.');
        _refresh();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _supprimer(NoteJournal note) async {
    final userId = _userId;
    if (userId == null) return;
    final confirme = await confirmDelete(
      context,
      'Supprimer définitivement cette note ?',
    );
    if (!confirme) return;
    await _service.supprimer(userId, note.id);
    if (mounted) {
      showSuccess(context, 'Note supprimée.');
      _refresh();
    }
  }

  Future<void> _exporter() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final octets = await _service.exporterJson(userId);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(octets),
              name: 'journal-e-system-church.json',
              mimeType: 'application/json',
            ),
          ],
          subject: 'Mon journal — e-System Church',
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _importer() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) return;
      final nombre = await _service.importerJson(userId, bytes);
      if (mounted) {
        showSuccess(
          context,
          nombre == 0
              ? 'Rien à importer : vos notes sont déjà là.'
              : '$nombre note${nombre > 1 ? 's' : ''} importée${nombre > 1 ? 's' : ''}.',
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon journal')),
      body: FutureBuilder<List<NoteJournal>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final notes = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Journal privé pour prendre vos notes. Vos notes '
                          'restent privées, elles ne sont jamais envoyées.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Mes notes',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                            ),
                            Text(
                              pluriel(notes.length, 'note'),
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (notes.isEmpty && !_editeurOuvert)
                          const EmptyState(
                            icon: Icons.edit_outlined,
                            message: 'Aucune note pour le moment. Vos notes '
                                'personnelles apparaîtront ici, pour vous seul.',
                          )
                        else
                          ...notes.map((note) => Card(
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.edit_outlined),
                                  title: Text(
                                    note.titre.isEmpty
                                        ? 'Sans titre'
                                        : note.titre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    note.texte,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    icon:
                                        const Icon(Icons.delete_outline),
                                    tooltip: 'Supprimer',
                                    onPressed: () => _supprimer(note),
                                  ),
                                  onTap: () => _ouvrirEditeur(note),
                                ),
                              )),
                        const SizedBox(height: 12),
                        if (_editeurOuvert) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _noteEnCours == null
                                        ? 'Nouvelle note'
                                        : 'Modifier la note',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _titreController,
                                    decoration: const InputDecoration(
                                      labelText: 'Titre',
                                      hintText: 'Titre de votre note',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _texteController,
                                    decoration: const InputDecoration(
                                      labelText: 'Texte',
                                      hintText: 'Écrivez votre note ici',
                                    ),
                                    maxLines: 6,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: _enregistrement
                                              ? null
                                              : _enregistrer,
                                          child: Text(
                                            _enregistrement
                                                ? 'Enregistrement…'
                                                : 'Enregistrer',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _fermerEditeur,
                                          child: const Text('Annuler'),
                                        ),
                                      ),
                                    ],
                                  ),

                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          FilledButton.icon(
                            onPressed: () => _ouvrirEditeur(),
                            icon: const Icon(Icons.add),
                            label: const Text('Nouvelle note'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const SectionTitle(title: 'Export et import'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'Export et import JSON par fusion. L’import '
                            'ajoute vos notes sans effacer celles déjà '
                            'présentes.',
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exporter,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Exporter en JSON'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importer,
                                icon: const Icon(Icons.upload_outlined),
                                label: const Text('Importer en JSON'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
