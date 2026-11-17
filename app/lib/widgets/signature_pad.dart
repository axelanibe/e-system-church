import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/attestation.dart';
import '../utils/format.dart';

/// Signature électronique dessinée (V1), faite maison, zéro nouvelle
/// dépendance : [CustomPaint] + [GestureDetector], traits lissés par
/// courbes de Bézier, export en points normalisés 0..1 + PNG (fond
/// blanc, trait violet profond #2A0059). Le tracé ne quitte jamais
/// l'appareil avant validation : il monte au serveur en un seul POST.
///
/// Seuils de validation locale : au moins 8 points et 30 px de trait
/// au total, sinon la signature est refusée (« signature vide »).
const int _signatureMinPoints = 8;
const double _signatureMinLongueur = 30;

/// Tracé validé : points normalisés 0..1 et image PNG du tracé.
class SignatureTrace {
  const SignatureTrace({required this.points, required this.pngBytes});

  /// Points normalisés 0..1, dans l'ordre du tracé.
  final List<Offset> points;

  /// PNG du tracé (fond blanc, trait violet profond).
  final Uint8List pngBytes;
}

/// Validation locale d'un tracé : nombre de points et longueur totale
/// minimaux. Pure, donc testable sans widget.
bool traitsSignatureValides(List<List<Offset>> traits) {
  var nbPoints = 0;
  var longueur = 0.0;
  for (final trait in traits) {
    nbPoints += trait.length;
    for (var i = 1; i < trait.length; i++) {
      longueur += (trait[i] - trait[i - 1]).distance;
    }
  }
  return nbPoints >= _signatureMinPoints &&
      longueur >= _signatureMinLongueur;
}

/// Chemin lissé d'un trait : courbes quadratiques par les milieux.
Path _cheminLisse(List<Offset> trait) {
  final chemin = Path();
  if (trait.isEmpty) return chemin;
  chemin.moveTo(trait.first.dx, trait.first.dy);
  for (var i = 1; i < trait.length; i++) {
    final milieu = Offset(
      (trait[i - 1].dx + trait[i].dx) / 2,
      (trait[i - 1].dy + trait[i].dy) / 2,
    );
    chemin.quadraticBezierTo(
        trait[i - 1].dx, trait[i - 1].dy, milieu.dx, milieu.dy);
  }
  chemin.lineTo(trait.last.dx, trait.last.dy);
  return chemin;
}

Paint _peintureTrait() => Paint()
  ..color = AppTheme.violetProfond
  ..strokeWidth = 3
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _dessinerTraits(Canvas canvas, List<List<Offset>> traits) {
  final peinture = _peintureTrait();
  final peinturePoint = Paint()
    ..color = AppTheme.violetProfond
    ..style = PaintingStyle.fill;
  for (final trait in traits) {
    if (trait.length == 1) {
      canvas.drawCircle(trait.first, 1.5, peinturePoint);
    } else {
      canvas.drawPath(_cheminLisse(trait), peinture);
    }
  }
}

class _PeintreSignature extends CustomPainter {
  const _PeintreSignature(this.traits);

  final List<List<Offset>> traits;

  @override
  void paint(Canvas canvas, Size size) => _dessinerTraits(canvas, traits);

  @override
  bool shouldRepaint(_PeintreSignature oldDelegate) =>
      oldDelegate.traits != traits;
}

