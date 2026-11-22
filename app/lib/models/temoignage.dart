import '../utils/format.dart';

/// Témoignages (lot 3c, 22 novembre 2026) : texte, photo, vidéo ou
/// audio, publiés par un membre, modérés par l'admin de l'église.
/// Modèle : Connexion Prophétique (lib/temoignages.dart), adapté :
/// isolation par church_id, modération réservée à admin_eglise,
/// statuts en_attente / approuve / rejete, médias servis par
/// /temoignages/:id/media (jeton en paramètre, voir ApiService).
/// Le statut ne s'affiche que pour l'auteur et l'admin, jamais dans
/// le fil public (seuls les approuvés y sont visibles).

/// Taille maximale d'une photo, comme côté serveur.
const tailleMaxPhotoTemoignage = 5 * 1024 * 1024;

/// Taille maximale d'une vidéo, comme côté serveur.
const tailleMaxVideoTemoignage = 25 * 1024 * 1024;

/// Taille maximale d'un audio, comme côté serveur.
const tailleMaxAudioTemoignage = 10 * 1024 * 1024;

/// Durée maximale d'une vidéo, vérifiée à la sélection.
const dureeMaxVideoTemoignage = Duration(seconds: 60);

/// Durée maximale d'un audio, vérifiée à la sélection.
const dureeMaxAudioTemoignage = Duration(minutes: 5);

/// Longueur maximale du texte, côté application et serveur.
const longueurMaxTexteTemoignage = 2000;

/// Statuts connus d'un témoignage.
const statutsTemoignage = ['en_attente', 'approuve', 'rejete'];

/// Libellé d'un statut, pour l'auteur et pour l'admin.
String libelleStatutTemoignage(String statut) {
  switch (statut) {
    case 'approuve':
      return 'Approuvé';
    case 'rejete':
      return 'Rejeté';
    default:
      return 'En attente';
  }
}

/// Un témoignage, tel que renvoyé par le serveur. [urlMedia] est le
/// chemin relatif (/temoignages/:id/media) ou null pour un texte seul ;
/// l'URL complète avec jeton se construit par [ApiService.urlMediaTemoignage].
class Temoignage {
  final String id;
  final String auteurNom;
  final String? urlMedia;
  final String texte;
  final String typeMedia; // texte | photo | video | audio
  final String statut; // en_attente | approuve | rejete
  final DateTime? creeLe;

  const Temoignage({
    required this.id,
    this.auteurNom = '',
    this.urlMedia,
    this.texte = '',
    this.typeMedia = 'texte',
    this.statut = 'en_attente',
    this.creeLe,
  });

  factory Temoignage.fromJson(Map<String, dynamic> json) => Temoignage(
        id: (json['id'] ?? '').toString(),
        auteurNom: (json['auteur_nom'] ?? '').toString(),
        urlMedia: json['url_media'] as String?,
        texte: (json['texte'] ?? '').toString(),
        typeMedia: (json['type_media'] ?? 'texte').toString(),
        statut: (json['statut'] ?? 'en_attente').toString(),
        creeLe: parseDate(json['cree_le'] as String?),
      );

  bool get approuve => statut == 'approuve';
  bool get enAttente => statut == 'en_attente';
  bool get rejete => statut == 'rejete';
  bool get estPhoto => typeMedia == 'photo';
  bool get estVideo => typeMedia == 'video';
  bool get estAudio => typeMedia == 'audio';
  bool get estTexte => typeMedia == 'texte';
}

/// Les trois listes renvoyées par GET /temoignages : le fil des
/// approuvés, mes témoignages avec leur statut, et la file de
/// modération (admin_eglise seulement, vide sinon).
class TemoignagesPageData {
  final List<Temoignage> fil;
  final List<Temoignage> miens;
  final List<Temoignage> moderation;

  const TemoignagesPageData({
    this.fil = const [],
    this.miens = const [],
    this.moderation = const [],
  });

  factory TemoignagesPageData.fromJson(Map<String, dynamic> json) {
    List<Temoignage> lire(String cle) =>
        ((json[cle] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Temoignage.fromJson)
            .toList();
    return TemoignagesPageData(
      fil: lire('temoignages'),
      miens: lire('mes_temoignages'),
      moderation: lire('moderation'),
    );
  }
}
