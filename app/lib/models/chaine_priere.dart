/// Chaîne de prière (lot 3d) : 24 créneaux d'une heure par jour, un
/// membre par créneau, un créneau par membre et par jour. Aides pures
/// et modèle, adaptés de Connexion Prophétique (`lib/chaine_priere.dart`)
/// : mêmes moments de la journée et mêmes libellés, palette et textes
/// d'e-System Church, français seulement.
library;

/// Nombre de créneaux dans une journée, un par heure.
const nbCreneauxPriere = 24;

/// Moment de la journée d'un créneau, comme les filtres de l'écran :
/// Nuit 0 h-6 h, Matin 6 h-12 h, Après-midi 12 h-18 h, Soir 18 h-0 h.
enum MomentChaine { nuit, matin, apresMidi, soir }

/// Moment d'une heure, 0 à 23.
MomentChaine momentChaine(int heure) {
  if (heure < 6) return MomentChaine.nuit;
  if (heure < 12) return MomentChaine.matin;
  if (heure < 18) return MomentChaine.apresMidi;
  return MomentChaine.soir;
}

/// Libellé d'un moment pour l'en-tête de section, par
/// exemple « Nuit • 0 h – 6 h ».
String libelleMomentChaine(MomentChaine moment) {
  switch (moment) {
    case MomentChaine.nuit:
      return 'Nuit • 0 h – 6 h';
    case MomentChaine.matin:
      return 'Matin • 6 h – 12 h';
    case MomentChaine.apresMidi:
      return 'Après-midi • 12 h – 18 h';
    case MomentChaine.soir:
      return 'Soir • 18 h – 0 h';
  }
}

/// Un créneau de la chaîne : son heure, le membre qui l'a pris, ou
/// rien quand il est libre. Le prénom est le premier mot du nom complet
/// en base, jamais inventé.
class CreneauPriere {
  CreneauPriere({required this.heure, this.memberId, this.prenom = ''});

  factory CreneauPriere.fromJson(Map<String, dynamic> json) => CreneauPriere(
        heure: json['heure'] is int
            ? json['heure'] as int
            : int.tryParse((json['heure'] ?? '').toString()) ?? 0,
        memberId: (json['member_id'] ?? '').toString().isEmpty
            ? null
            : (json['member_id'] ?? '').toString(),
        prenom: (json['prenom'] ?? '').toString(),
      );

  final int heure;
  final String? memberId;
  final String prenom;

  bool get estLibre => memberId == null;
  bool estMien(String? monMemberId) =>
      !estLibre && monMemberId != null && memberId == monMemberId;
}

/// Les 24 créneaux d'un jour, avec le compteur et l'identifiant du
/// membre appelant (pour repérer son propre créneau).
class ChainePriereJour {
  ChainePriereJour({
    required this.jour,
    required this.aujourdHui,
    required this.heuresCouvertes,
    required this.monMemberId,
    required this.creneaux,
  });

  factory ChainePriereJour.fromJson(Map<String, dynamic> json) {
    final creneaux = creneauxPriereDepuisReponse(json);
    return ChainePriereJour(
      jour: (json['jour'] ?? '').toString(),
      aujourdHui: (json['aujourd_hui'] ?? '').toString(),
      heuresCouvertes: json['heures_couvertes'] is int
          ? json['heures_couvertes'] as int
          : heuresCouvertesPriere(creneaux),
      monMemberId: (json['mon_member_id'] ?? '').toString().isEmpty
          ? null
          : (json['mon_member_id'] ?? '').toString(),
      creneaux: creneaux,
    );
  }

  /// Jour en AAAA-MM-JJ.
  final String jour;

  /// Jour courant côté serveur, en AAAA-MM-JJ.
  final String aujourdHui;

  /// Nombre d'heures couvertes sur 24.
  final int heuresCouvertes;

  /// Fiche membre liée au compte appelant, ou null sans fiche.
  final String? monMemberId;

  /// Les 24 créneaux, de 0 h à 23 h, dans l'ordre.
  final List<CreneauPriere> creneaux;

