import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Message à mon église (tranche P1) : fil privé façon Messenger avec
/// l'église mère ou la tutelle, dans l'application, pas par e-mail.
/// Le fidèle écrit, l'église répond depuis son espace.
class MessagesFideleScreen extends StatefulWidget {
  const MessagesFideleScreen({super.key});

  @override
  State<MessagesFideleScreen> createState() => _MessagesFideleScreenState();
}

class _MessagesFideleScreenState extends State<MessagesFideleScreen> {
  late Future<FilMessages> _future;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _envoi = false;

  /// Onglet en cours : 0 « Secrétariat / Église » (fil privé P1,
  /// inchangé), 1 « Groupes & Ministères » (état vide honnête :
  /// aucun groupe pour le moment, pas de groupe inventé).
  int _onglet = 0;

  /// Suggestions rapides sous le message d'accueil : elles
  /// remplissent le compositeur, rien n'est envoyé sans le fidèle.
  static const _suggestions = [
    'Demander une attestation',
    'Question cotisations',
    'Sujet de prière',
  ];

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<FilMessages> _charger() =>
      context.read<AppState>().api.getMesMessages();

  void _refresh() => setState(() => _future = _charger());

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _defilerBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _envoyer() async {
    final texte = _controller.text.trim();
    if (texte.isEmpty) return;
    setState(() => _envoi = true);
    try {
      await context.read<AppState>().api.envoyerMessageFidele(corps: texte);
      _controller.clear();
      if (mounted) {
        _refresh();
        _defilerBas();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Secrétariat / Église'),
                icon: Icon(Icons.church_outlined),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Groupes & Ministères'),
                icon: Icon(Icons.groups_outlined),
              ),
            ],
            selected: {_onglet},
            onSelectionChanged: (s) => setState(() => _onglet = s.first),
          ),
        ),
        Expanded(
          child: _onglet == 1
              ? const _GroupesVides()
              : FutureBuilder<FilMessages>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const AppLoading();
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: _refresh,
                      );
                    }
                    final fil = snapshot.data!;
                    final messages = fil.messages;
                    return Column(
                      children: [
                        Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    child: Icon(Icons.church_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fil.destinataireNom ?? 'Mon église',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Message privé à son église ; les réponses se '
                          'lisent dans l’application.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const Chip(label: Text('Privé', style: TextStyle(fontSize: 11.5))),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: PaletteMembre.bordure,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Bonjour, bienvenue dans la messagerie de '
                              'votre église. Écrivez votre message, le '
                              'secrétariat vous répondra ici.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in _suggestions)
                              ActionChip(
                                label: Text(s),
                                onPressed: () {
                                  _controller.text = s;
                                  _controller.selection =
                                      TextSelection.fromPosition(
                                    TextPosition(offset: s.length),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const EmptyState(
                          icon: Icons.mail_outline,
                          message: 'Aucun message.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final moi = m.deMoi;
                        return Align(
                          alignment: moi
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: moi
                                  ? PaletteMembre.violetRoyal
                                  : Colors.white,
                              border: moi
                                  ? null
                                  : Border.all(
                                      color: PaletteMembre.bordure,
                                    ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.corps,
                                  style: TextStyle(
                                    color: moi
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatDateTime(m.createdAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: moi
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                                .withValues(alpha: 0.7)
                                            : null,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Écrire un message',
                        filled: true,
                        fillColor: PaletteMembre.surfaceDouce,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: FilledButton(
                      onPressed: _envoi ? null : _envoyer,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        backgroundColor: PaletteMembre.or,
                        foregroundColor: PaletteMembre.violetRoyal,
                      ),
                      child: _envoi
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: PaletteMembre.violetRoyal,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                    ),
                  ),
                ],
              ),
            ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Onglet « Groupes & Ministères » : état vide honnête, aucun
/// groupe n'existe pour le moment dans l'église du fidèle.
class _GroupesVides extends StatelessWidget {
  const _GroupesVides();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.groups_outlined,
      message: 'Aucun groupe pour le moment. Les groupes et ministères '
          'de votre église apparaîtront ici.',
    );
  }
}
