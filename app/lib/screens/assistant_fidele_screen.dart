import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/cultes.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'cotisations_screen.dart';

/// Assistant automatisé de l’espace membre : réponses prédéfinies,
/// calculées uniquement à partir des vraies données de
/// l’application. Local seulement, aucune écriture serveur, aucun
/// appel IA, aucune réponse inventée, aucun texte biblique ou de
/// prière inventé. Sans donnée, l’assistant le dit. Toute autre
/// question renvoie vers Clavardage.
class AssistantFideleScreen extends StatefulWidget {
  const AssistantFideleScreen({super.key});

  @override
  State<AssistantFideleScreen> createState() => _AssistantFideleScreenState();
}

/// Une question suggérée et sa réponse, calculée depuis les données
/// réelles chargées par l’écran.
class _QuestionReponse {
  final String question;
  final String reponse;

  /// Ouvre l’écran lié, quand la réponse renvoie vers un écran.
  final Widget Function()? ouvrir;

  const _QuestionReponse({
    required this.question,
    required this.reponse,
    this.ouvrir,
  });
}

/// Réponse prédéfinie, fonction pure testable sans écran : la
/// question est reconnue par mot clé, la réponse vient du prochain
/// culte réel quand il y en a un, sinon l’assistant dit qu’il n’y
/// en a pas. Toute question inconnue renvoie vers Clavardage.
String reponseAssistant(String question, {Culte? prochainCulte}) {
  final normalisee = question.toLowerCase();
  if (normalisee.contains('culte')) {
    final culte = prochainCulte;
    if (culte == null) {
      return 'Aucun culte à venir pour le moment.';
    }
    final lieu = culte.lieu ?? 'Lieu à confirmer';
    final quand = culte.date == null
        ? 'Date à confirmer'
        : formatDateTimeSansDecalage(culte.date);
    return 'Prochain culte : ${culte.titre}, $quand, $lieu.';
  }
  if (normalisee.contains('carte')) {
    return 'Votre carte de membre s’affiche librement, sans paiement, '
        'dans l’onglet Carte.';
  }
  if (normalisee.contains('camp')) {
    return 'Pour le moment, aucun camp n’est affiché dans Mes camps.';
  }
  if (normalisee.contains('cotisation')) {
    return 'Retrouvez vos cotisations dans Mes cotisations.';
  }
  if (normalisee.contains('prière') || normalisee.contains('priere')) {
    return 'Votre sujet de prière privé se dépose depuis l’accueil, '
        'dans « Sujet de prière privé ». Il reste confidentiel : '
        'seuls les responsables de prière le lisent.';
  }
  return 'Je ne sais pas répondre, écrivez à votre église dans '
      'Clavardage.';
}

class _MessageAssistant {
  final String texte;
  final bool deMoi;

  /// Ouvre l’écran lié, quand la réponse renvoie vers un écran.
  final Widget Function()? ouvrir;

  const _MessageAssistant({
    required this.texte,
    required this.deMoi,
    this.ouvrir,
  });
}