  /// Le créneau du membre appelant ce jour-là, ou null.
  CreneauPriere? get monCreneau {
    for (final c in creneaux) {
      if (c.estMien(monMemberId)) return c;
    }
    return null;
  }

  /// Vrai quand le jour est passé côté serveur, donc en lecture seule.
  bool get estPasse => estJourPasseChaine(jour, aujourdHui);

  /// Vrai quand le jour affiché est aujourd'hui côté serveur.
  bool get estAujourdHui => aujourdHui.isNotEmpty && jour == aujourdHui;
}

/// Les 24 créneaux du jour, dans l'ordre, depuis la réponse du
/// serveur. Un créneau absent de la réponse est libre.
List<CreneauPriere> creneauxPriereDepuisReponse(Map<String, dynamic> data) {
  final parHeure = <int, CreneauPriere>{};
  final lignes = data['creneaux'];
  if (lignes is List) {
    for (final ligne in lignes) {
      if (ligne is Map<String, dynamic>) {
        final c = CreneauPriere.fromJson(ligne);
        if (c.heure >= 0 &&
            c.heure < nbCreneauxPriere &&
            !parHeure.containsKey(c.heure)) {
          parHeure[c.heure] = c;
        }
      }
    }
  }
  return List.generate(
    nbCreneauxPriere,
    (heure) => parHeure[heure] ?? CreneauPriere(heure: heure),
  );
}

/// Nombre d'heures couvertes sur 24, pour l'en-tête.
int heuresCouvertesPriere(List<CreneauPriere> creneaux) =>
    creneaux.where((c) => !c.estLibre).length;

/// Libellé d'un créneau, par exemple « 8 h – 9 h ».
String libelleCreneauPriere(int heure) {
  final suivante = (heure + 1) % 24;
  return '$heure h – $suivante h';
}

/// Jour en AAAA-MM-JJ, pour la demande au serveur.
String jourIsoChaine(DateTime jour) =>
    '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';

/// Jour seul, sans l'heure, pour comparer deux jours.
DateTime jourSeulChaine(DateTime jour) =>
    DateTime(jour.year, jour.month, jour.day);

/// Date en « samedi 21 nov. 2026 », comme la maquette de Connexion
/// Prophétique (minuscules, abréviations françaises).
String libelleDateChaine(DateTime jour) {
  const jours = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche'
  ];
  const mois = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.'
  ];
  return '${jours[jour.weekday - 1]} ${jour.day} ${mois[jour.month - 1]} ${jour.year}';
}

/// Position du jour par rapport à aujourd'hui : « Aujourd'hui »,
/// « Demain », « Hier », « Dans 3 jours », « Il y a 2 jours ».
String libelleRelatifChaine(DateTime jour, DateTime aujourdHui) {
  final ecart =
      jourSeulChaine(jour).difference(jourSeulChaine(aujourdHui)).inDays;
  if (ecart == 0) return 'Aujourd’hui';
  if (ecart == 1) return 'Demain';
  if (ecart == -1) return 'Hier';
  if (ecart > 1) return 'Dans $ecart jours';
  return 'Il y a ${-ecart} jours';
}

/// Vrai quand le jour demandé est avant aujourd'hui côté serveur, donc
/// en lecture seule. La comparaison de chaînes suffit en AAAA-MM-JJ.
bool estJourPasseChaine(String jourIso, String? aujourdHuiIso) =>
    aujourdHuiIso != null &&
    aujourdHuiIso.isNotEmpty &&
    jourIso.compareTo(aujourdHuiIso) < 0;

/// Créneaux du moment choisi, tous quand le filtre est nul.
List<CreneauPriere> creneauxFiltresChaine(
    List<CreneauPriere> creneaux, MomentChaine? moment) {
  if (moment == null) return creneaux;
  return creneaux.where((c) => momentChaine(c.heure) == moment).toList();
}

/// Initiales d'un prénom pour l'avatar, par exemple « KO » pour Kofi.
/// Jamais inventées, elles viennent du prénom servi.
String initialesDepuisPrenom(String prenom) {
  final propre = prenom.trim();
  if (propre.isEmpty) return '';
  if (propre.length == 1) return propre.toUpperCase();
  return propre.substring(0, 2).toUpperCase();
}
