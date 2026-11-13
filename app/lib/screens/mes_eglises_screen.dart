import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/church.dart';
import '../state/app_state.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';

/// Écran dédié « Mes églises » : le sélecteur d'église active.
///
/// Le tiroir ne montre plus la liste complète des églises : avec plus de
/// 500 branches, il devenait interminable et repoussait les entrées du
/// menu en bas. Ici, la liste est paginée (50 par page) et cherchable
/// par nom, code ESC-… ou ville ; la suite ne se charge qu'au défilement.
/// L'église active est en tête de la première page et cochée. Toucher
/// une ligne change d'église et revient à l'écran précédent, sans
/// recharger toute l'application.
class MesEglisesScreen extends StatefulWidget {
  const MesEglisesScreen({super.key});

  @override
  State<MesEglisesScreen> createState() => _MesEglisesScreenState();
}

class _MesEglisesScreenState extends State<MesEglisesScreen> {
  static const int _limite = 50;

  final _recherche = TextEditingController();
  final _defilement = ScrollController();
  Timer? _attenteRecherche;

  List<Membership> _items = [];
  int _total = 0;
  int _page = 1;
  int _pages = 0;
  bool _chargement = true;
  bool _chargementSuite = false;
  String? _basculeEnCours;

  @override
  void initState() {
    super.initState();
    _defilement.addListener(_surDefilement);
    _charger();
  }

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    _recherche.dispose();
    _defilement.dispose();
    super.dispose();
  }

  /// La suite se charge quand on approche du bas de la liste.
  void _surDefilement() {
    if (!_defilement.hasClients || _chargementSuite || _chargement) return;
    if (_page >= _pages) return;
    if (_defilement.position.pixels >=
        _defilement.position.maxScrollExtent - 300) {
      _chargerSuite();
    }
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _page = 1;
    });
    try {
      final resultat = await context.read<AppState>().api.listerMesEglises(
            recherche: _recherche.text,
            page: 1,
            limite: _limite,
          );
      if (!mounted) return;
      setState(() {
        _items = resultat.eglises;
        _total = resultat.total;
        _page = resultat.page;
        _pages = resultat.pages;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      showApiError(context, e);
    }
  }

  Future<void> _chargerSuite() async {
    setState(() => _chargementSuite = true);
    try {
      final resultat = await context.read<AppState>().api.listerMesEglises(
            recherche: _recherche.text,
            page: _page + 1,
            limite: _limite,
          );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...resultat.eglises];
        _page = resultat.page;
        _pages = resultat.pages;
        _chargementSuite = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargementSuite = false);
      showApiError(context, e);
    }
  }

  /// Recherche après une courte pause, pour ne pas appeler l'API à
  /// chaque lettre tapée.
  void _surRechercheChangee() {
    // Reconstruction immédiate : l'icône d'effacement apparaît dès
    // la première lettre tapée, la recherche suit après une pause.
    setState(() {});
    _attenteRecherche?.cancel();
    _attenteRecherche = Timer(const Duration(milliseconds: 400), _charger);
  }

  Future<void> _changerEglise(Membership membership) async {
    final state = context.read<AppState>();
    if (membership.church.id == state.church?.id) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _basculeEnCours = membership.church.id);
    try {
      await state.switchChurch(membership.church.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _basculeEnCours = null);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeId = state.church?.id;
    final aUneSuite = _page < _pages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes églises'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _recherche,
              onChanged: (_) => _surRechercheChangee(),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _charger(),
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, code ou ville…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _recherche.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _recherche.clear();
                          _charger();
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (!_chargement && _total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _total == 1 ? '1 église' : '$_total églises',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: _chargement
                ? const Center(child: AppLoading())
                : _items.isEmpty
                    ? EmptyState(
                        icon: Icons.church_outlined,
                        message: _recherche.text.trim().isEmpty
                            ? 'Aucune église pour l’instant.'
                            : 'Aucune église trouvée pour « ${_recherche.text.trim()} ».',
                      )
                    : ListView.builder(
                        controller: _defilement,
                        itemCount: _items.length + (aUneSuite ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _items.length) {
                            if (!_chargementSuite) {
                              // Déclenche le chargement de la suite dès
                              // que la ligne de chargement devient visible.
                              Future.microtask(_chargerSuite);
                            }
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: AppLoading()),
                            );
                          }
                          final membership = _items[index];
                          final church = membership.church;
                          final active = church.id == activeId;
                          return ListTile(
                            leading:
                                ChurchAvatar(church: church, radius: 18),
                            title: Text(
                              church.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${church.code}'
                              '${church.city == null ? '' : ' · ${church.city}'}'
                              ' · ${membership.role}'
                              '${church.isMere ? ' · Église mère' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _basculeEnCours == church.id
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : active
                                    ? const Icon(Icons.check)
                                    : null,
                            onTap: _basculeEnCours == null
                                ? () => _changerEglise(membership)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
