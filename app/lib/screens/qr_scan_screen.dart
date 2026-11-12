import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../state/app_state.dart';
import '../utils/qr_carte.dart';

/// Scan réel de la carte de membre par la caméra.
///
/// Le QR de la carte contient `CODE_EGLISE:MATRICULE`. Le code est vérifié
/// ici avant l'appel, puis le serveur vérifie à nouveau que le membre
/// appartient à l'église de la session : une carte d'une autre église est
/// refusée avec un message clair, jamais pointée.
///
/// Après chaque pointage réussi, le scan reprend tout seul pour la
/// personne suivante, sans quitter l'écran : c'est ce qui sert à l'entrée
/// du culte. La saisie manuelle par matricule reste le repli, depuis
/// l'écran Présences, quand la caméra est refusée ou absente.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.culteId});

  final String culteId;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _controller;
  bool _enCours = false;
  bool _torche = false;
  String? _message;
  bool _succes = false;
  int _pointes = 0;
  String? _dernierCode;
  DateTime? _dernierInstant;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _traiterCode(String brut) async {
    if (_enCours) return;
    final maintenant = DateTime.now();
    if (_dernierCode == brut &&
        _dernierInstant != null &&
        maintenant.difference(_dernierInstant!).inSeconds < 3) {
      return;
    }
    _dernierCode = brut;
    _dernierInstant = maintenant;
    _enCours = true;

    final state = context.read<AppState>();
    final lecture = lireQrCarte(brut, codeEglise: state.church?.code);
    if (!lecture.ok) {
      _afficher(lecture.erreur!, succes: false);
      return;
    }
    try {
      final presence = await state.api.pointerPresence(
        matricule: lecture.matricule,
        culteId: widget.culteId,
        statut: 'present',
        mode: 'scan_qr',
      );
      if (!mounted) return;
      setState(() => _pointes++);
      _afficher(
        'Présence pointée : ${presence.membreNom ?? lecture.matricule}.',
        succes: true,
      );
    } catch (e) {
      _afficher(e.toString(), succes: false);
    }
  }

  void _afficher(String message, {required bool succes}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _succes = succes;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _enCours = false);
    });
  }

  void _basculerTorche() {
    setState(() => _torche = !_torche);
    _controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner une carte'),
        actions: [
          IconButton(
            onPressed: _basculerTorche,
            icon: Icon(_torche ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampe torche',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    for (final code in capture.barcodes) {
                      final valeur = code.rawValue;
                      if (valeur != null && valeur.isNotEmpty) {
                        _traiterCode(valeur);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) {
                    final refuse =
                        error.errorCode ==
                        MobileScannerErrorCode.permissionDenied;
                    return _ErreurCamera(
                      refuse: refuse,
                      onManuel: () => Navigator.of(context).pop(),
                    );
                  },
                ),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.orAmbre,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: AppTheme.cypress,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _message ?? 'Placez le QR de la carte dans le cadre.',
                  style: TextStyle(
                    color: _message == null
                        ? Colors.white
                        : (_succes ? Colors.white : Colors.red.shade200),
                    fontWeight:
                        _message == null ? FontWeight.normal : FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _pointes == 0
                      ? 'Le scan reprend tout seul après chaque pointage.'
                      : '$_pointes présence(s) pointée(s) pendant ce scan.',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Saisir le matricule à la main'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panneau affiché quand la caméra ne démarre pas.
class _ErreurCamera extends StatelessWidget {
  const _ErreurCamera({required this.refuse, required this.onManuel});

  final bool refuse;
  final VoidCallback onManuel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.fondAlabaster,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 64,
            color: AppTheme.cypress,
          ),
          const SizedBox(height: 16),
          Text(
            refuse
                ? 'L’appareil photo est nécessaire pour scanner une carte. '
                    'Autorisez l’appareil photo dans les réglages du '
                    'téléphone, ou saisissez le matricule à la main.'
                : 'La caméra n’a pas pu démarrer sur ce téléphone. '
                    'Saisissez le matricule à la main.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onManuel,
            icon: const Icon(Icons.keyboard_outlined),
            label: const Text('Saisir le matricule à la main'),
          ),
        ],
      ),
    );
  }
}
