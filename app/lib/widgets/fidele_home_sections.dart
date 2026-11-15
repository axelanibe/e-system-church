import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
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
import '../screens/ecole_biblique_screen.dart';
import '../screens/journal_screen.dart';
import '../screens/mes_attestations_screen.dart';
import '../screens/messages_fidele_screen.dart';
import '../screens/rendez_vous_screen.dart';

/// Contenu partagé des deux écrans d'accueil fidèle (tranche 3,
/// E-FI1) : « fidele-accueil » (onglet Accueil de la coquille
/// fidèle) et « membre » (Espace membre, ouvert depuis Modules).
/// Mêmes données, même chargement, mêmes sections, seul l'ordre
/// des blocs et la section outils changent, selon la projection :
/// - fidele-accueil : « Mes accès », 6 outils dont Prendre
///   rendez-vous, camps et attestations avant Prière du jour et
///   Sujet de prière privé.
/// - membre : « Actions rapides », 5 outils sans Prendre
///   rendez-vous, Prière du jour et Sujet de prière privé avant
///   camps et attestations.
/// Contenu seul, sans Scaffold ni barre : la coquille fidèle
/// fournit l'écran et la barre du bas, EspaceMembreScreen fournit
/// son Scaffold et son AppBar. En-tête, carte membre premium,
/// prochain culte avec compte à rebours et « Je serai présent »,
/// Mon Parcours, chiffres réels, Mes camps, Mes attestations,
/// Prière du jour, Sujet de prière privé, devise. Rien d'inventé :
/// que des données réelles, et des états vides chaleureux quand
/// il n'y a rien. En aperçu admin (Voir l'espace fidèle), seules
/// les données du profil se chargent, le reste montre des états
/// vides.
class FideleHomeContenu extends StatefulWidget {
  /// Titre de la section outils : « Mes accès » ou
  /// « Actions rapides ».
  final String titreOutils;

  /// Vrai pour « fidele-accueil » : la grille outils gagne la
  /// carte pleine largeur « Prendre rendez-vous ».
  final bool avecRendezVous;

  /// Vrai pour « membre » : Prière du jour et Sujet de prière
  /// privé passent avant Mes camps et Mes attestations.
  final bool priereAvantCamps;

  const FideleHomeContenu({
    super.key,
    required this.titreOutils,
    required this.avecRendezVous,
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

  /// Confirmation de présence par culte, gardée en mémoire locale
  /// (le serveur est la source, on met à jour après chaque appel).
  final Map<String, bool> _rsvpParCulte = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    final api = context.read<AppState>().api;
    final apercu = context.read<AppState>().apercuFidele;
    _profilFuture = api.getMoi();
    if (apercu) {
      // Aperçu admin : pas de membre lié, états vides partout.
      _carteFuture = Future.value(null);
      _cultesFuture = Future.value(const []);
      _presencesFuture = Future.value(const []);
      _contributionsFuture = Future.value(const []);
      _attestationsFuture = Future.value(const []);
      return;
    }
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
    final apercu = context.read<AppState>().apercuFidele;
    if (apercu) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connectez-vous avec un compte fidèle pour confirmer '
            'votre présence.',
          ),
        ),
      );
      return;
    }
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
                  // En aperçu admin : bandeau de retour vers l'espace
                  // admin (maquette de refonte), en plus du retour de
                  // l'en-tête.
                  if (context.watch<AppState>().apercuFidele) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.orClair,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.or),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: AppTheme.orAttention,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Mode Aperçu Fidèle',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.violetProfond,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => context
                                .read<AppState>()
                                .sortirApercuFidele(),
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: const Text('Retour Admin'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(4, 8, 4, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatDate(DateTime.now()),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.orFonce,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bonjour${prenom.isEmpty ? '' : ', $prenom'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bienvenue dans votre église',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profil.church.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Retrouvez ici votre carte, votre '
                                  'parcours et vos prochains rendez-vous.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
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
                  const SectionTitle(title: 'Prochain culte'),
                  _ProchainCulte(
                    future: _cultesFuture,
                    rsvpParCulte: _rsvpParCulte,
                    onBasculerPresence: _basculerPresence,
                  ),
                  const SizedBox(height: 8),
                  SectionTitle(title: widget.titreOutils),
                  _GrilleOutils(
                    avecRendezVous: widget.avecRendezVous,
                    onBible: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        // La Bible est un écran sans Scaffold propre : elle
                        // vit aussi dans la coquille fidèle sous EnTeteClair.
                        // Poussée seule depuis la grille, on l'habille ici
                        // (barre « Ma Bible » + fond clair), comme les autres
                        // écrans fidèles (École, Cotisations…).
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Ma Bible'),
                          ),
                          body: const BibleFideleScreen(),
                        ),
                      ),
                    ),
                    onEcole: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EcoleBibliqueScreen(),
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
                    onMessages: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MessagesFideleScreen(),
                      ),
                    ),
                    onRendezVous: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RendezVousScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Mon Parcours'),
                  _ParcoursSection(future: _carteFuture),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Vos chiffres'),
                  _ChiffresSection(
                    presencesFuture: _presencesFuture,
                    contributionsFuture: _contributionsFuture,
                    attestationsFuture: _attestationsFuture,
                  ),
                  const SizedBox(height: 8),
                  // Ordre des blocs selon la projection : l'écran
                  // « membre » met Prière du jour et Sujet de prière
                  // privé avant Mes camps et Mes attestations,
                  // « fidele-accueil » fait l'inverse.
                  if (widget.priereAvantCamps) ...[
                    const SectionTitle(title: 'Prière du jour'),
                    const _PriereDuJourBloc(),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Sujet de prière privé'),
                    _SujetPriereSection(profilFuture: _profilFuture),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Mes camps'),
                    const _CampsVide(),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Mes attestations'),
                    _AttestationsResume(
                      future: _attestationsFuture,
                      onVoir: _voirMesAttestations,
                    ),
                  ] else ...[
                    const SectionTitle(title: 'Mes camps'),
                    const _CampsVide(),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Mes attestations'),
                    _AttestationsResume(
                      future: _attestationsFuture,
                      onVoir: _voirMesAttestations,
                    ),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Prière du jour'),
                    const _PriereDuJourBloc(),
                    const SizedBox(height: 8),
                    const SectionTitle(title: 'Sujet de prière privé'),
                    _SujetPriereSection(profilFuture: _profilFuture),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Tu es un don de Dieu',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.orFonce,
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

/// Grille 2 par 2 des accès du fidèle, au texte complet : titres
/// entiers, descriptions complètes, « Ouvrir » sur sa propre ligne
/// en bas de chaque carte (maquette de refonte). Sur
/// « fidele-accueil », « Prendre rendez-vous » est une carte pleine
/// largeur sous la grille ; sur « membre », elle est absente.
class _GrilleOutils extends StatelessWidget {
  final bool avecRendezVous;
  final VoidCallback onBible;
  final VoidCallback onEcole;
  final VoidCallback onCotisations;
  final VoidCallback onJournal;
  final VoidCallback onMessages;
  final VoidCallback onRendezVous;

  const _GrilleOutils({
    required this.avecRendezVous,
    required this.onBible,
    required this.onEcole,
    required this.onCotisations,
    required this.onJournal,
    required this.onMessages,
    required this.onRendezVous,
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
                  icone: Icons.school_outlined,
                  titre: 'École biblique',
                  sousTitre: 'Cours, leçons et ma progression.',
                  onTap: onEcole,
                ),
                _TuileAcces(
                  icone: Icons.mail_outline,
                  titre: 'Message à mon église',
                  sousTitre: 'Messagerie privée, dans l’application.',
                  onTap: onMessages,
                ),
              ],
            );
          },
        ),
        if (avecRendezVous) ...[
          const SizedBox(height: 12),
          _TuileLarge(
            icone: Icons.event_available_outlined,
            titre: 'Prendre rendez-vous',
            onTap: onRendezVous,
          ),
        ],
      ],
    );
  }
}

