import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../models/messagerie.dart';
import '../services/messagerie_lecture_service.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'messagerie_conversation_screen.dart';

/// Liste des conversations (T-Msg-1, spécification §6).
///
/// Cartes sobres, filtres Toutes, Directes, Groupes, Pastorale, état
/// vide chaleureux, nombre de non lus par conversation, aperçu du
/// dernier message, heure. Le serveur ne renvoie ni aperçu ni non lus :
/// ils sont calculés ici, à partir des messages lus pour chaque
/// conversation (voir `models/messagerie.dart`).
class MessagerieListeScreen extends StatefulWidget {
  /// [sansAppBar] : intégré comme onglet (barre du bas), sans sa propre
  /// barre, l'en-tête clair de HomeScreen donne déjà le titre.
  final bool sansAppBar;

  const MessagerieListeScreen({super.key, this.sansAppBar = false});

  @override
  State<MessagerieListeScreen> createState() => _MessagerieListeScreenState();
}

class _MessagerieListeScreenState extends State<MessagerieListeScreen> {
  String _filtre = 'toutes';
  List<ConversationMessagerie> _conversations = [];
  Map<String, Member> _membresParId = {};
  String? _monMembreId;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final api = context.read<AppState>().api;
    final monEmail = context.read<AppState>().user?.email;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await MessagerieLectureService.instance.charger();
      final conversations = await api.getConversationsMessagerie();
      // Noms des membres et mon identifiant (pour les non lus et les
      // titres des directes) : une seule lecture de la liste, qui ne
      // contient que les membres de mon église.
      var membresParId = <String, Member>{};
      String? monMembreId;
      try {
        final page = await api.getMembers(limit: 100);
        membresParId = {
          for (final membre in page.membres) membre.id: membre,
        };
        monMembreId = trouverMonMembreId(page.membres, monEmail);
      } catch (_) {
        // Sans la liste des membres, les noms s'affichent par défaut
        // et les non lus comptent tous les messages récents.
      }
      // Aperçu et non lus, conversation par conversation : un échec
      // sur l'une n'empêche pas les autres de s'afficher.
      final lecture = MessagerieLectureService.instance;
      final enrichies = <ConversationMessagerie>[];
      for (final conversation in conversations) {
        try {
          final messages =
              await api.getMessagesConversation(conversation.id);
          enrichies.add(
            conversation.copyWith(
              dernierMessage: messages.isEmpty
                  ? null
                  : messages.last.content,
              nonLus: compterMessagesNonLus(
                messages,
                monMembreId,
                lecture.luLe(conversation.id),
              ),
            ),
          );
        } catch (_) {
          enrichies.add(conversation);
        }
      }
      if (!mounted) return;
      setState(() {
        _conversations = enrichies;
        _membresParId = membresParId;
        _monMembreId = monMembreId;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.toString();
      });
    }
  }

  List<ConversationMessagerie> get _filtrees {
    switch (_filtre) {
      case 'directe':
        return _conversations
            .where((c) => c.type == 'directe')
            .toList();
      case 'groupes':
        return _conversations.where((c) => c.estGroupe).toList();
      case 'pastorale':
        return _conversations
            .where((c) => c.type == 'pastorale')
            .toList();
      default:
        return _conversations;
    }
  }

  /// Nom affiché : titre quand il existe, sinon, pour une directe,
  /// le nom de l'autre membre (dernier expéditeur), sinon un libellé
  /// neutre. Le serveur ne renvoie pas les participants en T-Msg-0.
  String _nomAffiche(ConversationMessagerie conversation) {
    if (conversation.title != null &&
        conversation.title!.trim().isNotEmpty) {
      return conversation.title!.trim();
    }
    if (conversation.type == 'directe') return 'Conversation directe';
    if (conversation.type == 'pastorale') return 'Conversation pastorale';
    return 'Groupe';
  }

  String _initiales(String nom) {
    final mots =
        nom.split(' ').where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first[0].toUpperCase();
    return (mots.first[0] + mots.last[0]).toUpperCase();
  }

  Future<void> _ouvrir(ConversationMessagerie conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagerieConversationScreen(
          conversation: conversation,
          titre: _nomAffiche(conversation),
          monMembreId: _monMembreId,
          nomsMembres: {
            for (final e in _membresParId.entries) e.key: e.value.fullName,
          },
        ),
      ),
    );
    // Retour : la lecture vient d'être marquée, on rafraîchit.
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    // Total des non lus pour le bandeau d'identité (design couleurs
    // messagerie, 16 nov. 2026).
    final totalNonLus =
        _conversations.fold<int>(0, (total, c) => total + c.nonLus);
    return Scaffold(
      appBar: widget.sansAppBar
          ? null
          : AppBar(
              title: const Text('Messagerie'),
              // Liseré or 3 px sous la barre : signature visuelle de
              // la messagerie, aussi dans chaque conversation.
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: Container(height: 3, color: AppTheme.or),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouvelleConversation,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle conversation'),
      ),
      body: _chargement
          ? const AppLoading()
          : _erreur != null
              ? AppError(message: _erreur!, onRetry: _charger)
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: Column(
                    children: [
                      // Bandeau dégradé violet, compteur des non lus
                      // en or : l'identité propre de la messagerie.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.violetProfond,
                              AppTheme.violetSecondaire,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline,
                              color: AppTheme.or,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: totalNonLus > 0
                                          ? '$totalNonLus'
                                          : 'Aucun message non lu',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: totalNonLus > 0
                                            ? AppTheme.or
                                            : Colors.white,
                                      ),
                                    ),
                                    if (totalNonLus > 0)
                                      TextSpan(
                                        text:
                                            ' conversation${totalNonLus > 1 ? 's' : ''} non lue${totalNonLus > 1 ? 's' : ''}',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        // Défilement horizontal : les 4 filtres ne
                        // tiennent pas sur un téléphone étroit quand
                        // la taille du texte est agrandie (Très grand).
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final (valeur, libelle)
                                  in const [
                                ('toutes', 'Toutes'),
                                ('directe', 'Directes'),
                                ('groupes', 'Groupes'),
                                ('pastorale', 'Pastorale'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(libelle),
                                    selected: _filtre == valeur,
                                    selectedColor: AppTheme.violetProfond,
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: AppTheme.bordure,
                                    ),
                                    labelStyle: TextStyle(
                                      color: _filtre == valeur
                                          ? Colors.white
                                          : AppTheme.violetProfond,
                                    ),
                                    onSelected: (_) => setState(
                                      () => _filtre = valeur,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _filtrees.isEmpty
                            ? EmptyState(
                                icon: Icons.chat_bubble_outline,
                                message: _filtre == 'toutes'
                                    ? 'Aucune conversation pour l’instant.\nÉcrivez à un membre de votre église pour commencer.'
                                    : 'Aucune conversation dans ce filtre.',
                                actionLabel: 'Nouvelle conversation',
                                onAction: _nouvelleConversation,
                              )
                            : ListView.separated(
                                itemCount: _filtrees.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final conversation = _filtrees[index];
                                  final nom = _nomAffiche(conversation);
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        // Identité messagerie : dégradé
                                        // violet, initiales en or.
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            AppTheme.violetProfond,
                                            AppTheme.violetVif,
                                          ],
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _initiales(nom),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppTheme.or,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            nom,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight:
                                                  conversation.nonLus > 0
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          heureCourteConversation(
                                            conversation.lastMessageAt,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.violetProfond
                                                .withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Pastille de type (Directe /
                                        // Groupe / Pastorale) : fond or
                                        // clair, texte violet profond.
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.orClair,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            libelleTypeConversation(
                                              conversation.type,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.violetProfond,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                conversation.dernierMessage ??
                                                    'Aucun message pour l’instant.',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            if (conversation.nonLus > 0) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 20,
                                                  minHeight: 20,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.or,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  '${conversation.nonLus}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme
                                                        .violetProfond,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    onTap: () => _ouvrir(conversation),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Création : type, puis membres de la même église. La liste des
  /// membres vient de l'API, déjà limitée à l'église active : aucun
  /// groupe ne peut mélanger deux églises.
  Future<void> _nouvelleConversation() async {
    final api = context.read<AppState>().api;
    List<Member> membres;
    try {
      membres = (await api.getMembers(limit: 100)).membres;
    } catch (e) {
      if (mounted) showApiError(context, e);
      return;
    }
    if (!mounted) return;
    final creee = await showModalBottomSheet<ConversationMessagerie>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FeuilleNouvelleConversation(membres: membres),
    );
    if (creee != null && mounted) {
      await _ouvrir(creee);
    }
  }
}

/// Feuille de création d'une conversation : type, titre pour les
/// groupes, sélection de membres de la même église.
class _FeuilleNouvelleConversation extends StatefulWidget {
  final List<Member> membres;

  const _FeuilleNouvelleConversation({required this.membres});

  @override
  State<_FeuilleNouvelleConversation> createState() =>
      _FeuilleNouvelleConversationState();
}

class _FeuilleNouvelleConversationState
    extends State<_FeuilleNouvelleConversation> {
  String _type = 'directe';
  final _titreController = TextEditingController();
  final _selection = <String>{};
  bool _tousLesMembres = false;
  bool _enCours = false;

  @override
  void dispose() {
    _titreController.dispose();
    super.dispose();
  }

  List<Member> get _selectionnes {
    if (_type == 'groupe_eglise' && _tousLesMembres) {
      return widget.membres;
    }
    return widget.membres
        .where((m) => _selection.contains(m.id))
        .toList();
  }

  bool get _valide {
    if (_type == 'directe') return _selection.length == 1;
    return _selectionnes.isNotEmpty &&
        _titreController.text.trim().isNotEmpty;
  }

  Future<void> _creer() async {
    if (!_valide || _enCours) return;
    setState(() => _enCours = true);
    try {
      final conversation = await context
          .read<AppState>()
          .api
          .creerConversationMessagerie(
            type: _type,
            title: _type == 'directe'
                ? null
                : _titreController.text.trim(),
            participantMemberIds:
                _selectionnes.map((m) => m.id).toList(),
          );
      if (mounted) Navigator.of(context).pop(conversation);
    } catch (e) {
      if (mounted) {
        setState(() => _enCours = false);
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final estGroupe = _type != 'directe';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nouvelle conversation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final (valeur, libelle) in const [
                ('directe', 'Directe'),
                ('groupe_departement', 'Groupe de département'),
                ('groupe_eglise', 'Groupe d’église'),
              ])
                ChoiceChip(
                  label: Text(libelle),
                  selected: _type == valeur,
                  onSelected: (_) => setState(() {
                    _type = valeur;
                    _selection.clear();
                    _tousLesMembres = false;
                  }),
                ),
            ],
          ),
          if (estGroupe) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _titreController,
              // 16 px minimum : Safari iPhone ne zoome pas. Le plancher
              // est dans AppTheme (bodyLarge compensé).
              decoration: const InputDecoration(
                labelText: 'Nom du groupe',
                hintText: 'Par exemple : Chorale',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_type == 'groupe_eglise') ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tous les membres de l’église'),
              value: _tousLesMembres,
              onChanged: (valeur) => setState(
                () => _tousLesMembres = valeur ?? false,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _type == 'directe'
                ? 'Choisissez un membre de votre église.'
                : 'Choisissez les membres du groupe.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 280,
            child: _tousLesMembres && _type == 'groupe_eglise'
                ? Center(
                    child: Text(
                      '${widget.membres.length} membres seront ajoutés.',
                      style: const TextStyle(fontSize: 14),
                    ),
                  )
                : widget.membres.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun membre dans votre église.',
                          style: TextStyle(fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.membres.length,
                        itemBuilder: (context, index) {
                          final membre = widget.membres[index];
                          final choisi =
                              _selection.contains(membre.id);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(membre.fullName),
                            subtitle: Text(membre.matricule),
                            value: choisi,
                            onChanged: (valeur) => setState(() {
                              if (_type == 'directe') {
                                _selection.clear();
                                if (valeur ?? false) {
                                  _selection.add(membre.id);
                                }
                              } else if (valeur ?? false) {
                                _selection.add(membre.id);
                              } else {
                                _selection.remove(membre.id);
                              }
                            }),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _valide && !_enCours ? _creer : null,
              child: _enCours
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Créer la conversation'),
            ),
          ),
        ],
      ),
    );
  }
}
