import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/messagerie.dart';
import '../services/messagerie_lecture_service.dart';
import '../services/messagerie_temps_reel.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'messagerie_signalement.dart';

/// Une conversation (T-Msg-1, spécification §6).
///
/// Bulles contrastées (blanc sur violet profond 16,9:1, violet
/// profond sur blanc 15,3:1), zone de saisie fixe en bas, cibles
/// tactiles de 48 px minimum, champs à 16 px minimum sur iPhone.
/// Les nouveaux messages arrivent par WebSocket ; quand il est coupé,
/// l'écran rafraîchit par HTTP toutes les 15 secondes et affiche
/// « Reconnexion… ». T-Msg-4 : le bouton « Signaler » ouvre la feuille
/// de signalement de la conversation, l'appui long sur une bulle
/// propose Modifier / Supprimer (mes bulles) et Signaler (toutes).
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
      // T-Msg-4 : un message déjà connu est remplacé (modification ou
      // suppression douce diffusée par WebSocket), pas ignoré.
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index >= 0) {
          _messages = [..._messages]..[index] = message;
        } else {
          _messages = [..._messages, message];
        }
      });
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

  /// T-Msg-4 : signale la conversation (motif, description
  /// facultative, phrase de visibilité avant envoi).
  Future<void> _signaler() async {
    await ouvrirFeuilleSignalement(
      context,
      api: context.read<AppState>().api,
      targetType: 'conversation',
      targetId: widget.conversation.id,
    );
  }

  /// T-Msg-4 : appui long sur une bulle — Modifier / Supprimer sur
  /// mes bulles, Signaler sur toutes. Un message supprimé ne propose
  /// plus que Signaler, il n'y a plus rien à modifier.
  Future<void> _menuMessage(MessageMessagerie message, bool mien) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mien && !message.supprime)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Modifier'),
                onTap: () => Navigator.of(ctx).pop('modifier'),
              ),
            if (mien && !message.supprime)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Supprimer'),
                onTap: () => Navigator.of(ctx).pop('supprimer'),
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Signaler'),
              onTap: () => Navigator.of(ctx).pop('signaler'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choix == 'modifier') {
      await _modifierMessage(message);
    } else if (choix == 'supprimer') {
      await _supprimerMessage(message);
    } else if (choix == 'signaler') {
      await ouvrirFeuilleSignalement(
        context,
        api: context.read<AppState>().api,
        targetType: 'message',
        targetId: message.id,
      );
    }
  }

  Future<void> _modifierMessage(MessageMessagerie message) async {
    final api = context.read<AppState>().api;
    final controleur = TextEditingController(text: message.content);
    final nouveau = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(
          controller: controleur,
          maxLines: 4,
          maxLength: 5000,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controleur.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (nouveau == null || nouveau.isEmpty || nouveau == message.content) {
      return;
    }
    try {
      final modifie = await api.modifierMessageConversation(
        widget.conversation.id,
        message.id,
        content: nouveau,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index >= 0) _messages = [..._messages]..[index] = modifie;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerMessage(MessageMessagerie message) async {
    final api = context.read<AppState>().api;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        content: const Text(
          'Le message restera visible comme « Message supprimé ».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    try {
      final supprime = await api.supprimerMessageConversation(
        widget.conversation.id,
        message.id,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index >= 0) _messages = [..._messages]..[index] = supprime;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reponsesDesactivees = widget.conversation.reponsesDesactivees;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        // Liseré or 3 px sous la barre : signature visuelle de la
        // messagerie, aussi dans la liste des conversations.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: AppTheme.or),
        ),
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
                                onLongPress: () => _menuMessage(message, mien),
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
/// or foncé sur fond papier (4,58:1), jamais en blanc atténué
/// sur violet. T-Msg-4 : appui long (Modifier / Supprimer /
/// Signaler), « (modifié) » quand l'auteur a modifié le message,
/// style atténué pour un message supprimé.
class _Bulle extends StatelessWidget {
  final MessageMessagerie message;
  final bool mien;
  final String? nomExpediteur;
  final VoidCallback? onLongPress;

  const _Bulle({
    required this.message,
    required this.mien,
    this.nomExpediteur,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final heure = message.createdAt == null
        ? ''
        : heureCourteConversation(message.createdAt);
    final sousTitre = [
      if (heure.isNotEmpty) heure,
      if (message.estModifie) '(modifié)',
    ].join(' ');
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
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: message.supprime
                        ? AppTheme.fondPapier
                        : mien
                            ? AppTheme.violetProfond
                            : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: mien && !message.supprime
                        ? null
                        : Border.all(
                            // Bordure papier-violet : la bulle se
                            // distingue du fond papier.
                            color: AppTheme.bordure,
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
                          fontStyle: message.supprime
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: message.supprime
                              ? AppTheme.orFonce
                              : mien
                                  ? Colors.white
                                  : AppTheme.violetProfond,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (sousTitre.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    sousTitre,
                    style: const TextStyle(
                      fontSize: 11,
                      // Horodatage or foncé (4,58:1 sur papier).
                      color: AppTheme.orFonce,
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
