import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activites.dart';
import '../models/announcement.dart';
import '../models/ecole_biblique.dart';
import '../models/medias.dart';
import '../services/recherche_globale.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'ecole_biblique_screen.dart';

/// Recherche globale (T2, modèle CP) : un seul champ, quatre sources
/// déjà chargées localement, annonces, activités, cours de l'École
/// biblique, livres de la Librairie, résultats groupés par source.
/// Aucun appel serveur pendant la frappe, aucun verset ni membre ici.
class RechercheGlobaleScreen extends StatefulWidget {
  const RechercheGlobaleScreen({super.key});

  @override
  State<RechercheGlobaleScreen> createState() =>
      _RechercheGlobaleScreenState();
}

class _RechercheGlobaleScreenState extends State<RechercheGlobaleScreen> {
  final _controller = TextEditingController();
  String _requete = '';
  bool _chargement = true;
  List<Announcement> _annonces = [];
  List<Activite> _activites = [];
  List<CoursEcole> _cours = [];
  List<Livre> _livres = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final api = context.read<AppState>().api;
    List<Announcement> annonces = [];
    List<Activite> activites = [];
    List<CoursEcole> cours = [];
    List<Livre> livres = [];
    // Chaque source se charge seule : un échec sur l'une n'empêche
    // pas la recherche sur les autres.
    try {
      annonces = await api.getMesAnnonces();
    } catch (_) {
      annonces = [];
    }
    try {
      activites = await api.getMesActivites();
    } catch (_) {
      activites = [];
    }
    try {
      cours = await api.getCoursEcole();
    } catch (_) {
      cours = [];
    }
    try {
      livres = await api.getLivres();
    } catch (_) {
      livres = [];
    }
    if (!mounted) return;
    setState(() {
      _annonces = annonces;
      _activites = activites;
      _cours = cours;
      _livres = livres;
      _chargement = false;
    });
  }

  ResultatsRecherche get _resultats => rechercherContenus(
        requete: _requete,
        annonces: _annonces,
        activites: _activites,
        cours: _cours,
        livres: _livres,
      );

  void _voirAnnonce(Announcement annonce) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(annonce.title),
        content: Text(
          [
            if (annonce.createdAt != null) formatDate(annonce.createdAt),
            annonce.body,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _voirActivite(Activite activite) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activite.titre),
        content: Text(
          [
            afficherDateTimeSansDecalage(activite.dateHeure),
            if (activite.lieu != null) activite.lieu!,
            if (activite.responsable != null)
              'Avec ${activite.responsable!}',
            if (activite.description != null) activite.description!,
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _voirLivre(Livre livre) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(livre.titre),
        content: Text(
          [
            if (livre.auteur != null) livre.auteur!,
            if (livre.categorie != null) livre.categorie!,
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _voirCours() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EcoleBibliqueScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultats = _resultats;
    final requete = _requete.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Rechercher dans l’application',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (valeur) => setState(() => _requete = valeur),
            ),
          ),
          Expanded(
            child: _chargement
                ? const AppLoading()
                : requete.isEmpty
                    ? const EmptyState(
                        icon: Icons.search,
                        message:
                            'Tapez un mot pour chercher dans les annonces, '
                            'les activités, les cours et les livres.',
                      )
                    : resultats.estVide
                        ? EmptyState(
                            icon: Icons.search_off_outlined,
                            message: 'Aucun résultat pour « $requete ».',
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            children: [
                              if (resultats.annonces.isNotEmpty) ...[
                                const SectionTitle(title: 'Annonces'),
                                for (final annonce in resultats.annonces)
                                  ListTile(
                                    leading: const Icon(
                                      Icons.campaign_outlined,
                                    ),
                                    title: Text(annonce.title),
                                    subtitle: Text(
                                      annonce.body,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _voirAnnonce(annonce),
                                  ),
                              ],
                              if (resultats.activites.isNotEmpty) ...[
                                const SectionTitle(title: 'Activités'),
                                for (final activite in resultats.activites)
                                  ListTile(
                                    leading: const Icon(Icons.event_outlined),
                                    title: Text(activite.titre),
                                    subtitle: Text(
                                      [
                                        afficherDateTimeSansDecalage(
                                          activite.dateHeure,
                                        ),
                                        if (activite.lieu != null)
                                          activite.lieu!,
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _voirActivite(activite),
                                  ),
                              ],
                              if (resultats.cours.isNotEmpty) ...[
                                const SectionTitle(title: 'Cours'),
                                for (final cours in resultats.cours)
                                  ListTile(
                                    leading: const Icon(Icons.school_outlined),
                                    title: Text(cours.titre),
                                    subtitle: Text(
                                      cours.niveauLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: _voirCours,
                                  ),
                              ],
                              if (resultats.livres.isNotEmpty) ...[
                                const SectionTitle(title: 'Livres'),
                                for (final livre in resultats.livres)
                                  ListTile(
                                    leading: const Icon(
                                      Icons.menu_book_outlined,
                                    ),
                                    title: Text(livre.titre),
                                    subtitle: Text(
                                      [
                                        if (livre.auteur != null)
                                          livre.auteur!,
                                        if (livre.categorie != null)
                                          livre.categorie!,
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _voirLivre(livre),
                                  ),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
