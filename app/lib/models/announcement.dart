import '../utils/format.dart';

/// Annonce (`announcements`). `broadcast = true` : diffusée à tout le réseau.
class Announcement {
  final String id;
  final String title;
  final String body;
  final bool broadcast;
  final DateTime? createdAt;
  final String? churchId;
  final String? egliseNom;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.broadcast,
    this.createdAt,
    this.churchId,
    this.egliseNom,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        broadcast: json['broadcast'] as bool? ?? false,
        createdAt: parseDate(json['created_at'] as String?),
        churchId: json['church_id'] as String?,
        egliseNom: json['eglise_nom'] as String?,
      );
}
