import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/messagerie.dart';
import '../services/messagerie_lecture_service.dart';
import '../services/messagerie_temps_reel.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Une conversation (T-Msg-1, spécification §6).
///
/// Bulles contrastées (blanc sur violet profond 16,9:1, violet
/// profond sur blanc 15,3:1), zone de saisie fixe en bas, cibles
/// tactiles de 48 px minimum, champs à 16 px minimum sur iPhone.
/// Les nouveaux messages arrivent par WebSocket ; quand il est coupé,
/// l'écran rafraîchit par HTTP toutes les 15 secondes et affiche
/// « Reconnexion… ». Le bouton « Signaler » est présent mais inerte en
/// T-Msg-1 : il affiche « Bientôt disponible », le signalement arrive
/// en T-Msg-2.
class MessagerieConversationScreen extends StatefulWidget {
  final ConversationMessagerie conversation;

  /// Titre affiché (résolu par la liste : titre ou nom de l'autre membre).
  final String titre;

  /// Identifiant de ma fiche membre, quand la liste l'a résolu.
  final String? monMembreId;

  /// Noms des membres de l'église, par identifiant.
  final Map<String, String> nomsMembres;

  const MessagerieConversationScreen({
    super.key,
    required this.conversation,
    required this.titre,
    this.monMembreId,
    this.nomsMembres = const {},
  });

  @override
  State<MessagerieConversationScreen> createState() =>
      _MessagerieConversationScreenState();
}

