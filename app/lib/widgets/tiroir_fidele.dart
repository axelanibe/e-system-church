import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'common_widgets.dart';
import '../screens/a_propos_screen.dart';
import '../screens/camps_fidele_screen.dart';
import '../screens/mes_attestations_screen.dart';
import '../screens/parametres_fidele_screen.dart';
import '../screens/rendez_vous_screen.dart';
import '../screens/temoignages_screen.dart';
import '../screens/transparence_screen.dart';

/// Tiroir hamburger de l’espace membre : en-tête identité du membre
/// (nom, matricule, église, données réelles de l’accueil), recherche
/// qui filtre les entrées, et exactement les entrées du menu Plus,
/// dans le même ordre, avec les mêmes navigations. Mon journal et
/// Mes cotisations restent seulement dans les accès rapides, pas ici.
/// Méditation, Bureau et Établissements n’existent pas dans l’espace
/// membre : aucune entrée créée pour eux.
class TiroirFidele extends StatefulWidget {
  /// Appelé pour revenir sur l’accueil (Prière du jour, Sujet de
  /// prière privé, affichés sur l’accueil).
  final VoidCallback? onAllerAccueil;

  const TiroirFidele({super.key, this.onAllerAccueil});

  @override
  State<TiroirFidele> createState() => _TiroirFideleState();
}

class _TiroirFideleState extends State<TiroirFidele> {
  final _rechercheController = TextEditingController();
  String _recherche = '';
  late Future<FideleProfil> _profilFuture;
  late Future<MaCarte?> _carteFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _profilFuture = api.getMoi();
    _carteFuture = api
        .getMaCarte()
        .then<MaCarte?>((carte) => carte)
        .catchError((_) => null);
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  List<_EntreeTiroir> get _entrees => [
        _EntreeTiroir(
          icone: Icons.event_available_outlined,
          titre: 'Prendre rendez-vous',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const RendezVousScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.event_outlined,
          titre: 'Mes camps',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CampsFideleScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.receipt_long_outlined,
          titre: 'Mes attestations',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MesAttestationsScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.mic_outlined,
          titre: 'Témoignages',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TemoignagesScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.wb_sunny_outlined,
          titre: 'Prière du jour',
          onTap: (context) => widget.onAllerAccueil?.call(),
        ),
        _EntreeTiroir(
          icone: Icons.volunteer_activism_outlined,
          titre: 'Sujet de prière privé',
          onTap: (context) => widget.onAllerAccueil?.call(),
        ),
        _EntreeTiroir(
          icone: Icons.visibility_outlined,
          titre: 'Transparence financière',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TransparenceScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.settings_outlined,
          titre: 'Paramètres',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ParametresFideleScreen(),
            ),
          ),
        ),
        _EntreeTiroir(
          icone: Icons.info_outline,
          titre: 'À propos',
          onTap: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AProposScreen(),
            ),
          ),
        ),
      ];

  List<_EntreeTiroir> get _filtrees {
    final mots = normaliserRecherche(_recherche)
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .toList();
    if (mots.isEmpty) return _entrees;
    return _entrees.where((entree) {
      final texte = normaliserRecherche(entree.titre);
      return mots.every(texte.contains);
    }).toList();
  }

  void _aller(BuildContext context, _EntreeTiroir entree) {
    // On ferme le tiroir avant de naviguer, sinon l’écran poussé
    // reste couvert par le tiroir.
    Navigator.of(context).pop();
    entree.onTap(context);
  }

  @override
  Widget build(BuildContext context) {
    final filtrees = _filtrees;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<FideleProfil>(
              future: _profilFuture,
              builder: (context, snapshot) {
                final profil = snapshot.data;
                return FutureBuilder<MaCarte?>(
                  future: _carteFuture,
                  builder: (context, carteSnapshot) {
                    final matricule =
                        carteSnapshot.data?.member.matricule ??
                            profil?.matricule;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            PaletteMembre.violetRoyal,
                            PaletteMembre.degradeSecondaire,
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: PaletteMembre.or,
                            child: Text(
                              _initiales(
                                profil?.user.fullName ?? '',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppFontSizes.s16,
                                color: PaletteMembre.violetRoyal,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            profil?.user.fullName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: AppFontSizes.s16,
                                ),
                          ),
                          if (matricule != null && matricule.isNotEmpty)
                            Text(
                              matricule,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: PaletteMembre.orSurViolet,
                                    fontSize: AppFontSizes.s12_5,
                                  ),
                            ),
                          if (profil != null)
                            Text(
                              profil.church.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontSize: AppFontSizes.s12_5,
                                  ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                controller: _rechercheController,
                decoration: const InputDecoration(
                  hintText: 'Rechercher dans le menu…',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (valeur) => setState(() => _recherche = valeur),
              ),
            ),
            Expanded(
              child: filtrees.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_outlined,
                      message: 'Aucune entrée trouvée.',
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final entree in filtrees)
                          ListTile(
                            leading: Icon(
                              entree.icone,
                              color: PaletteMembre.violetRoyal,
                            ),
                            title: Text(
                              entree.titre,
                              style: const TextStyle(
                                fontSize: AppFontSizes.s13_5,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _aller(context, entree),
                          ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.logout,
                            color: Colors.red,
                          ),
                          title: const Text(
                            'Se déconnecter',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: AppFontSizes.s13_5,
                            ),
                          ),
                          onTap: () =>
                              context.read<AppState>().logout(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _initiales(String nom) {
    final mots = nom.split(' ').where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first[0].toUpperCase();
    return (mots.first[0] + mots.last[0]).toUpperCase();
  }
}

class _EntreeTiroir {
  final IconData icone;
  final String titre;
  final void Function(BuildContext context) onTap;

  const _EntreeTiroir({
    required this.icone,
    required this.titre,
    required this.onTap,
  });
}
