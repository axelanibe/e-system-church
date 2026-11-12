import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
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
/// lisible, une belle carte de membre en vedette, un accueil
/// personnalisé, le prochain culte, les actions principales en gros
/// boutons, puis ce qui attend le fidèle : annonces, dons, campagnes,
/// présences. Rien d'inventé : que des données réelles, et des états
/// vides chaleureux quand il n'y a rien. Aucun écran d'administration
/// n'est accessible depuis ici : les données viennent des lectures
/// `/moi/*` (son église, ses propres données).
class FideleHomeScreen extends StatefulWidget {
  const FideleHomeScreen({super.key});

  @override
  State<FideleHomeScreen> createState() => _FideleHomeScreenState();
}

class _FideleHomeScreenState extends State<FideleHomeScreen> {
  late Future<FideleProfil> _profilFuture;
  late Future<List<Announcement>> _annoncesFuture;
  late Future<List<Culte>> _cultesFuture;
  late Future<List<Presence>> _presencesFuture;
  late Future<List<Contribution>> _contributionsFuture;
  late Future<List<Campagne>> _campagnesFuture;

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

  Future<void> _voirMaCarte() async {
    try {
      final carte = await context.read<AppState>().api.getMaCarte();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberDetailScreen(member: carte.member),
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
                      const SectionTitle(title: 'Ce qui vous attend'),
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
        return SoftCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_outlined, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      culte.titre,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(formatDateTime(culte.date)),
                    if (culte.lieu != null) Text(culte.lieu!),
                    if (culte.orateur != null)
                      Text('Avec ${culte.orateur}'),
                    if (culte.theme != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        culte.theme!,
                        style:
                            Theme.of(context).textTheme.bodySmall,
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
