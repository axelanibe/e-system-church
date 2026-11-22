import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../config/app_theme.dart';
import '../models/temoignage.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Page de publication (lot 3c) : un seul compositeur, zone de texte
/// et un seul média au choix, photo ou vidéo dans la galerie, audio
/// par fichier. Le témoignage part en attente de validation par
/// l'admin de l'église, jamais direct dans le fil. Texte seul accepté,
/// sans média. Modèle : Connexion Prophétique
/// (lib/temoignages.dart, CreationTemoignagePage), adapté : pas
/// d'enregistrement audio dans l'appli en V1 (audio par fichier
/// seulement — le magnétophone viendra avec les messages vocaux),
/// pas de compression photo (le serveur vérifie le type réel dans les
/// octets et refuse ce qui dépasse les plafonds).
class CreationTemoignageScreen extends StatefulWidget {
  const CreationTemoignageScreen({super.key});

  @override
  State<CreationTemoignageScreen> createState() =>
      _CreationTemoignageScreenState();
}

/// Un média choisi pour le témoignage : un seul à la fois, photo,
/// vidéo ou audio, avec sa durée quand elle est connue.
class _MediaTemoignage {
  const _MediaTemoignage({
    required this.nom,
    required this.octets,
    required this.type,
    required this.mime,
    this.duree,
  });

  final String nom;
  final Uint8List octets;
  final String type; // photo | video | audio
  final String mime;
  final Duration? duree;
}

class _CreationTemoignageScreenState extends State<CreationTemoignageScreen> {
  final _texteControleur = TextEditingController();
  _MediaTemoignage? _media;
  bool _publicationEnCours = false;

  bool get _peutPublier =>
      !_publicationEnCours &&
      (_texteControleur.text.trim().isNotEmpty || _media != null);

  @override
  void dispose() {
    _texteControleur.dispose();
    super.dispose();
  }

  String _mimeDepuisNom(String nom) {
    switch (nom.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      default:
        return 'audio/mp4';
    }
  }

  String _typeDepuisMime(String mime) {
    if (mime.startsWith('image/')) return 'photo';
    if (mime.startsWith('video/')) return 'video';
    return 'audio';
  }

  /// Durée d'une vidéo, null quand elle ne peut pas être lue ou quand
  /// le chemin local est indisponible (web) : la vidéo est alors
  /// acceptée, le serveur ne vérifie pas la durée.
  Future<Duration?> _dureeVideo(String? chemin) async {
    if (chemin == null || chemin.isEmpty) return null;
    final controleur =
        VideoPlayerController.networkUrl(Uri.file(chemin));
    try {
      await controleur.initialize().timeout(const Duration(seconds: 10));
      return controleur.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controleur.dispose();
    }
  }

  /// Durée d'un audio, null quand il ne peut pas être lu : il est
  /// alors refusé, comme un fichier abîmé.
  Future<Duration?> _dureeAudio(Uint8List octets, String mime) async {
    final lecteur = AudioPlayer();
    try {
      await lecteur
          .setAudioSource(
            AudioSource.uri(Uri.dataFromBytes(octets, mimeType: mime)),
          )
          .timeout(const Duration(seconds: 10));
      return lecteur.duration;
    } catch (_) {
      return null;
    } finally {
      await lecteur.dispose();
    }
  }

  void _erreur(String message) {
    if (mounted) showApiError(context, message);
  }

