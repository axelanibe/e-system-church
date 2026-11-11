import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/church.dart';
import '../state/app_state.dart';

/// Avatar de l'église active : logo (NetworkImage) quand l'église en a un,
/// sinon ses initiales sur fond de sa couleur principale.
class ChurchAvatar extends StatelessWidget {
  final Church? church;
  final double radius;

  const ChurchAvatar({super.key, required this.church, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final c = church;
    if (c == null) {
      return CircleAvatar(
        radius: radius,
        child: const Icon(Icons.church_outlined),
      );
    }
    final logoUrl = c.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      final baseUrl = context.read<AppState>().apiBaseUrl;
      final fullUrl = logoUrl.startsWith('http') ? logoUrl : '$baseUrl$logoUrl';
      return CircleAvatar(
        radius: radius,
        backgroundColor: c.couleur,
        backgroundImage: NetworkImage(fullUrl),
        onBackgroundImageError: (_, __) {},
        child: Text(
          c.initiales,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.8,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.couleur,
      child: Text(
        c.initiales,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