class _MessagerieConversationScreenState
    extends State<MessagerieConversationScreen> {
  final _saisieController = TextEditingController();
  final _defilementController = ScrollController();
  List<MessageMessagerie> _messages = [];
  bool _chargement = true;
  String? _erreur;
  bool _envoiEnCours = false;
  String? _monMembreId;
  MessagerieTempsReel? _tempsReel;
  StreamSubscription<MessageMessagerie>? _abonnementMessages;
  StreamSubscription<bool>? _abonnementEtat;
  Timer? _minuteurRepli;
  bool _connecte = false;

  @override
  void initState() {
    super.initState();
    _monMembreId = widget.monMembreId;
    _charger();
    _demarrerTempsReel();
  }

  @override
  void dispose() {
    _minuteurRepli?.cancel();
    _abonnementMessages?.cancel();
    _abonnementEtat?.cancel();
    _tempsReel?.deconnecter();
    _saisieController.dispose();
    _defilementController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final api = context.read<AppState>().api;
    try {
      final messages =
          await api.getMessagesConversation(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _chargement = false;
        _erreur = null;
      });
      _marquerLu();
      _defilerEnBas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.toString();
      });
    }
  }

  /// Rafraîchissement silencieux (repli HTTP) : ne remplace que les
  /// messages, sans toucher au champ de saisie.
  Future<void> _rafraichirSilencieux() async {
    if (!mounted || _tempsReel?.estConnecte == true) return;
    try {
      final messages = await context
          .read<AppState>()
          .api
          .getMessagesConversation(widget.conversation.id);
      if (!mounted) return;
      if (messages.length != _messages.length) {
        setState(() => _messages = messages);
        _marquerLu();
        _defilerEnBas();
      }
    } catch (_) {
      // Le repli suivant réessaiera.
    }
  }

  void _demarrerTempsReel() {
    final api = context.read<AppState>().api;
    final tempsReel = MessagerieTempsReel(
      baseUrl: api.baseUrl,
      jeton: () => context.read<AppState>().api.token,
    );
    _tempsReel = tempsReel;
    _abonnementMessages = tempsReel.messages.listen((message) {
      if (!mounted || message.conversationId != widget.conversation.id) {
        return;
      }
      if (_messages.any((m) => m.id == message.id)) return;
      setState(() => _messages = [..._messages, message]);
      _marquerLu();
      _defilerEnBas();
    });
    _abonnementEtat = tempsReel.connecte.listen((connecte) {
      if (!mounted) return;
      setState(() => _connecte = connecte);
      // À la reconnexion, on reprend par HTTP ce qui a pu manquer.
      if (connecte) _rafraichirSilencieux();
    });
    tempsReel.abonner(widget.conversation.id);
    tempsReel.connecter();
    // Repli : interrogation HTTP toutes les 15 secondes tant que le
    // WebSocket est coupé.
    _minuteurRepli = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _rafraichirSilencieux(),
    );
  }

  void _marquerLu() {
    final dernier = _messages.isEmpty ? null : _messages.last.createdAt;
    MessagerieLectureService.instance.marquerLu(
      widget.conversation.id,
      dernier ?? DateTime.now(),
    );
  }

  void _defilerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_defilementController.hasClients) return;
      _defilementController.jumpTo(
        _defilementController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _envoyer() async {
    final contenu = _saisieController.text.trim();
    if (contenu.isEmpty || _envoiEnCours) return;
    setState(() => _envoiEnCours = true);
    try {
      final message = await context
          .read<AppState>()
          .api
          .envoyerMessageConversation(
            widget.conversation.id,
            content: contenu,
          );
      if (!mounted) return;
      _saisieController.clear();
      setState(() {
        _messages = [..._messages, message];
        _monMembreId = message.senderId;
        _envoiEnCours = false;
      });
      _marquerLu();
      _defilerEnBas();
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      showApiError(context, e);
    }
  }

  void _signaler() {
    // T-Msg-1 : bouton présent, sans action. Le signalement (motif,
    // preuve figée, file de modération) arrive en T-Msg-2.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bientôt disponible')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reponsesDesactivees = widget.conversation.reponsesDesactivees;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Signaler',
            onPressed: _signaler,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_connecte && !_chargement)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              color: AppTheme.or.withValues(alpha: 0.25),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Reconnexion…',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _chargement
                ? const AppLoading()
                : _erreur != null
                    ? AppError(message: _erreur!, onRetry: _charger)
                    : _messages.isEmpty
                        ? const EmptyState(
                            icon: Icons.chat_bubble_outline,
                            message:
                                'Aucun message pour l’instant.\nÉcrivez le premier.',
                          )
                        : ListView.builder(
                            controller: _defilementController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final mien = _monMembreId != null &&
                                  message.senderId == _monMembreId;
                              final nom = widget.nomsMembres[message.senderId];
                              return _Bulle(
                                message: message,
                                mien: mien,
                                nomExpediteur:
                                    widget.conversation.estGroupe && !mien
                                        ? nom
                                        : null,
                              );
                            },
                          ),
          ),
          if (reponsesDesactivees)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              color: AppTheme.fondPapier,
              child: const Text(
                'Les réponses sont désactivées sur ce canal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
            )
          else
            Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              ),
              color: AppTheme.fondPapier,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _saisieController,
                      // 16 px minimum : Safari iPhone ne zoome pas. Le
                      // plancher est dans AppTheme (bodyLarge compensé),
                      // pas de taille en dur ici.
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.send),
                      tooltip: 'Envoyer',
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.violetProfond,
                      ),
                      onPressed: _envoiEnCours ? null : _envoyer,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Une bulle de message : à droite sur violet pour mes messages, à
/// gauche sur blanc pour les autres. L'heure est sous la bulle, en
/// violet à 75 % sur fond papier (7,37:1), jamais en blanc atténué
/// sur violet.
class _Bulle extends StatelessWidget {
  final MessageMessagerie message;
  final bool mien;
  final String? nomExpediteur;

  const _Bulle({
    required this.message,
    required this.mien,
    this.nomExpediteur,
  });

  @override
  Widget build(BuildContext context) {
    final heure = message.createdAt == null
        ? ''
        : heureCourteConversation(message.createdAt);
    return Align(
      alignment: mien ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment:
                mien ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: mien ? AppTheme.violetProfond : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: mien
                      ? null
                      : Border.all(
                          color: AppTheme.violetProfond.withValues(
                            alpha: 0.2,
                          ),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nomExpediteur != null) ...[
                      Text(
                        nomExpediteur!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.violetProfond,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 15,
                        color: mien
                            ? Colors.white
                            : AppTheme.violetProfond,
                      ),
                    ),
                  ],
                ),
              ),
              if (heure.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    heure,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.violetProfond.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