  /// Un seul accès galerie : photo ou vidéo selon la sélection.
  Future<void> _choisirGalerie() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'mp4',
          'mov',
          'webm',
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final fichier = result.files.single;
      final octets = fichier.bytes;
      if (octets == null || !mounted) return;
      final mime = _mimeDepuisNom(fichier.name);
      final type = _typeDepuisMime(mime);
      if (type == 'photo') {
        if (octets.length > tailleMaxPhotoTemoignage) {
          _erreur('Photo trop volumineuse : 5 Mo au plus.');
          return;
        }
      } else {
        if (octets.length > tailleMaxVideoTemoignage) {
          _erreur('Vidéo trop volumineuse : 25 Mo au plus.');
          return;
        }
        final duree = await _dureeVideo(fichier.path);
        if (!mounted) return;
        if (duree != null && duree > dureeMaxVideoTemoignage) {
          _erreur('Vidéo trop longue : 60 secondes au plus.');
          return;
        }
        setState(() => _media = _MediaTemoignage(
              nom: fichier.name,
              octets: octets,
              type: 'video',
              mime: mime,
              duree: duree,
            ));
        return;
      }
      if (!mounted) return;
      setState(() => _media = _MediaTemoignage(
            nom: fichier.name,
            octets: octets,
            type: 'photo',
            mime: mime,
          ));
    } catch (_) {
      _erreur('Impossible de choisir le média.');
    }
  }

  /// Audio par sélecteur de fichier, m4a, mp3, ogg ou wav.
  Future<void> _choisirAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4a', 'mp3', 'ogg', 'wav'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final fichier = result.files.single;
      final octets = fichier.bytes;
      if (octets == null || !mounted) return;
      if (octets.length > tailleMaxAudioTemoignage) {
        _erreur('Audio trop volumineux : 10 Mo au plus.');
        return;
      }
      final mime = _mimeDepuisNom(fichier.name);
      final duree = await _dureeAudio(octets, mime);
      if (!mounted) return;
      if (duree == null) {
        _erreur('Impossible de lire cet audio.');
        return;
      }
      if (duree > dureeMaxAudioTemoignage) {
        _erreur('Audio trop long : 5 minutes au plus.');
        return;
      }
      setState(() => _media = _MediaTemoignage(
            nom: fichier.name,
            octets: octets,
            type: 'audio',
            mime: mime,
            duree: duree,
          ));
    } catch (_) {
      _erreur('Impossible de choisir l’audio.');
    }
  }

  Future<void> _publier() async {
    final texte = _texteControleur.text.trim();
    final media = _media;
    if ((texte.isEmpty && media == null) || _publicationEnCours) return;
    setState(() => _publicationEnCours = true);
    try {
      await context.read<AppState>().api.publierTemoignage(
            texte: texte.isEmpty ? null : texte,
            mediaOctets: media?.octets,
            mediaNom: media?.nom,
            mediaMime: media?.mime,
          );
      if (!mounted) return;
      showSuccess(
        context,
        'Témoignage envoyé, en attente de validation par l’admin de l’église.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _publicationEnCours = false);
    }
  }

  String _tailleEtDuree(_MediaTemoignage media) {
    final taille =
        '${(media.octets.length / 1024 / 1024).toStringAsFixed(1)} Mo';
    final duree = media.duree;
    if (duree == null) return taille;
    final minutes = duree.inMinutes;
    final secondes = duree.inSeconds % 60;
    final texteDuree = minutes > 0
        ? '$minutes min ${secondes.toString().padLeft(2, '0')} s'
        : '$secondes s';
    return '$taille · $texteDuree';
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    return Scaffold(
      appBar: AppBar(title: const Text('Publier un témoignage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Écris ton témoignage, avec une photo, une vidéo ou un audio si tu veux. Il sera visible dans le fil seulement après validation par l’admin de l’église.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _texteControleur,
            maxLines: 8,
            minLines: 4,
            maxLength: longueurMaxTexteTemoignage,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Écris ton témoignage',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _choisirGalerie,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _choisirAudio,
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('Audio'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Photo 5 Mo au plus, vidéo 25 Mo et 60 secondes au plus, audio 10 Mo et 5 minutes au plus.',
            style: TextStyle(fontSize: 12.5),
          ),
          if (media != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (media.type == 'photo')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(media.octets, fit: BoxFit.cover),
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            media.type == 'audio'
                                ? Icons.mic_outlined
                                : Icons.ondemand_video_outlined,
                            color: AppTheme.violetProfond,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  media.nom,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _tailleEtDuree(media),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Retirer',
                            onPressed: () => setState(() => _media = null),
                            icon: const Icon(Icons.close_outlined),
                          ),
                        ],
                      ),
                    if (media.type == 'photo')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _media = null),
                            icon: const Icon(Icons.close_outlined),
                            label: const Text('Retirer'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _peutPublier ? _publier : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(_publicationEnCours ? 'Publication…' : 'Publier'),
            ),
          ),
        ],
      ),
    );
  }
}
