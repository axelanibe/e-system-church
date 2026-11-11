import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../models/campagne.dart';
import '../models/module_eglise.dart';
import '../models/contribution.dart';
import '../models/cultes.dart';
import '../models/fidele.dart';
import '../models/presences.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/mere_badge.dart';
import 'campagnes_screen.dart';
import 'member_detail_screen.dart';
import 'mes_attestations_screen.dart';

/// Accueil fidèle (rôle `membre`) : mon église, mes annonces, cultes à
/// venir, ma carte de membre, mes présences, mes contributions, mon profil.
/// Aucun écran d'administration n'est accessible depuis ici : les données
/// viennent des lectures `/moi/*` (son église, ses propres données).
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
    // US1 : on ne charge pas les sections des modules désactivés.
    final state = context.read<AppState>();
    final api = state.api;
    _profilFuture = api.getMoi();
    _annoncesFuture = state.isModuleActif(CodesModules.annonces)
        ? api.getMesAnnonces()
        : Future.value(<Announcement>[]);
    // « Cultes à venir » : on ne garde que les cultes d'aujourd'hui ou
    // après. Un culte sans date exploitable est gardé plutôt que caché.
    _cultesFuture = state.isModuleActif(CodesModules.cultes)
        ? api.getMesCultes().then((cultes) {
      final now = DateTime.now();
      final aujourdHui = DateTime(now.year, now.month, now.day);
      return cultes.where((c) {
        final date = c.date;
        if (date == null) return true;
        final jour = DateTime(date.year, date.month, date.day);
        return !jour.isBefore(aujourdHui);
      }).toList();
        })
        : Future.value(<Culte>[]);
    _presencesFuture = state.isModuleActif(CodesModules.presences)
        ? api.getMesPresences()
        : Future.value(<Presence>[]);
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ChurchAvatar(church: church, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    church?.name ?? 'Mon église',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (church != null)
                    Row(
                      children: [
                        Text(
                          church.code,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (church.isMere) ...[
                          const SizedBox(width: 8),
                          const MereBadge(),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
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
            FutureBuilder<FideleProfil>(
              future: _profilFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ChurchAvatar(church: church, radius: 40),
                            const SizedBox(height: 12),
                            Text(
                              church?.name ?? '',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (church?.isMere ?? false) ...[
                              const SizedBox(height: 8),
                              const MereBadge(),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Code : ${church?.code ?? ''}'
                              '${church?.city != null ? ' · ${church!.city}' : ''}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _voirMaCarte,
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text('Voir ma carte de membre'),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MesAttestationsScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Mes attestations'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SectionTitle(title: 'Mon profil'),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(profil.user.fullName),
                      subtitle: Text(profil.user.email),
                    ),
                    if (profil.matricule != null)
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text('Matricule : ${profil.matricule}'),
                        subtitle: const Text('Votre carte de membre'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Changer mon mot de passe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changerMotDePasse,
                    ),
                  ],
                );
              },
            ),
            if (state.isModuleActif(CodesModules.annonces))
              const SectionTitle(title: 'Mes annonces'),
            if (state.isModuleActif(CodesModules.annonces))
              _SectionList<Announcement>(
              future: _annoncesFuture,
              emptyIcon: Icons.campaign_outlined,
              emptyMessage: 'Aucune annonce pour l’instant.',
              itemBuilder: (a) => ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(a.title),
                subtitle: Text(
                  a.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (state.isModuleActif(CodesModules.cultes))
              const SectionTitle(title: 'Cultes à venir'),
            if (state.isModuleActif(CodesModules.cultes))
              _SectionList<Culte>(
              future: _cultesFuture,
              emptyIcon: Icons.event_outlined,
              emptyMessage: 'Aucun culte à venir pour l’instant.',
              itemBuilder: (c) => ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(c.titre),
                subtitle: Text(
                  '${formatDateTime(c.date)}'
                  '${c.lieu != null ? ' · ${c.lieu}' : ''}'
                  '${c.orateur != null ? ' · ${c.orateur}' : ''}',
                ),
              ),
            ),
            if (state.isModuleActif(CodesModules.presences))
              const SectionTitle(title: 'Mes présences'),
            if (state.isModuleActif(CodesModules.presences))
              _SectionList<Presence>(
              future: _presencesFuture,
              emptyIcon: Icons.how_to_reg_outlined,
              emptyMessage: 'Aucune présence enregistrée pour l’instant.',
              itemBuilder: (p) => ListTile(
                leading: const Icon(Icons.how_to_reg_outlined),
                title: Text(p.statutLabel),
                subtitle: Text(
                  '${formatDateTime(p.pointeAt)} · ${p.mode}',
                ),
              ),
            ),
            const SectionTitle(title: 'Mes contributions'),
            _SectionList<Contribution>(
              future: _contributionsFuture,
              emptyIcon: Icons.volunteer_activism_outlined,
              emptyMessage: 'Aucune contribution enregistrée pour l’instant.',
              itemBuilder: (c) => ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: Text(
                    '${Contribution.labelForType(c.type)} — ${formatMontant(c.amountFcfa, state.devise)}'),
                subtitle: Text(
                  '${formatDate(c.createdAt)} · ${c.status}',
                ),
              ),
            ),
            const SectionTitle(title: 'Campagnes de mon église'),
            _SectionList<Campagne>(
              future: _campagnesFuture,
              emptyIcon: Icons.volunteer_activism_outlined,
              emptyMessage: 'Aucune campagne visible pour l’instant.',
              itemBuilder: (c) => ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: Text(c.nom),
                subtitle: Text(
                  c.depasse
                      ? 'Objectif dépassé : ${formatFcfa(c.totalCollecte)} sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).'
                      : '${formatFcfa(c.totalCollecte)} sur ${formatFcfa(c.objectifFcfa)} (${c.pourcentage} %).',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CampagnesScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${state.user?.fullName ?? ''} — ${state.roleLabel}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
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
