import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/announcement.dart';
import '../models/attestation.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/fidele.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/carte_membre_vedette.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';
import '../widgets/soft_card.dart';
import '../screens/bible_fidele_screen.dart';
import '../screens/carte_fidele_screen.dart';
import '../screens/cotisations_screen.dart';
import '../screens/journal_screen.dart';
import '../screens/mes_attestations_screen.dart';
import '../screens/messagerie_liste_screen.dart';
import '../services/messagerie_lecture_service.dart';

/// Contenu partagé des deux écrans d'accueil fidèle (tranche 3,
/// E-FI1) : « fidele-accueil » (onglet Accueil de la coquille
/// fidèle) et « membre » (Espace membre, ouvert depuis Modules).
/// Mêmes données, même chargement, mêmes sections, seul l'ordre
/// des blocs et la section outils changent, selon la projection :
/// - fidele-accueil : « Actions rapides », 4 outils de la maquette
///   (écran 37), camps et attestations avant Prière du jour et
///   Sujet de prière privé.
/// - membre : « Actions rapides », 4 outils, Prière du jour et Sujet
///   de prière privé avant camps et attestations.
/// Contenu seul, sans Scaffold ni barre : la coquille fidèle
/// fournit l'écran et la barre du bas. En-tête, carte membre premium,
/// prochain culte avec compte à rebours et « Je serai présent »,
/// Mon Parcours, chiffres réels, Mes camps, Mes attestations,
/// Prière du jour, Sujet de prière privé, devise. Rien d'inventé :
/// que des données réelles, et des états vides chaleureux quand
/// il n'y a rien.
class FideleHomeContenu extends StatefulWidget {
  /// Titre de la section outils : « Mes accès » ou
  /// « Actions rapides ».
  final String titreOutils;

  /// Conservé pour l'appelant : l'ordre des blocs est désormais fixé
  /// par la maquette (écran 37), Prière du jour et Sujet de prière
  /// privé avant Mes camps et Mes attestations, pour les deux écrans.
  final bool priereAvantCamps;

  const FideleHomeContenu({
    super.key,
    required this.titreOutils,
    required this.priereAvantCamps,
  });

  @override
  State<FideleHomeContenu> createState() => _FideleHomeContenuState();
}

class _FideleHomeContenuState extends State<FideleHomeContenu> {
  late Future<FideleProfil> _profilFuture;
  late Future<MaCarte?> _carteFuture;
  late Future<List<Culte>> _cultesFuture;
  late Future<List<Presence>> _presencesFuture;
  late Future<List<Contribution>> _contributionsFuture;
  late Future<List<Attestation>> _attestationsFuture;
  late Future<List<Announcement>> _annoncesFuture;

  /// Confirmation de présence par culte, gardée en mémoire locale
  /// (le serveur est la source, on met à jour après chaque appel).
  final Map<String, bool> _rsvpParCulte = {};

