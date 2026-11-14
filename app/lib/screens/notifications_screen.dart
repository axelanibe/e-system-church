import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// T11 — Notifications : boîte d'envoi (push et SMS), création, envoi,
/// et paramètres du fournisseur. Aucun fournisseur n'est branché :
/// tant qu'Axel n'a pas choisi de fournisseur, l'envoi reste en
/// attente et rien ne part. La clé n'est jamais affichée.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  ParametresConfiance? _parametres;
  List<NotificationConfiance> _notifications = [];
  bool _chargement = true;
  String? _erreur;
  String? _message;

  final _titreController = TextEditingController();
  final _messageController = TextEditingController();
  final _fournisseurController = TextEditingController();
  final _cleController = TextEditingController();
  final _plafondController = TextEditingController();
  String _canal = 'push';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _titreController.dispose();
    _messageController.dispose();
    _fournisseurController.dispose();
    _cleController.dispose();
    _plafondController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final api = context.read<AppState>().api;
      final parametres = await api.getParametresConfiance();
      final notifications = await api.getNotifications();
      if (!mounted) return;
      setState(() {
        _parametres = parametres;
        _notifications = notifications;
        _fournisseurController.text =
            parametres.notificationFournisseur ?? '';
        _plafondController.text =
            parametres.notificationPlafondMensuel.toString();
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _chargement = false;
      });
    }
  }

  Future<void> _creer() async {
    final titre = _titreController.text.trim();
    final message = _messageController.text.trim();
    if (titre.isEmpty || message.isEmpty) {
      setState(() => _erreur = 'Titre et message obligatoires.');
      return;
    }
    try {
      final notification = await context.read<AppState>().api.createNotification(
            canal: _canal,
            titre: titre,
            message: message,
          );
      if (!mounted) return;
      setState(() {
        _notifications = [notification, ..._notifications];
        _titreController.clear();
        _messageController.clear();
        _message = 'Notification créée en file.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Future<void> _envoyer(NotificationConfiance notification) async {
    try {
      final miseAJour =
          await context.read<AppState>().api.envoyerNotification(notification.id);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => n.id == miseAJour.id ? miseAJour : n)
            .toList();
        _message = miseAJour.statut == 'envoyee'
            ? 'Notification envoyée.'
            : 'Envoi impossible : ${miseAJour.erreur ?? 'fournisseur non configuré'}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  Future<void> _sauverParametres() async {
    final plafond = int.tryParse(_plafondController.text.trim());
    try {
      final parametres =
          await context.read<AppState>().api.patchParametresConfiance(
                notificationFournisseur:
                    _fournisseurController.text.trim().isEmpty
                        ? null
                        : _fournisseurController.text.trim(),
                notificationCle: _cleController.text.trim().isEmpty
                    ? null
                    : _cleController.text.trim(),
                notificationPlafondMensuel: plafond,
              );
      if (!mounted) return;
      setState(() {
        _parametres = parametres;
        _cleController.clear();
        _message = 'Paramètres enregistrés. La clé n’est jamais affichée.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_erreur != null)
                    Card(
                      color: AppTheme.rougeErreur.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_erreur!),
                      ),
                    ),
                  if (_message != null)
                    Card(
                      color: AppTheme.vertFonce.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fournisseur',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _parametres?.notificationsConfigurees == true
                                ? 'Fournisseur configuré : ${_parametres!.notificationFournisseur ?? ''}.'
                                : 'Aucun fournisseur choisi pour le moment : les notifications restent en file, rien n’est envoyé.',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _fournisseurController,
                            decoration: const InputDecoration(
                              labelText: 'Fournisseur (à compléter)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _cleController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Clé du fournisseur',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _plafondController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Plafond mensuel (nombre)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            value: _parametres?.notificationsActives ?? false,
                            title: const Text('Notifications actives'),
                            onChanged: (valeur) async {
                              try {
                                final parametres = await context
                                    .read<AppState>()
                                    .api
                                    .patchParametresConfiance(
                                        notificationsActives: valeur);
                                if (!mounted) return;
                                setState(() => _parametres = parametres);
                              } catch (e) {
                                if (!mounted) return;
                                setState(
                                    () => _erreur = messageErreurSimple(e));
                              }
                            },
                          ),
                          FilledButton(
                            onPressed: _sauverParametres,
                            child: const Text('Enregistrer les paramètres'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nouvelle notification',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _canal,
                            decoration: const InputDecoration(
                              labelText: 'Canal',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'push', child: Text('Push')),
                              DropdownMenuItem(
                                  value: 'sms', child: Text('SMS')),
                            ],
                            onChanged: (valeur) {
                              if (valeur != null) {
                                setState(() => _canal = valeur);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _titreController,
                            decoration: const InputDecoration(
                              labelText: 'Titre',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _messageController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Message',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _creer,
                            child: const Text('Créer la notification'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Boîte d’envoi',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_notifications.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune notification.'),
                      ),
                    ),
                  for (final notification in _notifications)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.orClair,
                          child: Icon(
                            notification.canal == 'sms'
                                ? Icons.sms_outlined
                                : Icons.notifications_outlined,
                            color: AppTheme.orFonce,
                          ),
                        ),
                        title: Text(notification.titre),
                        subtitle: Text(
                          '${notification.canalLabel} · ${notification.statutLabel} · ${formatDateTime(notification.createdAt)}'
                          '${notification.erreur == null ? '' : '\n${notification.erreur}'}',
                        ),
                        isThreeLine: notification.erreur != null,
                        trailing: notification.statut == 'en_attente'
                            ? TextButton(
                                onPressed: () => _envoyer(notification),
                                child: const Text('Envoyer'),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
