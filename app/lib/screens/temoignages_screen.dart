import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/temoignage.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'creation_temoignage_screen.dart';
import 'lecteur_temoignage_screen.dart';

/// Page Témoignages (lot 3c) : fil des témoignages approuvés, mes
/// témoignages avec leur statut, file de modération pour l'admin de
/// l'église. Modèle : Connexion Prophétique (lib/temoignages.dart),
/// adapté : palette violet/or du logo, une seule entrée par
/// fonctionnalité (carte Modules côté admin, menu Plus côté fidèle).
/// Le statut s'affiche pour l'auteur et pour l'admin, jamais dans le
/// fil public.
class TemoignagesScreen extends StatefulWidget {
  const TemoignagesScreen({super.key});

  @override
  State<TemoignagesScreen> createState() => _TemoignagesScreenState();
}

class _TemoignagesScreenState extends State<TemoignagesScreen> {
  late Future<TemoignagesPageData> _donneesFuture;
  bool _actionEnCours = false;

  @override
  void initState() {
    super.initState();
    _donneesFuture = context.read<AppState>().api.getTemoignages();
  }

  void _recharger() {
    setState(() {
      _donneesFuture = context.read<AppState>().api.getTemoignages();
    });
  }

  Future<void> _publier() async {
    final publie = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreationTemoignageScreen(),
      ),
    );
    if (publie == true) _recharger();
  }

  Future<void> _moderer(Temoignage t, String statut) async {
    if (_actionEnCours) return;
    final api = context.read<AppState>().api;
    if (statut == 'rejete') {
      final confirmer = await confirmDelete(
        context,
        'Refuser ce témoignage ? Il restera visible par son auteur seulement.',
      );
      if (!confirmer) return;
    }
    setState(() => _actionEnCours = true);
    try {
      await api.modererTemoignage(t.id, statut);
      if (mounted) {
        showSuccess(
          context,
          statut == 'approuve'
              ? 'Témoignage approuvé, il est visible dans le fil.'
              : 'Témoignage refusé, il reste visible par son auteur seulement.',
        );
      }
      _recharger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _supprimer(Temoignage t) async {
    final api = context.read<AppState>().api;
    final confirmer = await confirmDelete(
      context,
      'Supprimer définitivement ce témoignage ?',
    );
    if (!confirmer) return;
    try {
      await api.supprimerTemoignage(t.id);
      if (mounted) showSuccess(context, 'Témoignage supprimé.');
      _recharger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  void _lire(Temoignage t) {
    final url = context.read<AppState>().api.urlMediaTemoignage(t);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LecteurTemoignageScreen(temoignage: t, urlMedia: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Témoignages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Actualiser',
            onPressed: _recharger,
          ),
        ],
      ),
      body: FutureBuilder<TemoignagesPageData>(
        future: _donneesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              message: 'Impossible de charger les témoignages.',
              actionLabel: 'Réessayer',
              onAction: _recharger,
            );
          }
          final donnees = snapshot.data ??
              const TemoignagesPageData();
          return RefreshIndicator(
            onRefresh: () async => _recharger(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _publier,
                    icon: const Icon(Icons.mic_outlined),
                    label: const Text('Publier un témoignage'),
                  ),
                ),
                const SizedBox(height: 16),
                if (donnees.moderation.isNotEmpty) ...[
                  Text(
                    'À modérer (${donnees.moderation.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final t in donnees.moderation) ...[
                    _CarteTemoignage(
                      temoignage: t,
                      onTap: () => _lire(t),
                      actions: [
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: _actionEnCours ? null : () => _supprimer(t),
                          icon: const Icon(Icons.delete_outlined),
                        ),
                        TextButton(
                          onPressed: _actionEnCours
                              ? null
                              : () => _moderer(t, 'rejete'),
                          child: const Text('Refuser'),
                        ),
                        FilledButton(
                          onPressed: _actionEnCours
                              ? null
                              : () => _moderer(t, 'approuve'),
                          child: const Text('Approuver'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                ],
                if (donnees.miens.isNotEmpty) ...[
                  Text(
                    'Mes témoignages',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final t in donnees.miens) ...[
                    _CarteTemoignage(
                      temoignage: t,
                      montreStatut: true,
                      onTap: () => _lire(t),
                      actions: [
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => _supprimer(t),
                          icon: const Icon(Icons.delete_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                ],
                if (donnees.fil.isEmpty)
                  const EmptyState(
                    icon: Icons.mic_outlined,
                    message: 'Aucun témoignage approuvé pour le moment.',
                  )
                else
                  for (final t in donnees.fil) ...[
                    _CarteTemoignage(
                      temoignage: t,
                      onTap: () => _lire(t),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Icône d'une carte selon le type de média du témoignage.
IconData _iconeTypeMedia(String typeMedia) {
  switch (typeMedia) {
    case 'photo':
      return Icons.photo_outlined;
    case 'audio':
      return Icons.mic_outlined;
    case 'texte':
      return Icons.text_fields_outlined;
    default:
      return Icons.ondemand_video_outlined;
  }
}

/// Une carte du fil : icône du média, auteur et date, extrait du
/// texte quand il y en a, toucher pour lire en plein écran. Le statut
/// s'affiche pour l'auteur et pour l'admin, jamais dans le fil public.
class _CarteTemoignage extends StatelessWidget {
  const _CarteTemoignage({
    required this.temoignage,
    required this.onTap,
    this.actions,
    this.montreStatut = false,
  });

  final Temoignage temoignage;
  final VoidCallback onTap;
  final List<Widget>? actions;
  final bool montreStatut;

  @override
  Widget build(BuildContext context) {
    final t = temoignage;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.violetProfond,
                    child: Icon(
                      _iconeTypeMedia(t.typeMedia),
                      color: AppTheme.or,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.auteurNom.isEmpty ? 'Témoignage' : t.auteurNom,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (t.creeLe != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatDateSeule(t.creeLe),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (montreStatut) ...[
                          const SizedBox(height: 4),
                          Text(
                            libelleStatutTemoignage(t.statut),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: t.approuve
                                      ? const Color(0xFF1B6B3A)
                                      : t.rejete
                                          ? const Color(0xFF7A1F2B)
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (t.estVideo || t.estAudio)
                    const Icon(
                      Icons.play_circle_outlined,
                      color: AppTheme.violetProfond,
                      size: 28,
                    ),
                ],
              ),
              if (t.texte.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(t.texte, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (actions != null) ...[
                const SizedBox(height: 8),
                // Wrap plutôt que Row : sur écran étroit, les trois
                // boutons de modération (Supprimer, Refuser, Approuver)
                // débordent de 20 px en Row.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