  /// Conversations de messagerie non lues, pour la pastille de la
  /// tuile « Messagerie » (design couleurs messagerie, 16 nov. 2026).
  int _messagerieNonLus = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    final api = context.read<AppState>().api;
    _profilFuture = api.getMoi();
    // Badge de la tuile « Messagerie » : même calcul local que côté
    // admin (MessagerieLectureService, sans route serveur). Un échec
    // ne bloque pas l'accueil, la pastille reste cachée.
    _chargerNonLusMessagerie();
    _carteFuture = api.getMaCarte();
    // « Cultes à venir » : on ne garde que les cultes d'aujourd'hui ou
    // après. Un culte sans date exploitable est gardé plutôt que caché.
    _cultesFuture = api.getMesCultes().then((cultes) {
      final now = DateTime.now();
      final aujourdHui = DateTime(now.year, now.month, now.day);
      return cultes.where((c) {
        final date = c.date;
        if (date == null) return true;
        final jour = DateTime(date.year, date.month, date.day);
        return !jour.isBefore(aujourdHui);
      }).toList();
    });
    _presencesFuture = api.getMesPresences();
    _contributionsFuture = api.getMesContributions();
    _attestationsFuture = api.getMesAttestations();
    _annoncesFuture = api.getMesAnnonces();
  }

  Future<void> _chargerNonLusMessagerie() async {
    final api = context.read<AppState>().api;
    try {
      await MessagerieLectureService.instance.charger();
      final conversations = await api.getConversationsMessagerie();
      if (!mounted) return;
      setState(
        () => _messagerieNonLus = MessagerieLectureService.instance
            .compterConversationsNonLues(conversations),
      );
    } catch (_) {
      // Sans messagerie lisible, pas de badge.
    }
  }

  Future<void> _refresh() async {
    setState(_charger);
  }

  void _voirMaCarte() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CarteFideleScreen(),
      ),
    );
  }

  void _voirMesAttestations() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MesAttestationsScreen(),
      ),
    );
  }

  Future<void> _basculerPresence(Culte culte, bool confirme) async {
    try {
      if (confirme) {
        await context.read<AppState>().api.confirmerPresenceCulte(culte.id);
      } else {
        await context.read<AppState>().api.annulerPresenceCulte(culte.id);
      }
      if (mounted) {
        setState(() => _rsvpParCulte[culte.id] = confirme);
        showSuccess(
          context,
          confirme
              ? 'Présence confirmée.'
              : 'Présence annulée.',
        );
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête de l'espace connecté : nom et logo de
                  // l'église (règle d'Axel, 14 novembre 2026), pas le
                  // logo e-System Church en grand.
                  EnteteEspace(
                    eglise: context.watch<AppState>().church,
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<FideleProfil>(
                    future: _profilFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const AppLoading();
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return AppError(
                          message: snapshot.error?.toString() ??
                              'Impossible de charger votre profil.',
                          onRetry: () => setState(_charger),
                        );
                      }
                      final profil = snapshot.data!;
                      final prenom = profil.user.fullName
                          .trim()
                          .split(' ')
                          .firstWhere(
                            (e) => e.isNotEmpty,
                            orElse: () => '',
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              // Design couleurs messagerie (16 nov. 2026) :
                              // la Projection (.m-hero) montre ce héros en
                              // blanc, bordure fine, date en or ; la couleur
                              // demandée par Axel va au-delà de la
                              // Projection, appliquée quand même dans sa
                              // palette : dégradé violet, textes blancs,
                              // date en or clair. Structure gardée (date,
                              // salutation, sous-titre). Même motif que la
                              // carte « Aujourd'hui » de l'accueil admin.
                              // Jamais de texte blanc sur or.
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppTheme.violetProfond,
                                  AppTheme.violetSecondaire,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatDate(DateTime.now()),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.orClair,
                                        fontSize: 10.5,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bonjour${prenom.isEmpty ? '' : ', $prenom'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontSize: 20,
                                        color: Colors.white,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bienvenue dans votre église',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontSize: 13.5,
                                        color: Colors.white,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Retrouvez ici votre carte, votre '
                                  'parcours et vos prochains rendez-vous.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontSize: 12,
                                        color:
                                            Colors.white.withValues(alpha: 0.85),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (profil.church.banniereUrl != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                profil.church.banniereUrl!,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          CarteMembreVedette(
                            profil: profil,
                            onVoirCarte: _voirMaCarte,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _ProchainCulte(
                    future: _cultesFuture,
                    rsvpParCulte: _rsvpParCulte,
                    onBasculerPresence: _basculerPresence,
                  ),
                  const SizedBox(height: 8),
                  _ParcoursSection(future: _carteFuture),
                  const SizedBox(height: 8),
                  _ChiffresSection(
                    presencesFuture: _presencesFuture,
                    contributionsFuture: _contributionsFuture,
                    attestationsFuture: _attestationsFuture,
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Verset du jour'),
                  const _VersetDuJour(),
                  const SizedBox(height: 8),
                  // Ordre maquette, écran 37 : Prochain culte, Mon
                  // Parcours, chiffres, Verset du jour, Actions
                  // rapides, Prière du jour, Sujet de prière privé,
                  // Mes camps, Mes attestations, Annonces, devise.
                  // Le Sujet de prière privé reste sur l'accueil : c'est
                  // la seule entrée vers le formulaire de prière, la
                  // coquille fidèle n'a pas d'onglet Prière.
                  SectionTitle(title: widget.titreOutils),
                  _GrilleOutils(
                    onBible: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        // La Bible est un écran sans Scaffold propre : elle
                        // vit aussi dans la coquille fidèle sous EnTeteClair.
                        // Poussée seule depuis la grille, on l'habille ici
                        // (barre « Ma Bible » + fond clair), comme les autres
                        // écrans fidèles (École, Cotisations…).
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Bible et école biblique'),
                          ),
                          body: const BibleFideleScreen(),
                        ),
                      ),
                    ),
                    onCotisations: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CotisationsScreen(),
                      ),
                    ),
                    onJournal: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JournalScreen(),
                      ),
                    ),
                    onMessagerie: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MessagerieListeScreen(),
                      ),
                    ),
                    badgeMessagerie: _messagerieNonLus,
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Prière du jour'),
                  const _PriereDuJourBloc(),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Sujet de prière privé'),
                  _SujetPriereSection(profilFuture: _profilFuture),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Mes camps', taille: 15),
                  const _CampsVide(),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Mes attestations', taille: 15),
                  _AttestationsResume(
                    future: _attestationsFuture,
                    onVoir: _voirMesAttestations,
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Annonces de mon église'),
                  _AnnoncesEgliseSection(future: _annoncesFuture),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Tu es un don de Dieu',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.orFonce,
                            fontSize: 12.5,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grille 2 par 2 des accès du fidèle (Projection, « Actions
/// rapides ») : 4 tuiles, Ma Bible, Mes cotisations, Mon journal,
/// Messagerie, au texte complet, « Ouvrir » sur sa propre ligne en
/// bas de chaque carte. L'école biblique s'ouvre depuis l'onglet
/// Bible, le rendez-vous depuis le menu Plus : un seul point
/// d'entrée chacun. La tuile « Messagerie » reprend le modèle
/// « Message à mon église » de la Projection (icône or, titre bleu
/// nuit, flèche « Ouvrir → » en or) et ouvre la nouvelle messagerie,
/// échanges entre membres de l'église (design couleurs messagerie,
/// 16 nov. 2026). Le fil privé « Message à mon église » (P1) reste
/// accessible par l'onglet « Messages », inchangé : jamais deux
/// entrées pour la même fonction, et le libellé ne fait pas croire
/// au fidèle qu'il parle à son église mère quand il parle aux
/// membres de son église.
class _GrilleOutils extends StatelessWidget {
  final VoidCallback onBible;
  final VoidCallback onCotisations;
  final VoidCallback onJournal;
  final VoidCallback onMessagerie;

  /// Conversations de messagerie non lues, pastille or sur la tuile.
  final int badgeMessagerie;

  const _GrilleOutils({
    required this.onBible,
    required this.onCotisations,
    required this.onJournal,
    required this.onMessagerie,
    this.badgeMessagerie = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Hauteur fixe ~230 px, quel que soit l'écran : assez pour
            // un titre sur 2 lignes, 4 lignes de description et le
            // lien Ouvrir, sans le vide de l'ancien ratio 0,7
            // (~330 px de vide à 1280 px). Un ratio fixe de 1,3
            // déborderait sur téléphone 390 px, la hauteur fixe non.
            final largeurTuile = (constraints.maxWidth - 12) / 2;
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: largeurTuile / 230,
              children: [
                _TuileAcces(
                  icone: Icons.menu_book_outlined,
                  titre: 'Ma Bible',
                  sousTitre:
                      'Lire et rechercher dans l’Ancien et le Nouveau Testament.',
                  onTap: onBible,
                ),
                _TuileAcces(
                  icone: Icons.account_balance_wallet_outlined,
                  titre: 'Mes cotisations',
                  sousTitre: 'Historique, reçus et total.',
                  onTap: onCotisations,
                ),
                _TuileAcces(
                  icone: Icons.edit_outlined,
                  titre: 'Mon journal',
                  sousTitre: 'Notes privées, jamais partagées.',
                  onTap: onJournal,
                ),
                _TuileAcces(
                  icone: Icons.chat_bubble_outline,
                  titre: 'Messagerie',
                  sousTitre:
                      'Conversations avec les membres de votre église.',
                  badge: badgeMessagerie,
                  onTap: onMessagerie,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TuileAcces extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  /// Nombre de conversations non lues : pastille or en coin, cachée
  /// à 0. Nul pour les tuiles sans compteur.
  final int? badge;

  const _TuileAcces({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final carte = Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.orClair,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: AppTheme.orFonce, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                titre,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13.5,
                    ),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                sousTitre,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                    ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Ouvrir →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.orAttention,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    final total = badge ?? 0;
    if (total <= 0) return carte;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        carte,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.or,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              '$total',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.violetProfond,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Prochain culte (maquette, écran 37) : carte blanche, titre violet
/// et pastille or « À venir », compte à rebours (jours, heures,
/// minutes), lieu et heure côte à côte, puis « Je serai présent ».
/// Sans culte : mêmes cases à « -- », lieu et heure « à confirmer »,
/// sans bouton (aucun culte à confirmer).
class _ProchainCulte extends StatelessWidget {
  final Future<List<Culte>> future;
  final Map<String, bool> rsvpParCulte;
  final Future<void> Function(Culte culte, bool confirme)
      onBasculerPresence;

  const _ProchainCulte({
    required this.future,
    required this.rsvpParCulte,
    required this.onBasculerPresence,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Culte>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(message: snapshot.error.toString(), onRetry: null);
        }
        final cultes = [...(snapshot.data ?? [])]
          ..sort((a, b) {
            final da = a.date;
            final db = b.date;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        final culte = cultes.isEmpty ? null : cultes.first;
        final confirme = culte == null
            ? false
            : rsvpParCulte[culte.id] ?? culte.seraiPresent;
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.bordure),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Prochain culte',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.violetProfond,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.or,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'À venir',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.violetProfond,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (culte != null) ...[
                const SizedBox(height: 8),
                Text(
                  culte.titre,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _CompteRebours(date: culte?.date),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIEU',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          culte?.lieu ?? 'Lieu à confirmer',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HEURE',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          culte?.date != null
                              ? formatDateTime(culte!.date)
                              : 'Heure à confirmer',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (culte?.orateur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Avec ${culte!.orateur}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (culte != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        onBasculerPresence(culte, !confirme),
                    icon: Icon(
                      confirme
                          ? Icons.check_circle_outline
                          : Icons.event_available_outlined,
                    ),
                    label: Text(
                      confirme ? 'Présence confirmée' : 'Je serai présent',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Compte à rebours en trois cases : jours, heures, minutes.
/// « -- » quand le culte n'a pas de date exploitable.
class _CompteRebours extends StatefulWidget {
  final DateTime? date;

  const _CompteRebours({required this.date});

  @override
  State<_CompteRebours> createState() => _CompteReboursState();
}

class _CompteReboursState extends State<_CompteRebours> {
  Timer? _timer;
  DateTime _maintenant = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() => _maintenant = DateTime.now());
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    String jours = '--';
    String heures = '--';
    String minutes = '--';
    if (date != null) {
      final reste = date.difference(_maintenant);
      if (!reste.isNegative) {
        jours = '${reste.inDays}';
        heures = '${reste.inHours % 24}';
        minutes = '${reste.inMinutes % 60}';
      }
    }
    return Row(
      children: [
        _CaseCompte(valeur: jours, unite: 'Jours'),
        const SizedBox(width: 8),
        _CaseCompte(valeur: heures, unite: 'Heures'),
        const SizedBox(width: 8),
        _CaseCompte(valeur: minutes, unite: 'Minutes'),
      ],
    );
  }
}

class _CaseCompte extends StatelessWidget {
  final String valeur;
  final String unite;

  const _CaseCompte({required this.valeur, required this.unite});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.fondPapier,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              valeur,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                  ),
            ),
            Text(
              unite,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mon Parcours : 4 étapes, sans rien inventer. Inscription faite dès
/// que le membre existe, Baptême fait quand une date de baptême est
/// enregistrée, Intégration et Service restent « Étape à venir » :
/// aucune règle n'est définie pour elles. Pourcentage = étapes faites / 4.
class _ParcoursSection extends StatelessWidget {
  final Future<MaCarte?> future;

  const _ParcoursSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaCarte?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        final carte = snapshot.data;
        final membre = carte?.member;
        final inscriptionFaite = membre != null;
        final baptemeFait = membre?.baptemeDate != null &&
            membre!.baptemeDate!.isNotEmpty;
        final faites = [inscriptionFaite, baptemeFait, false, false]
            .where((e) => e)
            .length;
        final pourcentage = (faites * 100 / 4).round();
        return SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.route_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mon Parcours — $pourcentage %',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Vos étapes, une par une, au rythme de votre croissance.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: faites / 4,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: AppTheme.or,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              _EtapeParcours(
                numero: 1,
                titre: 'Inscription',
                faite: inscriptionFaite,
              ),
              _EtapeParcours(
                numero: 2,
                titre: 'Baptême',
                faite: baptemeFait,
              ),
              const _EtapeParcours(
                numero: 3,
                titre: 'Intégration',
                faite: false,
              ),
              const _EtapeParcours(
                numero: 4,
                titre: 'Service',
                faite: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EtapeParcours extends StatelessWidget {
  final int numero;
  final String titre;
  final bool faite;

  const _EtapeParcours({
    required this.numero,
    required this.titre,
    required this.faite,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor:
                faite ? AppTheme.or : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: faite
                // T13, D02 : jamais de blanc sur or (2,24:1, icône
                // 16 px incluse). Bleu nuit sur or : 7,36:1.
                ? const Icon(Icons.check, size: 16, color: AppTheme.violetProfond)
                : Text(
                    '$numero',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 12.5),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titre,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontSize: 13.5),
            ),
          ),
          Text(
            faite ? 'Étape faite.' : 'Étape à venir.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Chiffres réels du serveur : présences, contributions, attestations.
class _ChiffresSection extends StatelessWidget {
  final Future<List<Presence>> presencesFuture;
  final Future<List<Contribution>> contributionsFuture;
  final Future<List<Attestation>> attestationsFuture;

  const _ChiffresSection({
    required this.presencesFuture,
    required this.contributionsFuture,
    required this.attestationsFuture,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<dynamic>>>(
      future: Future.wait(
          [presencesFuture, contributionsFuture, attestationsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        final presences = snapshot.data?[0] as List<Presence>? ?? [];
        final contributions =
            snapshot.data?[1] as List<Contribution>? ?? [];
        final attestations =
            snapshot.data?[2] as List<Attestation>? ?? [];
        return Row(
          children: [
            Expanded(
              child: _ChiffreCarte(
                valeur: '${presences.length}',
                libelle: 'Présences',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChiffreCarte(
                valeur: '${contributions.length}',
                libelle: 'Contributions',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChiffreCarte(
                valeur: '${attestations.length}',
                libelle: 'Attestations',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChiffreCarte extends StatelessWidget {
  final String valeur;
  final String libelle;

  const _ChiffreCarte({required this.valeur, required this.libelle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text(
              valeur,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              libelle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mes camps : état vide, les inscriptions aux camps apparaîtront
/// ici quand le serveur en renverra.
class _CampsVide extends StatelessWidget {
  const _CampsVide();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.event_outlined,
      message: 'Aucun camp pour le moment. '
          'Vos inscriptions aux camps apparaîtront ici.',
    );
  }
}

/// Mes attestations : compteur et lien vers l'écran, état vide sinon.
class _AttestationsResume extends StatelessWidget {
  final Future<List<Attestation>> future;
  final VoidCallback onVoir;

  const _AttestationsResume({required this.future, required this.onVoir});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Attestation>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        final n = snapshot.data?.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Certificats et attestations reçus.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Chip(label: Text('$n document${n > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11.5))),
            const SizedBox(height: 8),
            if (n == 0)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'Aucune attestation pour le moment. '
                    'Vos attestations délivrées par la structure '
                    'apparaîtront ici.',
              )
            else
              FilledButton.icon(
                onPressed: onVoir,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Voir mes attestations', style: TextStyle(fontSize: 13.5)),
              ),
          ],
        );
      },
    );
  }
}

/// Verset du jour (maquette, écran 37) : texte exact de la maquette,
/// Psaume 118, 24.
class _VersetDuJour extends StatelessWidget {
  const _VersetDuJour();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '« Voici le jour que l’Éternel a fait : qu’il soit pour nous un sujet d’allégresse et de joie ! »',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Psaume 118, 24',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.orFonce,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// Annonces de mon église (maquette, écran 37) : les 3 dernières
/// annonces de l'église du fidèle, même source que l'accueil fidèle
/// (`GET /moi/annonces`).
class _AnnoncesEgliseSection extends StatelessWidget {
  final Future<List<Announcement>> future;

  const _AnnoncesEgliseSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Announcement>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        final annonces = (snapshot.data ?? const <Announcement>[]).take(3).toList();
        if (annonces.isEmpty) {
          return const EmptyState(
            icon: Icons.campaign_outlined,
            message: 'Aucune annonce de mon église',
          );
        }
        return Column(
          children: [
            for (final a in annonces)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(a.title, style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    a.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Prière du jour (projection, écrans « membre » et
/// « fidele-accueil ») : emplacement prêt, son texte sera branché
/// depuis la source fournie par la structure, jamais inventé.
class _PriereDuJourBloc extends StatelessWidget {
  const _PriereDuJourBloc();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Un moment calme pour commencer la journée.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Le texte s’affichera ici.',
                style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Sujet de prière privé : attend le profil pour rattacher le
/// sujet au membre, ne montre rien tant que le profil n'est pas là.
class _SujetPriereSection extends StatelessWidget {
  final Future<FideleProfil> profilFuture;

  const _SujetPriereSection({required this.profilFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FideleProfil>(
      future: profilFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final profil = snapshot.data!;
        return _SujetPrierePrive(
          memberId: profil.memberId,
          membreNom: profil.user.fullName,
        );
      },
    );
  }
}

/// Sujet de prière privé : déposer un sujet de prière privé, coché
/// confidentiel par défaut. Le sujet part par la route existante
/// des demandes de prière, rattaché au membre quand le compte est
/// lié. Aucun texte de prière inventé : la Bible reste un
/// emplacement prêt, son texte sera branché depuis la source
/// fournie par la structure, jamais inventé.
class _SujetPrierePrive extends StatefulWidget {
  final String? memberId;
  final String membreNom;

  const _SujetPrierePrive({required this.memberId, required this.membreNom});

  @override
  State<_SujetPrierePrive> createState() => _SujetPrierePriveState();
}

class _SujetPrierePriveState extends State<_SujetPrierePrive> {
  final _sujetController = TextEditingController();
  final _detailsController = TextEditingController();
  var _confidentiel = true;
  var _envoi = false;

  @override
  void dispose() {
    _sujetController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _deposer() async {
    final sujet = _sujetController.text.trim();
    if (sujet.length < 2) {
      showApiError(context, 'Écrivez votre sujet de prière.');
      return;
    }
    setState(() => _envoi = true);
    try {
      await context.read<AppState>().api.createDemandePriere(
            sujet: sujet,
            memberId: widget.memberId,
            demandeurNom: widget.membreNom,
            details: _detailsController.text.trim().isEmpty
                ? null
                : _detailsController.text.trim(),
            confidentiel: _confidentiel,
          );
      if (!mounted) return;
      _sujetController.clear();
      _detailsController.clear();
      showSuccess(context, 'Votre sujet de prière a été déposé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ma demande de prière',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sujetController,
            decoration: const InputDecoration(
              labelText: 'Écrire ma demande',
            ),
            maxLength: 300,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            decoration: const InputDecoration(
              labelText: 'Détails (facultatif)',
            ),
            maxLines: 3,
          ),
          SwitchListTile(
            title: const Text('Demande confidentielle', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Seuls les responsables de prière la lisent.', style: TextStyle(fontSize: 11.5)),
            value: _confidentiel,
            onChanged: (v) => setState(() => _confidentiel = v),
          ),
          const Text(
            'Pour soi-même seulement — jamais au nom d’un autre. '
            'Confidentielle : seuls les responsables de prière la lisent.',
            style: TextStyle(fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _envoi ? null : _deposer,
            icon: const Icon(Icons.favorite_outline),
            label: Text(_envoi ? 'Envoi…' : 'Envoyer ma demande', style: const TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}
