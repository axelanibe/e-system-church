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
import '../widgets/soft_card.dart';
import 'bible_fidele_screen.dart';
import 'carte_fidele_screen.dart';
import 'cotisations_screen.dart';
import 'journal_screen.dart';
import 'mes_attestations_screen.dart';
import 'messages_fidele_screen.dart';

/// Accueil fidèle (tranche P1) : l'espace membre, dans l'ordre de la
/// projection. Contenu seul, sans Scaffold ni barre : la coquille
/// fidèle (FideleShell) fournit l'écran et la barre du bas.
/// En-tête, carte membre premium, prochain culte avec compte à rebours
/// et « Je serai présent », Mes accès en grille 2 par 2, Mon Parcours,
/// chiffres réels, Mes camps, Mes attestations, Prière du jour, Sujet
/// de prière privé, et « Tu es un don de Dieu » en bas.
/// Rien d'inventé : que des données réelles, et des états vides
/// chaleureux quand il n'y a rien. En aperçu admin (Voir l'espace
/// fidèle), seules les données du profil se chargent, le reste montre
/// des états vides.
class FideleHomeScreen extends StatefulWidget {
  const FideleHomeScreen({super.key});

  @override
  State<FideleHomeScreen> createState() => _FideleHomeScreenState();
}

class _FideleHomeScreenState extends State<FideleHomeScreen> {
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
              ? 'Présence confirmée. Votre église vous attend.'
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
                                  'Bonjour, fidèle',
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
                                  'parcours et vos prochains rendez vous. '
                                  'Tout commence par vous.',
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
                  const SectionTitle(title: 'Mes accès'),
                  _GrilleAcces(
                    onBible: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BibleFideleScreen(),
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
                  const SectionTitle(title: 'Mes camps'),
                  const EmptyState(
                    icon: Icons.event_outlined,
                    message: 'Aucun camp pour le moment. '
                        'Vos inscriptions aux camps apparaîtront ici.',
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Mes attestations'),
                  _AttestationsResume(
                    future: _attestationsFuture,
                    onVoir: _voirMesAttestations,
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Prière du jour'),
                  const SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Un moment calme pour commencer la journée.'),
                        SizedBox(height: 8),
                        Text('Le texte s’affichera ici.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SectionTitle(title: 'Sujet de prière privé'),
                  FutureBuilder<FideleProfil>(
                    future: _profilFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final profil = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Votre sujet reste privé. Il est transmis '
                            'uniquement aux responsables désignés.',
                          ),
                          const SizedBox(height: 8),
                          _PriereDuJour(
                            memberId: profil.memberId,
                            membreNom: profil.user.fullName,
                          ),
                        ],
                      );
                    },
                  ),
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

/// Grille 2 par 2 des accès du fidèle : Ma Bible, Mes cotisations,
/// Mon journal, Message à mon église.
class _GrilleAcces extends StatelessWidget {
  final VoidCallback onBible;
  final VoidCallback onCotisations;
  final VoidCallback onJournal;
  final VoidCallback onMessages;

  const _GrilleAcces({
    required this.onBible,
    required this.onCotisations,
    required this.onJournal,
    required this.onMessages,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _TuileAcces(
          icone: Icons.menu_book_outlined,
          titre: 'Ma Bible',
          sousTitre: 'Lire et rechercher, Ancien et Nouveau Testament.',
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
          sousTitre: 'Notes privées, jamais envoyées.',
          onTap: onJournal,
        ),
        _TuileAcces(
          icone: Icons.mail_outline,
          titre: 'Message à mon église',
          sousTitre: 'Messagerie privée, dans l’application.',
          onTap: onMessages,
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

  const _TuileAcces({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: AppTheme.orFonce),
              const SizedBox(height: 8),
              Text(
                titre,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  sousTitre,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Ouvrir →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.orFonce,
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
            message: 'Aucun culte prévu pour l’instant. Revenez bientôt, '
                'votre église vous attend.',
          );
        }
        final culte = cultes.first;
        final confirme = rsvpParCulte[culte.id] ?? culte.seraiPresent;
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bleuNuit,
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
                        color: Colors.white,
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
                ? const Icon(Icons.check, size: 16, color: Colors.white)
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

/// Prière du jour : déposer un sujet de prière privé, coché confidentiel
/// par défaut. Le sujet part par la route existante des demandes de
/// prière, rattaché au membre quand le compte est lié. Aucun texte de
/// prière inventé : la Bible reste un emplacement prêt, son texte sera
/// branché depuis la source fournie par la structure, jamais inventé.
class _PriereDuJour extends StatefulWidget {
  final String? memberId;
  final String membreNom;

  const _PriereDuJour({required this.memberId, required this.membreNom});

  @override
  State<_PriereDuJour> createState() => _PriereDuJourState();
}

class _PriereDuJourState extends State<_PriereDuJour> {
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
              hintText: 'Par exemple : ma famille, mon travail…',
            ),
            maxLength: 300,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            decoration: const InputDecoration(
              labelText: 'Détails (facultatif)',
              hintText: 'Quelques mots pour votre pasteur.',
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
          const SizedBox(height: 12),
          Text(
            'Bible : emplacement prêt. Le texte sera branché depuis la source fournie par votre église, aucun verset n’est inventé ici.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
