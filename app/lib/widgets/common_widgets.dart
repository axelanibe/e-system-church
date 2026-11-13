import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Indicateur de chargement centré.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Traduit une erreur technique en phrase simple en français, pour une
/// personne qui n'a aucune notion de technologie. Une phrase déjà claire
/// est gardée telle quelle, le reste devient un message générique
/// compréhensible. Ex. « ClientException: Load failed » devient
/// « Pas de connexion internet. Vérifiez votre connexion et réessayez. »
String messageErreurSimple(Object error) {
  final brut = error.toString();
  final bas = brut.toLowerCase();
  if (bas.contains('load failed') ||
      bas.contains('socketexception') ||
      bas.contains('failed host lookup') ||
      bas.contains('network is unreachable') ||
      bas.contains('connection refused')) {
    return 'Pas de connexion internet. Vérifiez votre connexion et réessayez.';
  }
  if (bas.contains('invalid_code') || bas.contains('code inconnu')) {
    return 'Code d’église inconnu. Demandez-le à votre pasteur.';
  }
  if (bas.contains('email_taken')) {
    return 'Cet e-mail est déjà utilisé.';
  }
  if (bas.contains('401') ||
      bas.contains('unauthorized') ||
      bas.contains('mot de passe incorrect') ||
      bas.contains('e-mail ou mot de passe')) {
    return 'E-mail ou mot de passe incorrect.';
  }
  if (bas.contains('403') || bas.contains('forbidden')) {
    return 'Vous n’avez pas accès à cette fonction.';
  }
  if (bas.contains('404') || bas.contains('not found')) {
    return 'Introuvable. Vérifiez et réessayez.';
  }
  if (bas.contains('409')) {
    return 'Cette information existe déjà.';
  }
  if (bas.contains('foreign key') ||
      bas.contains('violates') ||
      bas.contains('constraint')) {
    return 'Impossible de supprimer : cet élément est encore utilisé ailleurs.';
  }
  if (bas.contains('exception') ||
      bas.contains('error') ||
      bas.contains('failed') ||
      bas.contains('null check') ||
      bas.contains('typeerror')) {
    return 'Quelque chose ne va pas. Vérifiez votre connexion et réessayez.';
  }
  return brut;
}

/// Panneau d'erreur avec bouton « Réessayer ».
class AppError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(messageErreurSimple(message), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// État vide (liste sans élément).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Titre de section (majuscules légères, espacement).
class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Petite pastille colorée de statut.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 14)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// Carte de statistique de l'artefact : libellé en haut, sur une
/// seule ligne, valeur en mono en dessous. Le libellé et la valeur
/// se rétrécissent au lieu d'être coupés au bord de la carte.
/// L'icône est gardée au constructeur pour compatibilité, mais
/// l'artefact n'en montre pas, elle n'est plus affichée.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? aide;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.aide,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.bleuNuit.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTheme.styleCode.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color ?? AppTheme.bleuNuit,
                ),
              ),
            ),
            if (aide != null) ...[
              const SizedBox(height: 2),
              Text(
                aide!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}

/// Affiche une erreur d'API dans un SnackBar.
void showApiError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(messageErreurSimple(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

/// Affiche une confirmation dans un SnackBar.
void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
