import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../state/app_state.dart';
import '../widgets/carte_membre_visuelle.dart';
import '../widgets/common_widgets.dart';

/// Page Carte seule (tranche P1, refonte 24 novembre 2026) : seul le
/// visuel de la carte, sans titre, sans paiement ni modification.
/// Format pass vertical centré (maquette), QR réel
/// (CODE_EGLISE:MATRICULE), actions « Télécharger ma carte » (PNG,
/// capture de la carte à 3x) et « Copier mon code » (le code de
/// vérification, pas l'image du QR).
class CarteFideleScreen extends StatefulWidget {
  const CarteFideleScreen({super.key});

  @override
  State<CarteFideleScreen> createState() => _CarteFideleScreenState();
}

class _CarteFideleScreenState extends State<CarteFideleScreen> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<void> _charger() async {
    // La carte est chargée par _CarteMembreSeule. Ici, on vérifie
    // seulement que le compte est lié à un membre.
    final profil = await context.read<AppState>().api.getMoi();
    if (profil.memberId == null) {
      throw Exception('Aucun membre lié à ce compte.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _charger()),
          );
        }
        return const _CarteMembreSeule();
      },
    );
  }
}

/// Carte du fidèle, chargée depuis le serveur puis affichée seule,
/// en format pass vertical centré.
class _CarteMembreSeule extends StatefulWidget {
  const _CarteMembreSeule();

  @override
  State<_CarteMembreSeule> createState() => _CarteMembreSeuleState();
}

class _CarteMembreSeuleState extends State<_CarteMembreSeule> {
  late Future<MaCarte> _future;
  final GlobalKey _cleCarte = GlobalKey();
  bool _telechargementEnCours = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMaCarte();
  }

  /// QR de la carte : CODE_EGLISE:MATRICULE, même règle que la
  /// fiche membre. Le lecteur accepte aussi les anciennes cartes,
  /// matricule seul.
  String _qrData(String? codeEglise, String matricule) =>
      codeEglise != null && codeEglise.isNotEmpty
          ? '$codeEglise:$matricule'
          : matricule;

  Future<void> _telecharger() async {
    if (_telechargementEnCours) return;
    setState(() => _telechargementEnCours = true);
    try {
      final boundary =
          _cleCarte.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final octets = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = octets?.buffer.asUint8List();
      if (png == null) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              png,
              name: 'ma-carte-e-system-church.png',
              mimeType: 'image/png',
            ),
          ],
          subject: 'Ma carte — e-System Church',
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _telechargementEnCours = false);
    }
  }

  Future<void> _copierCode(String qrData) async {
    await Clipboard.setData(ClipboardData(text: qrData));
    if (mounted) showSuccess(context, 'Code copié.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaCarte>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: () => setState(
              () => _future = context.read<AppState>().api.getMaCarte(),
            ),
          );
        }
        final carte = snapshot.data!;
        final qrData = _qrData(
          context.read<AppState>().church?.code,
          carte.member.matricule,
        );
        // La carte visuelle seule, en pass vertical, avec ses deux
        // actions et la note de la projection en dessous : les
        // modifications se font depuis le profil.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _cleCarte,
                    child: CarteMembreVisuelle(
                      member: carte.member,
                      qrData: qrData,
                      vertical: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _telechargementEnCours ? null : _telecharger,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Télécharger ma carte'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _copierCode(qrData),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copier mon code'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'La carte affiche le visuel seul : photo, nom, matricule, '
                    'établissement et QR. Les modifications se font depuis le '
                    'profil.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: PaletteMembre.texteSecondaire,
                          fontSize: AppFontSizes.s12_5,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
