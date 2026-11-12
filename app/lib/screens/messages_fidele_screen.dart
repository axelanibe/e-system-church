import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final apercu = context.watch<AppState>().apercuFidele;
    return FutureBuilder<FilMessages>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          // En aperçu admin, le fil n'existe pas : état vide, pas d'erreur.
          if (apercu) {
            return const EmptyState(
              icon: Icons.mail_outline,
              message: 'Aperçu : la conversation privée du fidèle '
                  's’affichera ici.',
            );
          }
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Boîte de messagerie de votre église, dans '
                          'l’application.',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Chip(label: Text('Privé')),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.mail_outline,
                      message: 'Aucun message pour le moment. Votre '
                          'conversation privée avec votre église commencera '
                          'ici.',
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
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
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
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message',
                      ),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _envoi ? null : _envoyer,
                    child: Text(_envoi ? 'Envoi…' : 'Envoyer'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Message privé, envoyé dans l’application, pas par e-mail.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
