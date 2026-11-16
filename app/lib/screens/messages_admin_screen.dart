import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/annexe.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Messages admin (maquette, écran 31) : messages de l'administration
/// aux églises du réseau. Écran dédié, vide « Aucun message de
/// l'administration. », formulaire Destinataires (Toutes les annexes
/// ou une annexe choisie), Message, « Envoyer le message ».
/// Envoi non branché : aucune route serveur n'envoie aujourd'hui un
/// message à une annexe (ni `POST /messages-admin`, ni équivalent) ;
/// le bouton l'explique au lieu de rester muet. Les messages internes
/// aux membres vivent dans Prières, 2e onglet, et ne sont pas touchés.
class MessagesAdminScreen extends StatefulWidget {
  const MessagesAdminScreen({super.key});

  @override
  State<MessagesAdminScreen> createState() => _MessagesAdminScreenState();
}

class _MessagesAdminScreenState extends State<MessagesAdminScreen> {
  late Future<List<Annexe>> _annexesFuture;
  final _messageController = TextEditingController();
  String? _destinataireId; // null = toutes les annexes
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _annexesFuture = context.read<AppState>().api.getAnnexes();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      showApiError(context, 'Écrivez le message.');
      return;
    }
    setState(() => _envoi = true);
    // Pas de route serveur pour envoyer un message aux annexes :
    // on ne laisse pas un bouton mort, on le dit.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Envoi impossible pour l’instant : aucune route serveur '
            'n’envoie de message aux annexes. Le message n’a pas été envoyé.',
          ),
        ),
      );
      setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages admin')),
      body: FutureBuilder<List<Annexe>>(
        future: _annexesFuture,
        builder: (context, snapshot) {
          final annexes = snapshot.data ?? const <Annexe>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const EmptyState(
                icon: Icons.mail_outline,
                message: 'Aucun message de l’administration.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String?>(
                        initialValue: _destinataireId,
                        decoration: const InputDecoration(
                          labelText: 'Destinataires *',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Toutes les annexes', style: TextStyle(fontSize: 13.5)),
                          ),
                          for (final a in annexes)
                            DropdownMenuItem<String?>(
                              value: a.egliseId,
                              child: Text(
                                '${a.egliseNom} (${a.egliseCode})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _destinataireId = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Message *',
                          hintText: 'Écrire le message',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _envoi ? null : _envoyer,
                        child: const Text('Envoyer le message', style: TextStyle(fontSize: 13.5)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'L’envoi aux annexes nécessite une route serveur, '
                        'à brancher côté serveur avant d’envoyer.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
