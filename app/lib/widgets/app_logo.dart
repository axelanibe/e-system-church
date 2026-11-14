import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Logo officiel e-System Church (ESC violet/or : croix, globe, Bible
/// ouverte), affiché tel quel, sans recoloration.
///
/// Le JPEG (1254×1254) est stocké en base64 découpé en 5 parties
/// (assets/logo.jpg.b64.partaa…partae) : l'API GitHub utilisée pour
/// déposer les fichiers ne transporte pas de binaire, et chaque partie
/// reste sous la limite d'argument de l'outil. Réassemblage + décodage
/// à l'exécution. Si le chargement échoue, on retombe sur l'icône
/// église précédente au lieu de planter.
class AppLogo extends StatefulWidget {
  const AppLogo({super.key, this.size = 96});

  /// Taille affichée (carré).
  final double size;

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> {
  static const _parties = <String>[
    'assets/logo.jpg.b64.partaa',
    'assets/logo.jpg.b64.partab',
    'assets/logo.jpg.b64.partac',
    'assets/logo.jpg.b64.partad',
    'assets/logo.jpg.b64.partae',
  ];

  late final Future<Uint8List?> _octets = _charger();

  static Future<Uint8List?> _charger() async {
    try {
      final tampon = StringBuffer();
      for (final partie in _parties) {
        tampon.write(await rootBundle.loadString(partie));
      }
      return base64Decode(tampon.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _octets,
      builder: (context, snapshot) {
        final octets = snapshot.data;
        if (octets == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SizedBox(width: widget.size, height: widget.size);
          }
          return Icon(Icons.church,
              size: widget.size * 2 / 3,
              color: Theme.of(context).colorScheme.primary);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.memory(octets,
              width: widget.size, height: widget.size, fit: BoxFit.cover),
        );
      },
    );
  }
}
