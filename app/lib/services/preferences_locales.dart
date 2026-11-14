import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
class PreferencesLocales extends ChangeNotifier {
  static const _cleLangue = 'langue';
  static const _cleEconomique = 'mode_economique';

  final FlutterSecureStorage _stockage;
  String _langue = 'fr';
  bool _modeEconomique = false;
  bool _initialise = false;

  PreferencesLocales([FlutterSecureStorage? stockage])
      : _stockage = stockage ?? const FlutterSecureStorage();

  String get langue => _langue;
  bool get estAnglais => _langue == 'en';
  bool get modeEconomique => _modeEconomique;
  bool get initialise => _initialise;

  Future<void> init() async {
    final langue = await _stockage.read(key: _cleLangue);
    if (langue == 'en' || langue == 'fr') _langue = langue!;
    _modeEconomique = await _stockage.read(key: _cleEconomique) == '1';
    _initialise = true;
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
}
