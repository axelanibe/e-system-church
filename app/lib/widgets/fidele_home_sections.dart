import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/activites.dart';
import '../models/announcement.dart';
import '../models/attestation.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/fidele.dart';
import '../models/presences.dart';
import '../screens/culte_detail_fidele_screen.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/carte_membre_vedette.dart';
import '../widgets/common_widgets.dart';
import '../widgets/compte_rebours.dart';
import '../widgets/soft_card.dart';
import '../screens/bible_fidele_screen.dart';
import '../screens/carte_fidele_screen.dart';
import '../screens/cotisations_screen.dart';
import '../screens/journal_screen.dart';
import '../screens/mes_attestations_screen.dart';
import '../screens/messagerie_liste_screen.dart';
import '../screens/recherche_globale_screen.dart';
import '../services/messagerie_lecture_service.dart';
import '../services/verset_du_jour.dart';

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
  late Future<List<Activite>> _activitesFuture;
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
    // « Activités à venir » (V1, migration 039) : publiées à venir de
    // son église, triées par date côté serveur. Les brouillons ne
    // sortent jamais de la route /moi/activites.
    _activitesFuture = api.getMesActivites();
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
        // Pas de toast ici : la pastille verte « Présence confirmée »
        // suffit, et le toast recouvrait les actions rapides.
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Confirmation de présence par activité (lot 3b, migration 040) :
  /// même motif que les cultes, doublon refusé en 409 par le serveur.
  final Map<String, bool> _rsvpParActivite = {};

  Future<void> _basculerPresenceActivite(
    Activite activite,
    bool confirme,
  ) async {
    try {
      if (confirme) {
        await context
            .read<AppState>()
            .api
            .confirmerPresenceActivite(activite.id);
      } else {
        await context
            .read<AppState>()
            .api
            .annulerPresenceActivite(activite.id);
      }
      if (mounted) {
        setState(() => _rsvpParActivite[activite.id] = confirme);
        // Pas de toast ici : la pastille verte « Présence confirmée »
        // suffit, et le toast recouvrait les actions rapides.
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
                  // Salutation de la maquette de refonte : « Bonjour,
                  // Prénom », église et date d'adhésion, devise en or,
                  // cloche de notification. L'en-tête de l'église
                  // (EnteteEspace) sort de l'accueil : le héros porte
                  // déjà le nom et le code de l'église.
                  _Salutation(
                    profilFuture: _profilFuture,
                    carteFuture: _carteFuture,
                    messagerieNonLus: _messagerieNonLus,
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                  _BarreRechercheAccueil(
                    onOuvrir: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RechercheGlobaleScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ProchainCulte(
                    future: _cultesFuture,
                    rsvpParCulte: _rsvpParCulte,
                    onBasculerPresence: _basculerPresence,
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Activités à venir'),
                  _ActivitesAVenirSection(
                    future: _activitesFuture,
                    rsvpParActivite: _rsvpParActivite,
                    onBasculerPresence: _basculerPresenceActivite,
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
                  // Ordre maquette de refonte : Prochain culte,
                  // Activités, Mon Parcours, chiffres, Verset du jour
                  // et Prière du jour dans une seule bannière pliable,
                  // Actions rapides, Sujet de prière privé, puis les
                  // sections secondaires en accordéons sous « Mon
                  // église », et la devise. Le Sujet de prière privé
                  // reste sur l'accueil : c'est la seule entrée vers
                  // le formulaire de prière, la coquille fidèle n'a
                  // pas d'onglet Prière.
                  const _VersetPriereBanniere(),
                  const SizedBox(height: 8),
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
                  const SectionTitle(title: 'Sujet de prière privé'),
                  _SujetPriereSection(profilFuture: _profilFuture),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Mon église'),
                  const _AccordeonMonEglise(
                    titre: 'Mes camps',
                    icone: Icons.event_outlined,
                    enfant: _CampsVide(),
                  ),
                  const SizedBox(height: 8),
                  _AccordeonMonEglise(
                    titre: 'Mes attestations',
                    icone: Icons.receipt_long_outlined,
                    enfant: _AttestationsResume(
                      future: _attestationsFuture,
                      onVoir: _voirMesAttestations,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AccordeonMonEglise(
                    titre: 'Annonces de mon église',
                    icone: Icons.campaign_outlined,
                    enfant: _AnnoncesEgliseSection(future: _annoncesFuture),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Tu es un don de Dieu',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PaletteMembre.orTexte,
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

/// Salutation de l'accueil (refonte) : « Bonjour, Prénom », église
/// et date d'adhésion, devise en or, et cloche de notification.
/// Le profil et la carte sont chargés ici, l'en-tête de l'église
/// ne dépend plus d'eux.
class _Salutation extends StatelessWidget {
  final Future<FideleProfil> profilFuture;
  final Future<MaCarte?> carteFuture;
  final int messagerieNonLus;

  const _Salutation({
    required this.profilFuture,
    required this.carteFuture,
    required this.messagerieNonLus,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FideleProfil>(
      future: profilFuture,
      builder: (context, snapshot) {
        final profil = snapshot.data;
        final prenom = (profil?.user.fullName ?? '')
            .trim()
            .split(' ')
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour${prenom.isEmpty ? '' : ', $prenom'}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: AppFontSizes.s20,
                          color: PaletteMembre.texte,
                        ),
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<MaCarte?>(
                    future: carteFuture,
                    builder: (context, carteSnapshot) {
                      final depuis =
                          carteSnapshot.data?.member.createdAt;
                      final texte = profil == null
                          ? ''
                          : depuis == null
                              ? profil.church.name
                              : '${profil.church.name} · Membre depuis '
                                  '${formatDate(depuis)}';
                      return Text(
                        texte,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: PaletteMembre.texteSecondaire,
                              fontSize: AppFontSizes.s12_5,
                            ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tu es un don de Dieu',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PaletteMembre.orTexte,
                          fontStyle: FontStyle.italic,
                          fontSize: AppFontSizes.s12_5,
                        ),
                  ),
                ],
              ),
            ),
            _ClocheNotifications(nonLus: messagerieNonLus),
          ],
        );
      },
    );
  }
}

/// Cloche de notification (refonte) : pastille or seulement quand
/// il y a une notification non lue. Un toucher ouvre la messagerie
/// s'il y en a, sinon un message discret.
class _ClocheNotifications extends StatelessWidget {
  final int nonLus;

  const _ClocheNotifications({required this.nonLus});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () {
            if (nonLus > 0) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MessagerieListeScreen(),
                ),
              );
            } else {
              showSuccess(context, 'Aucune nouvelle notification.');
            }
          },
          icon: const Icon(
            Icons.notifications_outlined,
            color: PaletteMembre.violetRoyal,
          ),
          tooltip: 'Notifications',
        ),
        if (nonLus > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(
                color: PaletteMembre.or,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$nonLus',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: PaletteMembre.violetRoyal,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Accordéon d'une section secondaire de « Mon église » (refonte) :
/// titre compact, contenu replié par défaut, état vide chaleureux
/// quand il n'y a rien.
class _AccordeonMonEglise extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Widget enfant;

  const _AccordeonMonEglise({
    required this.titre,
    required this.icone,
    required this.enfant,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icone, color: PaletteMembre.violetRoyal, size: 20),
        title: Text(
          titre,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: AppFontSizes.s14,
                fontWeight: FontWeight.bold,
              ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: enfant,
          ),
        ],
      ),
    );
  }
}

/// Barre de recherche de l'accueil fidèle (T2, modèle CP) : un faux
/// champ, sous le héros. Un toucher ouvre la recherche globale.
class _BarreRechercheAccueil extends StatelessWidget {
  final VoidCallback onOuvrir;

  const _BarreRechercheAccueil({required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOuvrir,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).hintColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rechercher dans l’application',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
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

/// Grille 2 par 2 des accès du fidèle (refonte) : 4 tuiles
/// compactes, Ma Bible, Mes cotisations, Mon journal, Messagerie.
/// Icône dans un carré doux + libellé sur UNE ligne, sans
/// description ni « Ouvrir → ». L'école biblique s'ouvre depuis
/// l'onglet Bible, le rendez-vous depuis le menu Plus : un seul
/// point d'entrée chacun. Le fil privé « Message à mon église »
/// (P1) reste accessible par l'onglet « Messages », inchangé :
/// jamais deux entrées pour la même fonction.
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.6,
      children: [
        _TuileAcces(
          icone: Icons.menu_book_outlined,
          titre: 'Ma Bible',
          onTap: onBible,
        ),
        _TuileAcces(
          icone: Icons.account_balance_wallet_outlined,
          titre: 'Mes cotisations',
          onTap: onCotisations,
        ),
        _TuileAcces(
          icone: Icons.edit_outlined,
          titre: 'Mon journal',
          onTap: onJournal,
        ),
        _TuileAcces(
          icone: Icons.chat_bubble_outline,
          titre: 'Messagerie',
          badge: badgeMessagerie,
          onTap: onMessagerie,
        ),
      ],
    );
  }
}