/// Cadre de signature dessinée : zone de tracé, boutons Effacer et
/// Valider. [onValide] n'est appelé qu'avec un tracé valide ; sinon un
/// message « signature vide » s'affiche sous le cadre.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.onValide, this.hauteur = 220});

  final ValueChanged<SignatureTrace> onValide;

  /// Hauteur de la zone de tracé.
  final double hauteur;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _traits = [];
  String? _erreur;

  /// Traits en cours, en coordonnées du cadre (pour les tests).
  List<List<Offset>> get traits => List.unmodifiable(_traits);

  /// Efface le tracé et le message d'erreur.
  void effacer() {
    setState(() {
      _traits.clear();
      _erreur = null;
    });
  }

  Future<void> _valider() async {
    if (!traitsSignatureValides(_traits)) {
      setState(() => _erreur = 'Signature vide : signez dans le cadre.');
      return;
    }
    final taille = context.size;
    if (taille == null) return;
    final trace = await _exporter(taille);
    widget.onValide(trace);
  }

  Future<SignatureTrace> _exporter(Size taille) async {
    final enregistreur = ui.PictureRecorder();
    final canvas = Canvas(enregistreur);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, taille.width, taille.height),
      Paint()..color = Colors.white,
    );
    _dessinerTraits(canvas, _traits);
    final image = await enregistreur
        .endRecording()
        .toImage(taille.width.toInt(), taille.height.toInt());
    final octets =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final points = [
      for (final trait in _traits)
        for (final p in trait)
          Offset(
            (p.dx / taille.width).clamp(0.0, 1.0),
            (p.dy / taille.height).clamp(0.0, 1.0),
          ),
    ];
    return SignatureTrace(
      points: points,
      pngBytes: octets!.buffer.asUint8List(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: widget.hauteur,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.bordure, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onPanStart: (details) => setState(() {
                    _traits.add([details.localPosition]);
                    _erreur = null;
                  }),
                  onPanUpdate: (details) => setState(
                      () => _traits.last.add(details.localPosition)),
                  child: CustomPaint(painter: _PeintreSignature(_traits)),
                ),
              ),
              if (_traits.isEmpty)
                const Center(
                  child: Text(
                    'Signez ici',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_erreur!,
                style: const TextStyle(
                    color: AppTheme.rougeErreur, fontSize: 13)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _traits.isEmpty ? null : effacer,
                icon: const Icon(Icons.clear_outlined),
                label: const Text('Effacer', style: TextStyle(fontSize: 13.5)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _valider,
                icon: const Icon(Icons.check_outlined),
                label: const Text('Valider', style: TextStyle(fontSize: 13.5)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Résultat du dialogue de signature : nom du signataire et tracé.
typedef ResultatSignature = ({String nom, SignatureTrace trace});

/// Dialogue de signature dessinée : champ nom (16 px, pré-rempli) +
/// [SignaturePad]. Renvoie null si l'utilisateur annule. Le nom est
/// obligatoire : un tracé validé sans nom affiche une erreur au lieu
/// de fermer le dialogue.
Future<ResultatSignature?> montrerDialogueSignature(
  BuildContext context, {
  required String titre,
  required String nomInitial,
}) async {
  final nomCtrl = TextEditingController(text: nomInitial);
  try {
    return await showDialog<ResultatSignature>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String? erreurNom;
          return AlertDialog(
            title: Text(titre, style: const TextStyle(fontSize: 17)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nomCtrl,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Signataire',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (erreurNom != null) {
                        setDialogState(() => erreurNom = null);
                      }
                    },
                  ),
                  if (erreurNom != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(erreurNom!,
                          style: const TextStyle(
                              color: AppTheme.rougeErreur, fontSize: 13)),
                    ),
                  const SizedBox(height: 12),
                  SignaturePad(
                    onValide: (trace) {
                      if (nomCtrl.text.trim().isEmpty) {
                        setDialogState(() => erreurNom =
                            'Indiquez le nom du signataire.');
                        return;
                      }
                      Navigator.of(ctx).pop(
                          (nom: nomCtrl.text.trim(), trace: trace));
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    nomCtrl.dispose();
  }
}

/// Mention d'une signature existante (vue membre, lecture seule) :
/// rien tant que la signature n'existe pas, sinon nom, date et image
/// du tracé. [future] vaut null quand le document n'est pas signé.
class MentionSignature extends StatelessWidget {
  const MentionSignature({super.key, required this.future});

  final Future<Signature?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Signature?>(
      future: future,
      builder: (context, snapshot) {
        final signature = snapshot.data;
        if (signature == null) return const SizedBox.shrink();
        final image = signature.imageBytes;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.draw_outlined,
                  size: 16, color: AppTheme.violetProfond),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Signé par ${signature.signataireNom}'
                  '${signature.dateSignature != null ? ' · ${formatDate(signature.dateSignature)}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (image != null)
                Image.memory(image,
                    width: 72, height: 28, fit: BoxFit.contain),
            ],
          ),
        );
      },
    );
  }
}
