import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Taille du texte (réglage local, par appareil) : quatre choix, Normal
/// par défaut, qui correspond aux tailles actuelles du thème. Le facteur
/// multiplie toutes les tailles de texte de l'application (mise à
/// l'échelle globale dans main.dart) ; les champs de saisie gardent
/// 16 px minimum une fois mis à l'échelle (voir AppTheme).
enum TailleTexte {
  petit(0.9),
  normal(1.0),
  grand(1.15),
  tresGrand(1.3);

  const TailleTexte(this.facteur);

  /// Facteur multiplicateur appliqué aux tailles de texte.
  final double facteur;

  static TailleTexte depuisValeur(String? valeur) =>
      values.firstWhere((v) => v.name == valeur, orElse: () => normal);
}

/// Préférences locales de l'application (US15, US16) : langue des
/// nouveaux écrans et mode économique. Persistées sur l'appareil
/// (stockage sécurisé), jamais envoyées au serveur.
///
/// US15 : seuls les écrans de la tranche T12 sont traduits (français
/// par défaut, anglais au choix) ; le reste de l'application reste en
/// français.
/// US16 : le mode économique coupe le chargement des photos en réseau
/// (avatars et carte) pour économiser les données. Le repli SMS, lui,
/// dépend d'un fournisseur non choisi : aucun envoi réel, aucun coût.
/// Dernière position de lecture de la Bible (livre, chapitre,
/// version), persistée sur l'appareil comme les autres réglages.
/// Sert la carte « Reprendre ma lecture » : absente tant que rien
/// n'a été lu.
class PositionLecture {
  final String code;
  final int chapitre;
  final String version;

  const PositionLecture({
    required this.code,
    required this.chapitre,
    required this.version,
  });
}

class PreferencesLocales extends ChangeNotifier {
  static const _cleLangue = 'langue';
  static const _cleEconomique = 'mode_economique';
  static const _cleTailleTexte = 'taille_texte';
  static const _cleLecture = 'lecture_bible';

  final FlutterSecureStorage _stockage;
  String _langue = 'fr';
  bool _modeEconomique = false;
  TailleTexte _tailleTexte = TailleTexte.normal;
  bool _initialise = false;
  PositionLecture? _derniereLecture;

  /// Dernière position de lecture, null si rien n'a encore été lu.
  PositionLecture? get derniereLecture => _derniereLecture;

  PreferencesLocales([FlutterSecureStorage? stockage])
      : _stockage = stockage ?? const FlutterSecureStorage();

  String get langue => _langue;
  bool get estAnglais => _langue == 'en';
  bool get modeEconomique => _modeEconomique;
  TailleTexte get tailleTexte => _tailleTexte;
  double get facteurTailleTexte => _tailleTexte.facteur;
  bool get initialise => _initialise;

  Future<void> init() async {
    final langue = await _stockage.read(key: _cleLangue);
    if (langue == 'en' || langue == 'fr') _langue = langue!;
    _modeEconomique = await _stockage.read(key: _cleEconomique) == '1';
    _tailleTexte =
        TailleTexte.depuisValeur(await _stockage.read(key: _cleTailleTexte));
    _derniereLecture =
        _positionDepuisValeur(await _stockage.read(key: _cleLecture));
    _initialise = true;
    notifyListeners();
  }

  static PositionLecture? _positionDepuisValeur(String? valeur) {
    if (valeur == null) return null;
    final parties = valeur.split('|');
    if (parties.length != 3) return null;
    final chapitre = int.tryParse(parties[1]);
    if (parties[0].isEmpty || chapitre == null || chapitre < 1) {
      return null;
    }
    return PositionLecture(
        code: parties[0], chapitre: chapitre, version: parties[2]);
  }

  /// Mémorise la position de lecture en cours (livre ouvert,
  /// chapitre affiché, version choisie).
  Future<void> definirLecture({
    required String code,
    required int chapitre,
    required String version,
  }) async {
    _derniereLecture =
        PositionLecture(code: code, chapitre: chapitre, version: version);
    await _stockage.write(
        key: _cleLecture, value: '$code|$chapitre|$version');
    notifyListeners();
  }

  Future<void> definirLangue(String langue) async {
    if (langue != 'fr' && langue != 'en') return;
    if (_langue == langue) return;
    _langue = langue;
    await _stockage.write(key: _cleLangue, value: langue);
    notifyListeners();
  }

  Future<void> definirModeEconomique(bool actif) async {
    if (_modeEconomique == actif) return;
    _modeEconomique = actif;
    await _stockage.write(key: _cleEconomique, value: actif ? '1' : '0');
    notifyListeners();
  }

  Future<void> definirTailleTexte(TailleTexte taille) async {
    if (_tailleTexte == taille) return;
    _tailleTexte = taille;
    await _stockage.write(key: _cleTailleTexte, value: taille.name);
    notifyListeners();
  }
}
