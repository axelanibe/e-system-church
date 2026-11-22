import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../models/temoignage.dart';

/// Lecteur plein écran d'un témoignage (lot 3c), comme le lecteur de
/// story de Connexion Prophétique : vidéo en lecture automatique,
/// photo affichée, audio avec lecteur, texte lu sur place. Toucher la
/// vidéo pour mettre en pause ou reprendre, bouton pour revoir à la fin.
class LecteurTemoignageScreen extends StatefulWidget {
  const LecteurTemoignageScreen({
    super.key,
    required this.temoignage,
    required this.urlMedia,
  });

  final Temoignage temoignage;

  /// URL complète du média (avec jeton), vide pour un texte seul.
  final String urlMedia;

  @override
  State<LecteurTemoignageScreen> createState() =>
      _LecteurTemoignageScreenState();
}

class _LecteurTemoignageScreenState extends State<LecteurTemoignageScreen> {
  VideoPlayerController? _controleurVideo;
  AudioPlayer? _lecteurAudio;
  bool _erreur = false;
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    final t = widget.temoignage;
    if (t.estVideo && widget.urlMedia.isNotEmpty) {
      _controleurVideo =
          VideoPlayerController.networkUrl(Uri.parse(widget.urlMedia))
            ..initialize().then((_) {
              if (!mounted) return;
              setState(() {});
              _controleurVideo!.play();
              _controleurVideo!.addListener(_surveillerVideo);
            }).catchError((_) {
              if (mounted) setState(() => _erreur = true);
            });
    }
    if (t.estAudio && widget.urlMedia.isNotEmpty) {
      _lecteurAudio = AudioPlayer();
      _lecteurAudio!
          .setAudioSource(AudioSource.uri(Uri.parse(widget.urlMedia)))
          .catchError((_) {
        if (mounted) setState(() => _erreur = true);
        return null;
      });
    }
  }

  void _surveillerVideo() {
    final controleur = _controleurVideo;
    if (controleur == null || !controleur.value.isInitialized) return;
    if (controleur.value.position >= controleur.value.duration &&
        controleur.value.duration != Duration.zero) {
      controleur.removeListener(_surveillerVideo);
      if (mounted) setState(() => _termine = true);
    }
  }

  @override
  void dispose() {
    _controleurVideo?.removeListener(_surveillerVideo);
    _controleurVideo?.dispose();
    _lecteurAudio?.dispose();
    super.dispose();
  }

  String _formaterDuree(Duration duree) {
    final minutes = duree.inMinutes;
    final secondes = duree.inSeconds % 60;
    return '$minutes:${secondes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.temoignage;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(t.auteurNom.isEmpty ? 'Témoignage' : t.auteurNom),
      ),
      body: SafeArea(
        child: Center(child: _corps()),
      ),
    );
  }

  Widget _corps() {
    final t = widget.temoignage;
    if (t.estPhoto) {
      if (widget.urlMedia.isEmpty) return _iconeErreur();
      return Image.network(
        widget.urlMedia,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _iconeErreur(),
      );
    }
    if (t.estAudio) {
      if (_erreur) return _iconeErreur();
      final lecteur = _lecteurAudio;
      if (lecteur == null) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: _LecteurAudio(
          lecteur: lecteur,
          formaterDuree: _formaterDuree,
        ),
      );
    }
    if (t.estTexte) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          t.texte,
          style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.5),
        ),
      );
    }
    final controleur = _controleurVideo;
    if (_erreur) return _iconeErreur();
    if (controleur == null || !controleur.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return GestureDetector(
      onTap: () {
        if (_termine) {
          controleur.seekTo(Duration.zero);
          setState(() => _termine = false);
          controleur.play();
          controleur.addListener(_surveillerVideo);
        } else if (controleur.value.isPlaying) {
          controleur.pause();
          setState(() {});
        } else {
          controleur.play();
          setState(() {});
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: controleur.value.aspectRatio,
            child: VideoPlayer(controleur),
          ),
          if (_termine)
            const Icon(Icons.replay_outlined, color: Colors.white, size: 56)
          else if (!controleur.value.isPlaying)
            const Icon(
              Icons.play_circle_outlined,
              color: Colors.white70,
              size: 56,
            ),
        ],
      ),
    );
  }

  Widget _iconeErreur() =>
      const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48);
}

/// Lecteur audio simple : lecture / pause, progression et durées.
class _LecteurAudio extends StatelessWidget {
  const _LecteurAudio({required this.lecteur, required this.formaterDuree});

  final AudioPlayer lecteur;
  final String Function(Duration) formaterDuree;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<PlayerState>(
          stream: lecteur.playerStateStream,
          builder: (context, snapshot) {
            final enCours = snapshot.data?.playing ?? false;
            return IconButton(
              iconSize: 64,
              color: Colors.white,
              onPressed: () {
                if (enCours) {
                  lecteur.pause();
                } else {
                  lecteur.play();
                }
              },
              icon: Icon(
                enCours
                    ? Icons.pause_circle_outlined
                    : Icons.play_circle_outlined,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        StreamBuilder<Duration>(
          stream: lecteur.positionStream,
          builder: (context, snapshotPosition) {
            final position = snapshotPosition.data ?? Duration.zero;
            return StreamBuilder<Duration?>(
              stream: lecteur.durationStream,
              builder: (context, snapshotDuree) {
                final duree = snapshotDuree.data ?? Duration.zero;
                final maxMs = duree.inMilliseconds;
                return Column(
                  children: [
                    Slider(
                      value: maxMs <= 0
                          ? 0
                          : position.inMilliseconds
                              .clamp(0, maxMs)
                              .toDouble(),
                      max: maxMs <= 0 ? 1 : maxMs.toDouble(),
                      onChanged: (valeur) => lecteur.seek(
                        Duration(milliseconds: valeur.round()),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formaterDuree(position),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          formaterDuree(duree),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
