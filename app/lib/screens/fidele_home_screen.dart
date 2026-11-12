import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/announcement.dart';
import '../models/attestation.dart';
import '../models/campagne.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/fidele.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/carte_membre_vedette.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/common_widgets.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'campagnes_screen.dart';
import 'member_detail_screen.dart';
import 'mes_attestations_screen.dart';

/// Accueil fidèle (rôle `membre`) : un espace qui donne envie d'ouvrir
/// l'application, pas une liste de lignes alignées. Une seule colonne
/// lisible, une belle carte de membre en vedette avec son QR, un accueil
/// personnalisé, le prochain culte en carte héro, Mon Parcours, la dîme
/// validée, les attestations PDF, la prière du jour. Rien d'inventé :
/// que des données réelles, et des états vides chaleureux quand il n'y a
/// rien. Aucun écran d'administration n'est accessible depuis ici : les
/// données viennent des lectures `/moi/*` (son église, ses propres données).
/// La bannière de l'église ne s'affiche que si l'église en a fourni une
/// (migration 018), sinon rien, jamais d'image inventée.
class FideleHomeScreen extends StatefulWidget {
  const FideleHomeScreen({super.key});

  @override
  State<FideleHomeScreen> createState() => _FideleHomeScreenState();
}

class _FideleHomeScreenState extends State<FideleHomeScreen> {
  late Future<FideleProfil> _profilFuture;
  late Future<List<Announcement>> _annoncesFuture;
  late Future<int> _nonLuesFuture;
  late Future<List<Culte>> _cultesFuture;
  late Future<List<Presence>> _presencesFuture;
  late Future<List<Contribution>> _contributionsFuture;
  late Future<List<Campagne>> _campagnesFuture;
  late Future<List<Attestation>> _attestationsFuture;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    // Tous les modules sont affichés pour toutes les églises (règle
    // du 11/11/2026) : toutes les sections sont chargées.
    final api = context.read<AppState>().api;
    _profilFuture = api.getMoi();
    _annoncesFuture = api.getMesAnnonces();
    _nonLuesFuture = api.getAnnoncesNonLues();
    _attestationsFuture = api.getMesAttestations();
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
    // US2 : seules les campagnes dont l'église montre le total arrivent
    // ici, le serveur filtre le reste.
    _campagnesFuture = api.getCampagnes();
  }

  Future<void> _refresh() async {
    setState(_charger);
  }

  Future<void> _marquerLue(Announcement annonce) async {
    try {
      await context.read<AppState>().api.marquerAnnonceLue(annonce.id);
      if (mounted) {
        setState(() {
          _nonLuesFuture =
              context.read<AppState>().api.getAnnoncesNonLues();
        });
      }
    } catch (_) {
      // Marquer lu est un confort, pas un blocage : on ignore l'échec.
    }
  }

  Future<void> _voirMaCarte() async {
    try {
      final carte = await context.read<AppState>().api.getMaCarte();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberDetailScreen(
            member: carte.member,
            lectureSeule: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _changerMotDePasse() async {
    await showChangePasswordDialog(context);
  }

  void _voirMesAttestations() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MesAttestationsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Accueil',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => context.read<AppState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
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
                        final prenom = profil.user.fullName
                            .trim()
                            .split(RegExp(r'\s+'))
                            .first;
                        return Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(4, 8, 4, 16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bonjour, $prenom',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Content de vous revoir.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.color,
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
                            const SizedBox(height: 12),
                            BoutonAvecAide(
                              label: 'Mes attestations',
                              aide: 'Vos attestations de don et de '
                                  'présence, à télécharger ou à recevoir.',
                              icon: Icons.description_outlined,
                              secondaire: true,
                              onPressed: _voirMesAttestations,
                            ),
                            FutureBuilder<List<Attestation>>(
                              future: _attestationsFuture,
                              builder: (context, snapshot) {
                                final n = snapshot.data?.length ?? 0;
                                if (snapshot.connectionState ==
                                        ConnectionState.waiting ||
                                    n == 0) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '$n attestation${n > 1 ? 's' : ''} PDF '
                                    'disponible${n > 1 ? 's' : ''}.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            const SectionTitle(title: 'Mon profil'),
                            ListTile(
                              leading:
                                  const Icon(Icons.person_outline),
                              title: Text(profil.user.fullName),
                              subtitle: Text(profil.user.email),
                            ),
                            if (profil.matricule != null)
                              ListTile(
                                leading:
                                    const Icon(Icons.badge_outlined),
                                title: Text(
                                    'Matricule : ${profil.matricule}'),
                                subtitle: const Text(
                                    'Votre carte de membre'),
                              ),
                            ListTile(
                              leading:
                                  const Icon(Icons.lock_outline),
                              title: const Text(
                                  'Changer mon mot de passe'),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: _changerMotDePasse,
                            ),
                          ],
                        );
                      },
                    ),
                    ...[
                      const SectionTitle(title: 'Prochain culte'),
                      _ProchainCulte(future: _cultesFuture),
                    ],
                    ...[
                      const SectionTitle(title: 'Mon Parcours'),
                      _ParcoursSection(
                        presencesFuture: _presencesFuture,
                        contributionsFuture: _contributionsFuture,
                      ),
                    ],
                    ...[
                      Row(
                        children: [
                          const Expanded(
                            child:
                                SectionTitle(title: 'Ce qui vous attend'),
                          ),
                          FutureBuilder<int>(
                            future: _nonLuesFuture,
                            builder: (context, snapshot) {
                              final n = snapshot.data ?? 0;
                              if (n == 0) return const SizedBox.shrink();
                              return Padding(
                                padding:
                                    const EdgeInsets.only(right: 16, top: 12),
                                child: Chip(
                                  label: Text(
                                      '$n non lue${n > 1 ? 's' : ''}'),
                                  backgroundColor: AppTheme.or,
                                  labelStyle: const TextStyle(
                                      color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      _SectionList<Announcement>(
                        future: _annoncesFuture,
                        emptyIcon: Icons.campaign_outlined,
                        emptyMessage: 'Rien de nouveau pour l’instant. '
                            'Votre église n’a rien publié.',
                        itemBuilder: (a) => ListTile(
                          leading:
                              const Icon(Icons.campaign_outlined),
                          title: Text(a.title),
                          subtitle: Text(
                            a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _marquerLue(a),
                        ),
                      ),
                    ],
                    const SectionTitle(title: 'Mes dons'),
                    _DonsSection(
                      future: _contributionsFuture,
                      devise: state.devise,
                    ),
                    const SectionTitle(title: 'Campagnes de mon église'),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                          'Chaque campagne montre ce qui a déjà été '
                          'collecté.'),
                    ),
                    _SectionList<Campagne>(
                      future: _campagnesFuture,
                      emptyIcon: Icons.volunteer_activism_outlined,
                      emptyMessage: 'Aucune campagne visible pour '
                          'l’instant. Votre église n’en a pas lancé.',
                      itemBuilder: (c) => ListTile(
                        leading: const Icon(
                            Icons.volunteer_activism_outlined),
                        title: Text(c.nom),
                        subtitle: Text(
                          c.depasse
                              ? 'Objectif dépassé : ${formatFcfa(c.totalCollecte)} sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).'
                              : '${formatFcfa(c.totalCollecte)} sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).',
                        ),
                        trailing:
                            const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CampagnesScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    ...[
                      const SectionTitle(title: 'Prière du jour'),
                      FutureBuilder<FideleProfil>(
                        future: _profilFuture,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox.shrink();
                          }
                          final profil = snapshot.data!;
                          return _PriereDuJour(
                            memberId: profil.memberId,
                            membreNom: profil.user.fullName,
                          );
                        },
                      ),
                    ],
                    ...[
                      const SectionTitle(title: 'Mes présences'),
                      _SectionList<Presence>(
                        future: _presencesFuture,
                        emptyIcon: Icons.how_to_reg_outlined,
                        emptyMessage: 'Aucune présence enregistrée '
                            'pour l’instant. Votre première présence '
                            'apparaîtra ici.',
                        itemBuilder: (p) => ListTile(
                          leading: const Icon(
                              Icons.how_to_reg_outlined),
                          title: Text(p.statutLabel),
                          subtitle: Text(
                            '${formatDateTime(p.pointeAt)} · ${p.mode}',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '${state.user?.fullName ?? ''} — ${state.roleLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste d'une section fidèle : chargement, erreur, vide explicite, items.
class _SectionList<T> extends StatelessWidget {
  final Future<List<T>> future;
  final IconData emptyIcon;
  final String emptyMessage;
  final Widget Function(T item) itemBuilder;

  const _SectionList({
    required this.future,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(message: snapshot.error.toString(), onRetry: null);
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return EmptyState(icon: emptyIcon, message: emptyMessage);
        }
        return Card(
          child: Column(
            children: items.map(itemBuilder).toList(),
          ),
        );
      },
    );
  }
}

/// Prochain culte en vedette : le plus proche, avec sa date, son lieu
/// et son orateur quand ils existent. État vide chaleureux sinon.
class _ProchainCulte extends StatelessWidget {
  final Future<List<Culte>> future;

  const _ProchainCulte({required this.future});

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
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bleuNuit,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_outlined,
                  size: 32, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROCHAIN CULTE',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
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
                      formatDateTime(culte.date),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    if (culte.lieu != null)
                      Text(
                        culte.lieu!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    if (culte.orateur != null)
                      Text(
                        'Avec ${culte.orateur}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    if (culte.theme != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        culte.theme!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mes dons : total confirmé en tête, puis chaque don. La progression
/// du fidèle, sans rien inventer : que ses contributions réelles.
class _DonsSection extends StatelessWidget {
  final Future<List<Contribution>> future;
  final String devise;

  const _DonsSection({required this.future, required this.devise});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Contribution>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(message: snapshot.error.toString(), onRetry: null);
        }
        final dons = snapshot.data ?? [];
        if (dons.isEmpty) {
          return const EmptyState(
            icon: Icons.volunteer_activism_outlined,
            message: 'Vous n’avez pas encore donné. Quand vous donnerez, '
                'tout apparaîtra ici.',
          );
        }
        final confirme = dons
            .where((c) => c.status == 'confirme')
            .fold<int>(0, (s, c) => s + c.amountFcfa);
        final dimeValidee = dons
            .where((c) => c.type == 'dime' && c.status == 'confirme')
            .fold<int>(0, (s, c) => s + c.amountFcfa);
        final aUneDime = dons.any((c) => c.type == 'dime');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SoftCard(
              child: Row(
                children: [
                  const Icon(Icons.volunteer_activism_outlined,
                      size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total donné (confirmé)',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium,
                        ),
                        Text(
                          formatMontant(confirme, devise),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall,
                        ),
                        Text(
                          aUneDime
                              ? 'Dîme validée : ${formatMontant(dimeValidee, devise)}'
                              : 'Aucune dîme validée pour l’instant.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                        Text(
                          '${dons.length} don${dons.length > 1 ? 's' : ''} au total',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: dons
                    .map((c) => ListTile(
                          leading: const Icon(
                              Icons.volunteer_activism_outlined),
                          title: Text(
                              '${Contribution.labelForType(c.type)} — ${formatMontant(c.amountFcfa, devise)}'),
                          subtitle: Text(
                            '${formatDate(c.createdAt)} · ${c.statusLabel}',
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Mon Parcours : ce que le fidèle a réellement vécu dans son église,
/// sans étape inventée. Nombre de présences, première présence
/// enregistrée, nombre de dons. Les étapes du parcours des nouveaux
/// venus (artefact, étape sur 4) n'existent pas en base : elles
/// arriveront avec la fiche de suivi en T4, on n'invente pas de
/// progression ici.
class _ParcoursSection extends StatelessWidget {
  final Future<List<Presence>> presencesFuture;
  final Future<List<Contribution>> contributionsFuture;

  const _ParcoursSection({
    required this.presencesFuture,
    required this.contributionsFuture,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<dynamic>>>(
      future: Future.wait([presencesFuture, contributionsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(message: snapshot.error.toString(), onRetry: null);
        }
        final presences = (snapshot.data?[0] as List<Presence>? ?? []);
        final dons = (snapshot.data?[1] as List<Contribution>? ?? []);
        final dates = presences
            .map((p) => p.pointeAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
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
                      '${presences.length} présence${presences.length > 1 ? 's' : ''} enregistrée${presences.length > 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              if (dates.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Première présence : ${formatDate(dates.first)}'),
              ],
              const SizedBox(height: 4),
              Text(
                  '${dons.length} don${dons.length > 1 ? 's' : ''} au total'),
              if (presences.isEmpty && dons.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Votre parcours commence ici : votre première présence et votre premier don apparaîtront ici.'),
                ),
            ],
          ),
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
              labelText: 'Votre sujet de prière',
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
            subtitle:
                const Text('Visible seulement par votre pasteur.'),
            value: _confidentiel,
            onChanged: (v) => setState(() => _confidentiel = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _envoi ? null : _deposer,
            icon: const Icon(Icons.favorite_outline),
            label: Text(_envoi ? 'Envoi…' : 'Déposer mon sujet'),
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
