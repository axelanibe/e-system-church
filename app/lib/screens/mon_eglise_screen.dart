import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/fidele.dart';
import '../models/parametres.dart';
import '../models/profil.dart';
import '../state/app_state.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/mere_badge.dart';
import 'paiements_screen.dart';

/// Module 13 — « Mon église » : identité publique de l'église active
/// (logo, nom, code, description, horaires, contacts, pasteur principal,
/// antennes) et édition du profil. Les contacts viennent des paramètres
/// de l'église (l'entité Church ne porte pas adresse / téléphone / e-mail).
class MonEgliseScreen extends StatefulWidget {
  const MonEgliseScreen({super.key});

  @override
  State<MonEgliseScreen> createState() => _MonEgliseScreenState();
}

class _MonEgliseScreenState extends State<MonEgliseScreen> {
  late Future<ProfilEglise> _future;
  late Future<EgliseParametres> _parametresFuture;
  Future<List<DemandeLiaison>>? _demandesFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _parametresFuture = context.read<AppState>().api.getParametres();
    if (context.read<AppState>().isAdmin) {
      _demandesFuture = context.read<AppState>().api.getDemandesLiaison();
    }
  }

  Future<ProfilEglise> _load() {
    final state = context.read<AppState>();
    return state.api.getPresentation(state.church!.code);
  }

  void _refresh() {
    setState(() {
      _future = _load();
      _parametresFuture = context.read<AppState>().api.getParametres();
      _refreshDemandes();
    });
  }

  void _refreshDemandes() {
    if (context.read<AppState>().isAdmin) {
      _demandesFuture = context.read<AppState>().api.getDemandesLiaison();
    }
  }

  /// Valide ou refuse une demande de liaison (admin).
  Future<void> _decider(DemandeLiaison demande, bool accepter) async {
    try {
      await context
          .read<AppState>()
          .api
          .decideDemandeLiaison(demande.id, accept: accepter);
      if (mounted) {
        showSuccess(
            context,
            accepter
                ? 'Liaison validée : le fidèle peut se connecter.'
                : 'Demande refusée.');
      }
      setState(_refreshDemandes);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Invitation par l'admin : le dialogue ne fait que saisir les données ;
  /// l'appel API a lieu ici (contexte de l'écran), puis le lien est affiché
  /// à transmettre (WhatsApp, SMS, etc.). Le lien expire dans 7 jours ;
  /// le jeton n'est exposé nulle part ailleurs.
  Future<void> _inviter() async {
    final emailController = TextEditingController();
    final memberIdController = TextEditingController();
    final nomController = TextEditingController();
    String role = 'membre';
    final saisie = await showDialog<_InviteSaisie>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inviter une personne'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                dialogTextField(
                  controller: emailController,
                  label: 'E-mail',
                  keyboardType: TextInputType.emailAddress,
                ),
                dialogDropdown<String>(
                  value: role,
                  label: 'Rôle dans l’église',
                  options: const {
                    'membre': 'Membre (fidèle)',
                    'tresorier': 'Trésorier',
                    'responsable_culte': 'Responsable de culte',
                    'admin_eglise': 'Admin d’église',
                  },
                  onChanged: (v) {
                    if (v != null) setDialogState(() => role = v);
                  },
                ),
                dialogTextField(
                  controller: memberIdController,
                  label: 'ID de la fiche membre (optionnel)',
                  hintText: 'Pour lier le compte à un membre existant',
                ),
                dialogTextField(
                  controller: nomController,
                  label: 'Nom complet (optionnel)',
                ),
                const Text(
                  'Le compte est créé sans mot de passe : la personne '
                  'l’initialise avec le lien (valable 7 jours).',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (emailController.text.trim().isEmpty ||
                    !emailController.text.contains('@')) {
                  return;
                }
                Navigator.of(dialogContext).pop(_InviteSaisie(
                  email: emailController.text.trim(),
                  role: role,
                  memberId: memberIdController.text.trim().isEmpty
                      ? null
                      : memberIdController.text.trim(),
                  fullName: nomController.text.trim().isEmpty
                      ? null
                      : nomController.text.trim(),
                ));
              },
              child: const Text('Créer l’invitation'),
            ),
          ],
        ),
      ),
    );
    if (saisie == null) return;
    if (!mounted) return;
    try {
      final lien = await context.read<AppState>().api.inviter(
            email: saisie.email,
            role: saisie.role,
            memberId: saisie.memberId,
            fullName: saisie.fullName,
          );
      if (!mounted) return;
      _afficherLienInvitation(lien);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Lien de réinitialisation généré par l'admin (sans SMTP) : la
  /// personne choisit un nouveau mot de passe avec le lien (valable
  /// 24 h, usage unique). L'e-mail est saisi ici ; l'appel API a lieu
  /// dans l'écran, puis le lien est affiché à transmettre.
  Future<void> _lienReinitialisation() async {
    final emailController = TextEditingController();
    final saisie = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lien de réinitialisation'),
        content: dialogTextField(
          controller: emailController,
          label: 'E-mail du compte',
          keyboardType: TextInputType.emailAddress,
          hintText: 'Ex. membre@eglise.ci',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              Navigator.of(dialogContext).pop(email);
            },
            child: const Text('Générer le lien'),
          ),
        ],
      ),
    );
    if (saisie == null) return;
    if (!mounted) return;
    try {
      final lien =
          await context.read<AppState>().api.adminResetLink(email: saisie);
      if (!mounted) return;
      _afficherLienReinitialisation(lien);
    } catch (e) {
      if (mounted) {
        showApiError(
            context,
            'Impossible de générer le lien : ${e.toString()} '
            '(vérifiez que l’e-mail correspond à un compte existant).');
      }
    }
  }

  /// Affiche le lien de réinitialisation à copier et transmettre.
  void _afficherLienReinitialisation(String lien) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lien de réinitialisation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transmettez ce lien à la personne (WhatsApp, SMS, e-mail). '
              'Il permet de choisir un nouveau mot de passe et expire '
              'dans 24 heures (usage unique).',
            ),
            const SizedBox(height: 12),
            SelectableText(lien),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lien));
              Navigator.of(dialogContext).pop();
              showSuccess(context, 'Lien copié.');
            },
            child: const Text('Copier le lien'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  /// Affiche le lien d'invitation à copier et transmettre.
  void _afficherLienInvitation(String lien) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invitation créée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transmettez ce lien à la personne (WhatsApp, SMS, e-mail). '
              'Il expire dans 7 jours.',
            ),
            const SizedBox(height: 12),
            SelectableText(lien),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lien));
              Navigator.of(dialogContext).pop();
              showSuccess(context, 'Lien copié.');
            },
            child: const Text('Copier le lien'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  /// Module 13 — choisit un logo (PNG/JPG, max 2 Mo), le téléverse et
  /// remplit le champ URL du logo avec l'URL renvoyée. Le champ URL reste
  /// disponible en repli.
  Future<void> _choisirLogo(
      TextEditingController logoUrlController, String churchId) async {
    final api = context.read<AppState>().api;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      if (file.size > 2 * 1024 * 1024) {
        if (mounted) {
          showApiError(context, 'Le logo doit peser 2 Mo au maximum.');
        }
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) {
          showApiError(context, 'Impossible de lire ce fichier.');
        }
        return;
      }
      final url = await api.uploadLogo(
            churchId: churchId,
            base64: base64Encode(bytes),
            filename: file.name,
          );
      logoUrlController.text = url;
      if (mounted) showSuccess(context, 'Logo téléversé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _editProfil(
      ProfilEglise profil, EgliseParametres parametres) async {
    final eglise = profil.eglise;
    final nomController = TextEditingController(text: eglise.name);
    final descriptionController =
        TextEditingController(text: eglise.description ?? '');
    final couleurController =
        TextEditingController(text: eglise.couleurPrincipale ?? '');
    final deviseController =
        TextEditingController(text: eglise.devise ?? '');
    final fuseauController =
        TextEditingController(text: eglise.fuseauHoraire ?? '');
    final horairesController = TextEditingController(
      text: eglise.horairesCultes
          .map((h) =>
              '${h.jour} ${h.heure}${h.titre.isNotEmpty ? ' — ${h.titre}' : ''}')
          .join('\n'),
    );
    final addressController =
        TextEditingController(text: parametres.adresse ?? '');
    final phoneController =
        TextEditingController(text: parametres.telephone ?? '');
    final emailController =
        TextEditingController(text: parametres.email ?? '');
    final cityController = TextEditingController(text: eglise.city ?? '');
    final logoUrlController = TextEditingController(
        text: parametres.logoUrl ?? eglise.logoUrl ?? '');
    await showCreateDialog(
      context: context,
      title: 'Modifier le profil de l’église',
      saveLabel: 'Enregistrer',
      fields: [
        dialogTextField(
          controller: nomController,
          label: 'Nom de l’église',
        ),
        const Text(
          'Le code de l’église ne change jamais, ni les matricules, '
          'ni les cartes existantes.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
        dialogTextField(
            controller: logoUrlController, label: 'URL du logo'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.tonalIcon(
            onPressed: () => _choisirLogo(logoUrlController, eglise.id),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Choisir un logo (PNG/JPG, max 2 Mo)'),
          ),
        ),
        _ChoixCouleur(
          controller: couleurController,
          nomEglise: eglise.name,
        ),
        dialogTextField(controller: deviseController, label: 'Devise'),
        dialogTextField(
            controller: fuseauController, label: 'Fuseau horaire'),
        dialogTextField(
          controller: horairesController,
          label: 'Horaires des cultes',
          maxLines: 4,
        ),
        const Text(
          'Un horaire par ligne : jour, heure, puis titre.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        dialogTextField(controller: addressController, label: 'Adresse'),
        dialogTextField(
          controller: phoneController,
          label: 'Téléphone',
          keyboardType: TextInputType.phone,
        ),
        dialogTextField(
          controller: emailController,
          label: 'E-mail',
          keyboardType: TextInputType.emailAddress,
        ),
        dialogTextField(controller: cityController, label: 'Ville'),
      ],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        final horaires = <HoraireCulte>[];
        for (final line in horairesController.text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length < 2) continue;
          final jour = parts[0];
          final heure = parts[1];
          final titre = parts.length > 2
              ? parts.sublist(2).join(' ').replaceFirst(
                  RegExp(r'^[—\-]\s*'), '')
              : '';
          horaires.add(HoraireCulte(
            jour: jour,
            heure: heure,
            titre: titre,
          ));
        }
        final appState = context.read<AppState>();
        final api = appState.api;
        try {
          await api.updateProfil(
                churchId: eglise.id,
                name: nomController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                horaires: horaires,
                couleurPrincipale: couleurController.text.trim().isEmpty
                    ? null
                    : couleurController.text.trim(),
                devise: deviseController.text.trim().isEmpty
                    ? null
                    : deviseController.text.trim(),
                fuseauHoraire: fuseauController.text.trim().isEmpty
                    ? null
                    : fuseauController.text.trim(),
                address: addressController.text.trim().isEmpty
                    ? null
                    : addressController.text.trim(),
                phone: phoneController.text.trim().isEmpty
                    ? null
                    : phoneController.text.trim(),
                email: emailController.text.trim().isEmpty
                    ? null
                    : emailController.text.trim(),
                city: cityController.text.trim().isEmpty
                    ? null
                    : cityController.text.trim(),
              );
          // L'URL du logo n'entre pas dans updateProfil : elle est
          // enregistrée dans les paramètres de l'église.
          final logoUrl = logoUrlController.text.trim();
          if (logoUrl.isNotEmpty &&
              logoUrl != (parametres.logoUrl ?? eglise.logoUrl ?? '')) {
            await api.saveParametres(
                  logoUrl: logoUrl,
                );
          }
          if (mounted) showSuccess(context, 'Profil mis à jour.');
          await appState.refreshMe();
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mon église')),
      body: FutureBuilder<ProfilEglise>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final profil = snapshot.data!;
          final eglise = profil.eglise;
          final horaires = eglise.horairesCultes;
          return FutureBuilder<EgliseParametres>(
            future: _parametresFuture,
            builder: (context, paramSnapshot) {
              final parametres = paramSnapshot.data;
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ChurchAvatar(church: eglise, radius: 40),
                            const SizedBox(height: 12),
                            Text(
                              eglise.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (eglise.isMere) ...[
                              const SizedBox(height: 8),
                              const MereBadge(),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Code : ${eglise.code}'
                              '${eglise.city != null ? ' · ${eglise.city}' : ''}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (eglise.description != null &&
                                eglise.description!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                eglise.description!,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: parametres == null
                                  ? null
                                  : () => _editProfil(profil, parametres),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Modifier le profil'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SectionTitle(title: 'Paiements'),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: const Text('Paiements'),
                        subtitle: const Text(
                            'Moyens de paiement de l’église par pays'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PaiementsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SectionTitle(title: 'Horaires des cultes'),
                    if (horaires.isEmpty)
                      const EmptyState(
                        icon: Icons.schedule_outlined,
                        message:
                            'Aucun horaire de culte renseigné pour l’instant.',
                      )
                    else
                      ...horaires.map((h) => ListTile(
                            leading: const Icon(Icons.schedule_outlined),
                            title:
                                Text(h.titre.isEmpty ? 'Culte' : h.titre),
                            subtitle: Text('${h.jour} à ${h.heure}'),
                          )),
                    const SectionTitle(title: 'Contacts'),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(parametres?.telephone ??
                          'Aucun téléphone renseigné'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(
                          parametres?.email ?? 'Aucun e-mail renseigné'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(parametres?.adresse ??
                          'Aucune adresse renseignée'),
                    ),
                    if (eglise.devise != null)
                      ListTile(
                        leading: const Icon(Icons.attach_money_outlined),
                        title: Text('Devise : ${eglise.devise}'),
                        subtitle: eglise.fuseauHoraire == null
                            ? null
                            : Text(
                                'Fuseau horaire : ${eglise.fuseauHoraire}'),
                      ),
                    const SectionTitle(title: 'Pasteur principal'),
                    if (profil.pasteurPrincipal == null)
                      const EmptyState(
                        icon: Icons.person_outline,
                        message:
                            'Aucun pasteur principal renseigné pour l’instant.',
                      )
                    else
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(profil.pasteurPrincipal!),
                      ),
                    const SectionTitle(title: 'Antennes'),
                    if (profil.antennes.isEmpty)
                      const EmptyState(
                        icon: Icons.account_tree_outlined,
                        message: 'Aucune antenne rattachée pour l’instant.',
                      )
                    else
                      ...profil.antennes.map((a) => ListTile(
                            leading: ChurchAvatar(church: a, radius: 20),
                            title: Text(a.name),
                            subtitle: Text(
                                '${a.code}${a.city != null ? ' · ${a.city}' : ''}'),
                          )),
                    if (state.isAdmin) ...[
                      const SectionTitle(title: 'Demandes de liaison'),
                      FilledButton.icon(
                        onPressed: _inviter,
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Inviter une personne'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _lienReinitialisation,
                        icon: const Icon(Icons.key_outlined),
                        label: const Text('Lien de réinitialisation'),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<DemandeLiaison>>(
                        future: _demandesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const AppLoading();
                          }
                          if (snapshot.hasError) {
                            return AppError(
                              message: snapshot.error.toString(),
                              onRetry: () =>
                                  setState(_refreshDemandes),
                            );
                          }
                          final demandes = snapshot.data ?? [];
                          if (demandes.isEmpty) {
                            return const EmptyState(
                              icon: Icons.link_outlined,
                              message:
                                  'Aucune demande de liaison en attente.',
                            );
                          }
                          return Column(
                            children: demandes
                                .map((d) => Card(
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          child:
                                              Icon(Icons.person_outline),
                                        ),
                                        title: Text(d.membreNom),
                                        subtitle: Text(
                                            '${d.matricule} · ${d.userEmail}'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.check,
                                                  color: Colors.green),
                                              tooltip: 'Valider',
                                              onPressed: () =>
                                                  _decider(d, true),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close,
                                                  color: Colors.red),
                                              tooltip: 'Refuser',
                                              onPressed: () =>
                                                  _decider(d, false),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Présentation publique : ${state.church?.code ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Données saisies dans le dialogue d'invitation (avant l'appel API).
class _InviteSaisie {
  final String email;
  final String role;
  final String? memberId;
  final String? fullName;

  const _InviteSaisie({
    required this.email,
    required this.role,
    this.memberId,
    this.fullName,
  });
}

/// Choix de la couleur principale parmi des couleurs prédéfinies, avec
/// aperçu de l'avatar (audit accessibilité, cas A2/A10 : plus de champ hex
/// libre, que « or » ou « doré » ne remplissait pas). Écrit dans [controller].
class _ChoixCouleur extends StatefulWidget {
  final TextEditingController controller;
  final String nomEglise;

  const _ChoixCouleur({required this.controller, required this.nomEglise});

  @override
  State<_ChoixCouleur> createState() => _ChoixCouleurState();
}

class _ChoixCouleurState extends State<_ChoixCouleur> {
  static const _presets = ['#0B1F3A', '#8A6A12', '#0C5B40', '#1B4F72'];
  late String _choisie;
  // Couleur actuelle hors des choix prédéfinis : on la garde visible
  // plutôt que de l'écraser silencieusement par le bleu nuit.
  String? _extra;

  @override
  void initState() {
    super.initState();
    final actuel = widget.controller.text.trim().toUpperCase();
    if (actuel.isEmpty) {
      _choisie = '#0B1F3A';
      widget.controller.text = _choisie;
    } else if (_presets.contains(actuel)) {
      _choisie = actuel;
    } else if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(actuel)) {
      _choisie = actuel;
      _extra = actuel;
    } else {
      _choisie = '#0B1F3A';
    }
  }

  Color _parse(String hex) {
    final valeur = int.tryParse('FF${hex.substring(1)}', radix: 16);
    return valeur == null ? AppTheme.bleuNuit : Color(valeur);
  }

  String get _initiales {
    final mots = widget.nomEglise
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .take(2)
        .toList();
    return mots.map((mot) => mot[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final fond = _parse(_choisie);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Couleur principale',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: fond,
                child: Text(
                  _initiales,
                  style: TextStyle(
                    color: ChurchAvatar.texteSur(fond),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._presets,
                    if (_extra != null) _extra!,
                  ].map((hex) {
                    final selectionne = _choisie == hex;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _choisie = hex;
                        widget.controller.text = hex;
                      }),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _parse(hex),
                          shape: BoxShape.circle,
                          border: selectionne
                              ? Border.all(color: AppTheme.or, width: 3)
                              : null,
                        ),
                        child: selectionne
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Choisissez une couleur : vos initiales restent lisibles dessus.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
