import '../models/activites.dart';
import '../models/announcement.dart';
import '../models/ecole_biblique.dart';
import '../models/medias.dart';
import '../utils/format.dart';

/// Recherche globale locale (T2, modèle CP) : les contenus déjà
/// chargés, jamais le serveur. Quatre sources, annonces, activités,
/// cours de l'École biblique, livres de la Librairie. Les versets et
/// les membres ne sont pas cherchés ici : les versets se cherchent
/// dans la Bible, les membres sur leur écran.

/// Résultats groupés par source, dans l'ordre d'affichage.
class ResultatsRecherche {
  final List<Announcement> annonces;
  final List<Activite> activites;
  final List<CoursEcole> cours;
  final List<Livre> livres;

  const ResultatsRecherche({
    this.annonces = const [],
    this.activites = const [],
    this.cours = const [],
    this.livres = const [],
  });

  bool get estVide =>
      annonces.isEmpty &&
      activites.isEmpty &&
      cours.isEmpty &&
      livres.isEmpty;

  int get total =>
      annonces.length + activites.length + cours.length + livres.length;
}

/// Filtre les quatre listes sur la requête : chaque mot de la requête
/// (insensible aux accents) doit apparaître dans le texte cherché.
/// Une requête vide ne renvoie rien.
ResultatsRecherche rechercherContenus({
  required String requete,
  required List<Announcement> annonces,
  required List<Activite> activites,
  required List<CoursEcole> cours,
  required List<Livre> livres,
}) {
  final mots = normaliserRecherche(requete)
      .split(RegExp(r'\s+'))
      .where((mot) => mot.isNotEmpty)
      .toList();
  if (mots.isEmpty) return const ResultatsRecherche();

  bool correspond(String texte) {
    final normalise = normaliserRecherche(texte);
    return mots.every(normalise.contains);
  }

  return ResultatsRecherche(
    annonces: annonces
        .where((a) => correspond('${a.title} ${a.body}'))
        .toList(),
    activites: activites
        .where(
          (a) => correspond(
            '${a.titre} ${a.description ?? ''} ${a.lieu ?? ''} '
            '${a.responsable ?? ''}',
          ),
        )
        .toList(),
    cours: cours
        .where((c) => correspond('${c.titre} ${c.description ?? ''}'))
        .toList(),
    livres: livres
        .where(
          (l) => correspond(
            '${l.titre} ${l.auteur ?? ''} ${l.categorie ?? ''}',
          ),
        )
        .toList(),
  );
}