class _TuileAcces extends StatelessWidget {
  final IconData icone;
  final String titre;
  final VoidCallback onTap;

  /// Nombre de conversations non lues : pastille or en coin, cachée
  /// à 0. Nul pour les tuiles sans compteur.
  final int? badge;

  const _TuileAcces({
    required this.icone,
    required this.titre,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final carte = Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PaletteMembre.surfaceDouce,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(
                  icone,
                  color: PaletteMembre.violetRoyal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: AppFontSizes.s13_5,
                        fontWeight: FontWeight.bold,
                      ),
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
              color: PaletteMembre.or,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              '$total',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: PaletteMembre.violetRoyal,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pastille verte « Présence confirmée » + bouton « Annuler »
/// (lot 3b, modèle Connexion Prophétique adapté aux couleurs AppTheme) :
/// affichée à la place du bouton « Je serai présent » quand le fidèle
/// a confirmé. Le Wrap évite tout débordement sur écran étroit : le
/// bouton « Annuler » passe à la ligne suivante si besoin.
class _PresenceConfirmee extends StatelessWidget {
  final VoidCallback onAnnuler;

  const _PresenceConfirmee({required this.onAnnuler});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.vertFonce.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: AppTheme.vertFonce,
              ),
              SizedBox(width: 6),
              // Texte élastique : dans la carte carrousel (272 px
              // utiles), la police large des tests dépasse la
              // pastille ; le texte se coupe avec « … » au lieu de
              // déborder. Sur un vrai téléphone, il tient en entier.
              Flexible(
                child: Text(
                  'Présence confirmée',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.vertFonce,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onAnnuler,
          child: const Text(
            'Annuler',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Prochain culte (maquette, écran 37) : carte blanche, titre violet
/// et pastille or « À venir », compte à rebours (jours, heures,
/// minutes), lieu et heure côte à côte, puis « Je serai présent ».
/// Confirmé : pastille verte « Présence confirmée » + « Annuler ».
/// Sans culte daté à venir (lot 3b) : la carte est masquée et un état
/// vide explicite s'affiche — le compte à rebours « -- » et le bouton
/// désactivé de la PR #143 ne sont plus montrés.
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
        // Seuls les cultes datés à venir comptent comme prochain culte.
        final dates = cultes.where((c) => c.date != null).toList();
        final culte = dates.isEmpty ? null : dates.first;
        if (culte == null) {
          return const EmptyState(
            icon: Icons.event_outlined,
            message: 'Aucun culte à venir',
          );
        }
        final confirme = rsvpParCulte[culte.id] ?? culte.seraiPresent;
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: PaletteMembre.bordure),
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
                      color: PaletteMembre.violetRoyal,
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
                      color: PaletteMembre.or,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'À venir',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: PaletteMembre.violetRoyal,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                culte.titre,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              CompteRebours(date: culte.date),
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
                          culte.lieu ?? 'Lieu à confirmer',
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
                          culte.date != null
                              ? formatDateTimeSansDecalage(culte.date)
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
              if (culte.orateur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Avec ${culte.orateur}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (confirme)
                _PresenceConfirmee(
                  onAnnuler: () => onBasculerPresence(culte, false),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => onBasculerPresence(culte, true),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text(
                      'Je serai présent',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CulteDetailFideleScreen(culte: culte),
                    ),
                  ),
                  child: const Text('Voir le détail'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compte à rebours partagé : voir `widgets/compte_rebours.dart`.

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
                color: PaletteMembre.or,
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
                faite ? PaletteMembre.or : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: faite
                // T13, D02 : jamais de blanc sur or (2,24:1, icône
                // 16 px incluse). Bleu nuit sur or : 7,36:1.
                ? const Icon(Icons.check, size: 16, color: PaletteMembre.violetRoyal)
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

/// Verset du jour et Prière du jour dans une seule bannière
/// pliable en dégradé (refonte) : le verset calendaire, le même
/// dans l'écran Bible, texte chargé depuis les données LSG, jamais
/// inventé ; en dessous, la Prière du jour garde la phrase d'Axel
/// « Un moment calme pour commencer la journée. » avec la mention
/// discrète « Texte à confirmer par la structure » : le vrai texte
/// est toujours attendu, rien n'est inventé. La case
/// « Le texte s'affichera ici. » (défaut signalé) est supprimée :
/// jamais un emplacement vide montré comme une donnée.
class _VersetPriereBanniere extends StatefulWidget {
  const _VersetPriereBanniere();

  @override
  State<_VersetPriereBanniere> createState() => _VersetPriereBanniereState();
}

class _VersetPriereBanniereState extends State<_VersetPriereBanniere> {
  bool _deplie = true;
  late final Future<VersetDuJour> _versetFuture;

  @override
  void initState() {
    super.initState();
    _versetFuture = chargerVersetDuJour(context.read<AppState>().api);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PaletteMembre.violetRoyal,
            PaletteMembre.degradeSecondaire,
            PaletteMembre.accent,
          ],
          stops: [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _deplie = !_deplie),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_stories_outlined,
                      color: PaletteMembre.or,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verset du jour',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: AppFontSizes.s14,
                            ),
                      ),
                    ),
                    Icon(
                      _deplie
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white,
                    ),
                  ],
                ),
                if (_deplie) ...[
                  const SizedBox(height: 10),
                  FutureBuilder<VersetDuJour>(
                    future: _versetFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      }
                      final verset = snapshot.data;
                      if (verset == null) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '« ${verset.texte} »',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: AppFontSizes.s13_5,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            verset.reference,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: PaletteMembre.or,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppFontSizes.s11_5,
                                ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Prière du jour',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AppFontSizes.s13_5,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Un moment calme pour commencer la journée.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: AppFontSizes.s13,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Texte à confirmer par la structure.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                          fontSize: AppFontSizes.s11_5,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Annonces de mon église (maquette, écran 37) : les 3 dernières
/// annonces de l'église du fidèle, même source que l'accueil fidèle
/// (`GET /moi/annonces`).
/// Activités à venir (V1, migration 039) : publiées à venir de son
/// église, triées par date, titre, date et heure, lieu. Chaque activité
/// porte son bouton « Je serai présent » (lot 3b, migration 040),
/// qui devient pastille verte « Présence confirmée » + « Annuler ».
class _ActivitesAVenirSection extends StatelessWidget {
  final Future<List<Activite>> future;
  final Map<String, bool> rsvpParActivite;
  final Future<void> Function(Activite activite, bool confirme)
      onBasculerPresence;

  const _ActivitesAVenirSection({
    required this.future,
    required this.rsvpParActivite,
    required this.onBasculerPresence,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Activite>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        final activites = [...(snapshot.data ?? const <Activite>[])]
          ..sort((a, b) {
            final da = a.date;
            final db = b.date;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        if (activites.isEmpty) {
          return const EmptyState(
            icon: Icons.event_outlined,
            message: 'Aucune activité à venir',
          );
        }
        // Carrousel horizontal (refonte) : cartes de ~82 % de la
        // largeur, titre, date et heure, lieu, bouton de présence.
        // Pas de pastille de catégorie : le modèle Activite n'en a pas.
        return SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: activites.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final activite = activites[index];
              final confirme = rsvpParActivite[activite.id] ??
                  activite.seraiPresent;
              return SizedBox(
                width: 300,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.event_outlined,
                              color: PaletteMembre.violetRoyal,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                activite.titre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            formatDateTimeSansDecalage(activite.date),
                            if (activite.lieu != null) activite.lieu,
                            if (activite.responsable != null)
                              'Avec ${activite.responsable}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        confirme
                            ? _PresenceConfirmee(
                                onAnnuler: () =>
                                    onBasculerPresence(activite, false),
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      onBasculerPresence(activite, true),
                                  icon: const Icon(
                                    Icons.event_available_outlined,
                                  ),
                                  label: const Text(
                                    'Je serai présent',
                                    style: TextStyle(fontSize: 13.5),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

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
              labelText: 'Écrire ma demande *',
              helperText: 'Ex. Prière pour ma famille, pour ma santé.',
              helperMaxLines: 2,
            ),
            maxLength: 300,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            decoration: const InputDecoration(
              labelText: 'Détails (facultatif)',
              helperText: 'Précisez si vous le souhaitez.',
              helperMaxLines: 2,
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