class _TuileAcces extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _TuileAcces({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                sousTitre,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Ouvrir →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.orAttention,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte pleine largeur : icône, titre et description à gauche,
/// lien Ouvrir à droite, sans troncature.
class _TuileLarge extends StatelessWidget {
  final IconData icone;
  final String titre;
  final VoidCallback onTap;

  const _TuileLarge({
    required this.icone,
    required this.titre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Ouvrir →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.orAttention,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prochain culte en vedette : le plus proche, avec son compte à
/// rebours (jours, heures, minutes) et « Je serai présent ».
/// État vide chaleureux sinon.
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
        if (cultes.isEmpty) {
          return const EmptyState(
            icon: Icons.event_outlined,
            message: 'Aucun culte programmé',
          );
        }
        final culte = cultes.first;
        final confirme = rsvpParCulte[culte.id] ?? culte.seraiPresent;
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.violetProfond,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'PROCHAIN CULTE',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1.2,
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
                        // T13, D02 : jamais de texte blanc sur or (2,24:1).
                        // Bleu nuit sur or : 7,36:1.
                        color: AppTheme.violetProfond,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                culte.titre,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Le prochain rendez vous de votre église.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Compte à rebours',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              _CompteRebours(date: culte.date),
              const SizedBox(height: 12),
              Text(
                'Lieu : ${culte.lieu ?? 'Lieu à confirmer'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              Text(
                culte.date != null
                    ? 'Heure : ${formatDateTime(culte.date)}'
                    : 'Heure : Heure à confirmer',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              if (culte.orateur != null)
                Text(
                  'Avec ${culte.orateur}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              const SizedBox(height: 16),
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
                  ),
                ),
              ),
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
          color: Colors.white12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              valeur,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              unite,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Vos étapes, une par une, au rythme de votre croissance.',
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titre,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            faite ? 'Étape faite.' : 'Étape à venir.',
            style: Theme.of(context).textTheme.bodySmall,
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
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              libelle,
              style: Theme.of(context).textTheme.bodySmall,
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Chip(label: Text('$n document${n > 1 ? 's' : ''}')),
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
                label: const Text('Voir mes attestations'),
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
            style: Theme.of(context).textTheme.bodyMedium,
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
            child: const Text('Le texte s’affichera ici.'),
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
          TextField(
            controller: _sujetController,
            decoration: const InputDecoration(
              labelText: 'Écrivez votre sujet de prière',
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
            title: const Text('Sujet confidentiel'),
            subtitle: const Text('Visible seulement par votre pasteur.'),
            value: _confidentiel,
            onChanged: (v) => setState(() => _confidentiel = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _envoi ? null : _deposer,
            icon: const Icon(Icons.favorite_outline),
            label: Text(_envoi ? 'Envoi…' : 'Écrire un sujet de prière'),
          ),
        ],
      ),
    );
  }
}
