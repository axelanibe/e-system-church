import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parametres.dart';
import '../models/profil.dart';
import '../state/app_state.dart';
import '../widgets/church_avatar.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _load();
    _parametresFuture = context.read<AppState>().api.getParametres();
  }

  Future<ProfilEglise> _load() {
    final state = context.read<AppState>();
    return state.api.getPresentation(state.church!.code);
  }

  void _refresh() {
    setState(() {
      _future = _load();
      _parametresFuture = context.read<AppState>().api.getParametres();
    });
  }

  /// Module 13 — choisit un logo (PNG/JPG, max 2 Mo), le téléverse et
  /// remplit le champ URL du logo avec l'URL renvoyée. Le champ URL reste
  /// disponible en repli.
  Future<void> _choisirLogo(
      TextEditingController logoUrlController, String churchId) async {
    final api = context.read<AppState>().api;
    try {
      final result = await FilePicker.pickFiles(
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
        dialogTextField(
            controller: couleurController, label: 'Couleur principale'),
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
      isValid: () => true,
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