class _AssistantFideleScreenState extends State<AssistantFideleScreen> {
  final _saisieController = TextEditingController();
  final _defilementController = ScrollController();
  final List<_MessageAssistant> _messages = [
    const _MessageAssistant(
      texte: 'Bonjour, je suis l’assistant e-System. '
          'Posez-moi une question, ou choisissez un sujet ci-dessous.',
      deMoi: false,
    ),
  ];
  Culte? _prochainCulte;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _chargerProchainCulte();
  }

  @override
  void dispose() {
    _saisieController.dispose();
    _defilementController.dispose();
    super.dispose();
  }

  Future<void> _chargerProchainCulte() async {
    try {
      final cultes = await context.read<AppState>().api.getMesCultes();
      final maintenant = DateTime.now();
      final aujourdHui =
          DateTime(maintenant.year, maintenant.month, maintenant.day);
      final aVenir = cultes.where((c) {
        final date = c.date;
        if (date == null) return false;
        final jour = DateTime(date.year, date.month, date.day);
        return !jour.isBefore(aujourdHui);
      }).toList()
        ..sort((a, b) => a.date!.compareTo(b.date!));
      if (mounted) {
        setState(() {
          _prochainCulte = aVenir.isEmpty ? null : aVenir.first;
          _charge = true;
        });
      }
    } catch (_) {
      // Sans culte lisible, l’assistant dit qu’il n’y en a pas.
      if (mounted) setState(() => _charge = true);
    }
  }

  List<_QuestionReponse> get _suggestions => [
        _QuestionReponse(
          question: 'Quel est le prochain culte ?',
          reponse: reponseAssistant(
            'prochain culte',
            prochainCulte: _prochainCulte,
          ),
        ),
        const _QuestionReponse(
          question: 'Comment avoir ma carte de membre ?',
          reponse: 'Votre carte de membre s’affiche librement, sans '
              'paiement, dans l’onglet Carte.',
        ),
        const _QuestionReponse(
          question: 'Y a-t-il un camp à venir ?',
          reponse: 'Pour le moment, aucun camp n’est affiché dans '
              'Mes camps.',
        ),
        _QuestionReponse(
          question: 'Où sont mes cotisations ?',
          reponse: reponseAssistant('cotisations'),
          ouvrir: () => const CotisationsScreen(),
        ),
        const _QuestionReponse(
          question: 'Comment déposer un sujet de prière privé ?',
          reponse: 'Votre sujet de prière privé se dépose depuis '
              'l’accueil, dans « Sujet de prière privé ». Il reste '
              'confidentiel : seuls les responsables de prière le '
              'lisent.',
        ),
      ];

  void _poser(String question) {
    final texte = question.trim();
    if (texte.isEmpty) return;
    final suggestion = _suggestions
        .where((s) => s.question == texte)
        .toList();
    final reponse = suggestion.isNotEmpty
        ? suggestion.first
        : _QuestionReponse(
            question: texte,
            reponse: reponseAssistant(texte, prochainCulte: _prochainCulte),
          );
    setState(() {
      _messages.add(_MessageAssistant(texte: texte, deMoi: true));
      _messages.add(
        _MessageAssistant(
          texte: reponse.reponse,
          deMoi: false,
          ouvrir: reponse.ouvrir,
        ),
      );
    });
    _saisieController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilementController.hasClients) {
        _defilementController.jumpTo(
          _defilementController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant e-System')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            color: PaletteMembre.surfaceDouce,
            child: const Text(
              'Réponses automatiques',
              style: TextStyle(
                fontSize: AppFontSizes.s12_5,
                fontWeight: FontWeight.bold,
                color: PaletteMembre.violetRoyal,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _defilementController,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.deMoi
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: message.deMoi
                            ? PaletteMembre.violetRoyal
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppRadii.md),
                        border: message.deMoi
                            ? null
                            : Border.all(
                                color: PaletteMembre.bordure,
                              ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.texte,
                            style: TextStyle(
                              fontSize: AppFontSizes.s14,
                              color: message.deMoi
                                  ? Colors.white
                                  : PaletteMembre.texte,
                            ),
                          ),
                          if (message.ouvrir != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => message.ouvrir!(),
                                ),
                              ),
                              child: const Text('Voir mes cotisations'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_charge)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      label: Text(
                        suggestion.question,
                        style: const TextStyle(
                          fontSize: AppFontSizes.s12_5,
                        ),
                      ),
                      onPressed: () => _poser(suggestion.question),
                    ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.only(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              top: AppSpacing.xs,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  AppSpacing.xs,
            ),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saisieController,
                    decoration: const InputDecoration(
                      hintText: 'Écrire une question…',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _poser,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(Icons.send),
                    tooltip: 'Envoyer',
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: PaletteMembre.violetRoyal,
                    ),
                    onPressed: () => _poser(_saisieController.text),
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
