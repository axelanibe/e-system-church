import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/membres_complement.dart';
import '../models/member.dart';
import '../models/parametres.dart';
import '../models/suppression_eglise.dart';
import '../state/app_state.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'audit_screen.dart';
import 'biens_screen.dart';
import 'consultations_screen.dart';
import 'deux_fa_screen.dart';
import 'file_hors_ligne_screen.dart';
import 'langue_donnees_screen.dart';
import 'listes_configurables_screen.dart';
import 'mon_eglise_screen.dart';
import 'notifications_screen.dart';
import 'sauvegarde_screen.dart';

/// Réglages et confiance (fusion E-CF4 + E-RG1, modèle projection,
/// écran « Réglages et confiance ») : un seul parcours. Les 5 entrées
/// Confiance en tête, dans l'ordre de la projection, puis les sections
/// Réglages (Église, Paramètres de l'église, Rôles, Départements,
/// Compte, API réelle, Application). Le Journal d'audit ouvre l'écran
/// Audit, qui montre les mêmes données que l'ancien onglet Journal des
/// paramètres. Les anciens écrans Confiance et Paramètres sont
/// supprimés, jamais gardés en doublon.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _savingUrl = false;
  bool _suppressionEnCours = false;

  // Paramètres de l'église (ancien écran Paramètres, formulaire en ligne).
  final _adresseController = TextEditingController();
  final _villeController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _waveController = TextEditingController();
  final _orangeController = TextEditingController();
  final _mtnController = TextEditingController();
  final _deviseController = TextEditingController();
  final _fuseauController = TextEditingController();
  // T10 : signataires configurables, vides par défaut (règle non tranchée).
  final _signataireNominationsController = TextEditingController();
  final _signataireProcesVerbauxController = TextEditingController();
  bool _savingParametres = false;
  // Le formulaire se remplit une fois, à la première réponse du
  // serveur : sans ce garde-fou, chaque recherche tapée dans une
  // autre section reconstruirait l'écran et effacerait la saisie.
  bool _parametresCharges = false;

  // Une recherche propre à chaque liste : l'ancien écran partageait
  // un seul champ entre les onglets.
  final _rechercheRolesController = TextEditingController();
  String _queryRoles = '';
  final _rechercheDepartementsController = TextEditingController();
  String _queryDepartements = '';

  late Future<EgliseParametres> _parametresFuture;
  late Future<List<RoleEglise>> _rolesFuture;
  late Future<List<Departement>> _departementsFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
        text: context.read<AppState>().apiBaseUrl);
    final api = context.read<AppState>().api;
    _parametresFuture = api.getParametres();
    _rolesFuture = api.getRoles();
    _departementsFuture = api.getDepartements();
    _membresFuture = api.getMembers();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _adresseController.dispose();
    _villeController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _logoUrlController.dispose();
    _waveController.dispose();
    _orangeController.dispose();
    _mtnController.dispose();
    _deviseController.dispose();
    _fuseauController.dispose();
    _signataireNominationsController.dispose();
    _signataireProcesVerbauxController.dispose();
    _rechercheRolesController.dispose();
    _rechercheDepartementsController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _parametresFuture = api.getParametres();
      _rolesFuture = api.getRoles();
      _departementsFuture = api.getDepartements();
      _membresFuture = api.getMembers();
    });
  }

  bool _matches(String text, String query) =>
      query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      showApiError(
          context, 'URL invalide (doit commencer par http:// ou https://).');
      return;
    }
    setState(() => _savingUrl = true);
    await context.read<AppState>().setApiBaseUrl(url);
    if (!mounted) return;
    setState(() => _savingUrl = false);
    showSuccess(context,
        'URL de l’API enregistrée. Vous avez été déconnecté(e) : reconnectez-vous.');
  }

  /// Suppression de sa propre église TEST : aperçu, puis confirmation
  /// nommant ce qui sera supprimé, puis suppression. Admin d'église
  /// seulement, église dont le nom commence par TEST seulement. Après
  /// la suppression, la session quitte l'église supprimée.
  Future<void> _supprimerEglise() async {
    final api = context.read<AppState>().api;
    setState(() => _suppressionEnCours = true);
    SuppressionEgliseApercu apercu;
    try {
      apercu = await api.getSuppressionEgliseApercu();
    } catch (e) {
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _suppressionEnCours = false);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette église ?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${apercu.eglise.nom} (${apercu.eglise.code}) sera supprimée définitivement, avec tout ce qu’elle contient :',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in apercu.annexes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• Annexe ${a.nom} (${a.code})',
                            style: const TextStyle(fontSize: 14)),
                      ),
                    for (final ligne in apercu.lignesComptes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $ligne',
                            style: const TextStyle(fontSize: 14)),
                      ),
                    if (apercu.utilisateursSupprimes > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '• Comptes utilisateurs TEST supprimés : ${apercu.utilisateursSupprimes}',
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Membres, contributions, campagnes, attestations et transferts partent avec elle. Cette action est définitive.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Supprimer définitivement',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _suppressionEnCours = true);
    try {
      await api.executerSuppressionEglise();
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
      showApiError(context, e);
      return;
    }
    // L'église n'existe plus : la session la quitte.
    final partir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Église supprimée'),
        content: Text(
            '${apercu.eglise.nom} n’existe plus. Vous allez être déconnecté(e).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (partir == true && mounted) {
      await context.read<AppState>().logout();
    }
  }

  Future<void> _saveParametres() async {
    setState(() => _savingParametres = true);
    try {
      await context.read<AppState>().api.saveParametres(
            adresse: _opt(_adresseController),
            ville: _opt(_villeController),
            telephone: _opt(_telephoneController),
            email: _opt(_emailController),
            logoUrl: _opt(_logoUrlController),
            waveNumero: _opt(_waveController),
            orangeNumero: _opt(_orangeController),
            mtnNumero: _opt(_mtnController),
            devise: _opt(_deviseController),
            fuseauHoraire: _opt(_fuseauController),
            signataireNominations: _opt(_signataireNominationsController),
            signataireProcesVerbaux:
                _opt(_signataireProcesVerbauxController),
          );
      if (mounted) showSuccess(context, 'Paramètres enregistrés.');
      _parametresCharges = false;
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _savingParametres = false);
    }
  }

  /// Gestion des départements : créer, renommer, supprimer. Les
  /// départements restent aussi le filtre et le sélecteur en contexte
  /// (liste des membres, formulaire membre).
  Future<void> _createDepartement(List<Member> membres) async {
    final nomController = TextEditingController();
    final descriptionController = TextEditingController();
    String? responsableId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau département',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du département'),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
        dialogDropdown<String?>(
          value: responsableId,
          label: 'Responsable',
          options: {
            null: 'Aucun',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => responsableId = v,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createDepartement(
                nom: nomController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                responsableMemberId: responsableId,
              );
          if (mounted) showSuccess(context, 'Département créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Renomme un département (les membres rattachés gardent leur département,
  /// seul le libellé change).
  Future<void> _renameDepartement(Departement departement) async {
    final nomController = TextEditingController(text: departement.nom);
    await showCreateDialog(
      context: context,
      title: 'Renommer le département',
      saveLabel: 'Enregistrer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du département'),
      ],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        try {
          await context.read<AppState>().api.updateDepartement(
                departement.id,
                nom: nomController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Département renommé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteDepartement(Departement departement) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le département « ${departement.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteDepartement(departement.id);
      if (mounted) showSuccess(context, 'Département supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _carteConfiance({
    required BuildContext context,
    required IconData icone,
    required String titre,
    required String sousTitre,
    required Widget ecran,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.orClair,
          child: Icon(icone, color: AppTheme.orFonce),
        ),
        title: Text(
          titre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          sousTitre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _ouvrir(context, ecran),
      ),
    );
  }

  Widget _formulaireParametres() {
    return FutureBuilder<EgliseParametres>(
      future: _parametresFuture,
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
        final p = snapshot.data!;
        if (!_parametresCharges) {
          _adresseController.text = p.adresse ?? '';
          _villeController.text = p.ville ?? '';
          _telephoneController.text = p.telephone ?? '';
          _emailController.text = p.email ?? '';
          _logoUrlController.text = p.logoUrl ?? '';
          _waveController.text = p.waveNumero ?? '';
          _orangeController.text = p.orangeNumero ?? '';
          _mtnController.text = p.mtnNumero ?? '';
          _deviseController.text = p.devise ?? '';
          _fuseauController.text = p.fuseauHoraire ?? '';
          _signataireNominationsController.text =
              p.signataireNominations ?? '';
          _signataireProcesVerbauxController.text =
              p.signataireProcesVerbaux ?? '';
          _parametresCharges = true;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle(title: 'Coordonnées'),
            dialogTextField(controller: _adresseController, label: 'Adresse'),
            dialogTextField(controller: _villeController, label: 'Ville'),
            dialogTextField(
              controller: _telephoneController,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _emailController,
              label: 'E-mail',
              keyboardType: TextInputType.emailAddress,
            ),
            dialogTextField(controller: _logoUrlController, label: 'URL du logo'),
            const SectionTitle(title: 'Paiements mobiles'),
            dialogTextField(
              controller: _waveController,
              label: 'Numéro Wave',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _orangeController,
              label: 'Numéro Orange Money',
              keyboardType: TextInputType.phone,
            ),
            dialogTextField(
              controller: _mtnController,
              label: 'Numéro MTN Mobile Money',
              keyboardType: TextInputType.phone,
            ),
            const SectionTitle(title: 'Préférences'),
            dialogTextField(controller: _deviseController, label: 'Devise'),
            dialogTextField(
                controller: _fuseauController, label: 'Fuseau horaire'),
            const SectionTitle(title: 'Gouvernance'),
            const Text(
              'Qui signe les nominations et les procès-verbaux. À compléter par l’église.',
              style: TextStyle(fontSize: 12),
            ),
            dialogTextField(
              controller: _signataireNominationsController,
              label: 'Signataire des nominations',
            ),
            dialogTextField(
              controller: _signataireProcesVerbauxController,
              label: 'Signataire des procès-verbaux',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _savingParametres ? null : _saveParametres,
              child: const Text('Enregistrer les paramètres'),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionRoles() {
    return Column(
      children: [
        searchField(
          controller: _rechercheRolesController,
          onChanged: (v) => setState(() => _queryRoles = v.trim()),
          label: 'Rechercher un utilisateur',
        ),
        FutureBuilder<List<RoleEglise>>(
          future: _rolesFuture,
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
            final items = snapshot.data!
                .where((r) =>
                    _matches(r.fullName ?? '', _queryRoles) ||
                    _matches(r.email ?? '', _queryRoles))
                .toList();
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.manage_accounts_outlined,
                message: 'Aucun utilisateur dans cette église pour l’instant.',
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final r = items[index];
                // Nom et rôle sur deux lignes : le menu déroulant en
                // trailing d'un ListTile débordait à 390 px, la largeur
                // du menu dépassant la place restante dans la tuile.
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.fullName ?? 'Utilisateur sans nom',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(r.email ?? ''),
                            const SizedBox(height: 4),
                            DropdownButton<String>(
                              value: r.role,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'admin_eglise',
                                  child: Text('Admin d’église'),
                                ),
                                DropdownMenuItem(
                                  value: 'tresorier',
                                  child: Text('Trésorier'),
                                ),
                                DropdownMenuItem(
                                  value: 'responsable_culte',
                                  child: Text('Responsable de culte'),
                                ),
                                DropdownMenuItem(
                                    value: 'membre',
                                    child: Text('Membre')),
                              ],
                              onChanged: (value) async {
                                if (value == null || value == r.role) {
                                  return;
                                }
                                try {
                                  await context
                                      .read<AppState>()
                                      .api
                                      .setRole(
                                        r.userId,
                                        value,
                                      );
                                  if (context.mounted) {
                                    showSuccess(context, 'Rôle mis à jour.');
                                  }
                                  _refresh();
                                } catch (e) {
                                  if (context.mounted) {
                                    showApiError(context, e);
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _sectionDepartements() {
    return FutureBuilder<MemberPage>(
      future: _membresFuture,
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
        final membres = snapshot.data!.membres;
        final noms = {for (final m in membres) m.id: m.fullName};
        return Column(
          children: [
            searchField(
              controller: _rechercheDepartementsController,
              onChanged: (v) =>
                  setState(() => _queryDepartements = v.trim()),
              label: 'Rechercher un département',
            ),
            FutureBuilder<List<Departement>>(
              future: _departementsFuture,
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
                final items = snapshot.data!
                    .where((d) => _matches(d.nom, _queryDepartements))
                    .toList();
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.group_work_outlined,
                    message: snapshot.data!.isEmpty
                        ? 'Aucun département pour l’instant.'
                        : 'Aucun département ne correspond à la recherche.',
                    actionLabel: 'Créer un département',
                    onAction: () => _createDepartement(membres),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final d = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.group_work_outlined),
                      ),
                      title: Text(d.nom),
                      subtitle: Text(
                        '${d.responsableMemberId != null ? 'Responsable : ${noms[d.responsableMemberId] ?? '—'}' : 'Sans responsable'}'
                        '${d.description != null ? ' · ${d.description}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Renommer',
                            onPressed: () => _renameDepartement(d),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _deleteDepartement(d),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final estEgliseTest =
        state.isAdmin && (state.church?.name.startsWith('TEST') ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages et confiance')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: 'Confiance'),
                  _carteConfiance(
                    context: context,
                    icone: Icons.backup_outlined,
                    titre: 'Sauvegardes',
                    sousTitre:
                        'Sauvegarde chiffrée de l’église, restauration testée.',
                    ecran: const SauvegardeScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.cloud_off_outlined,
                    titre: 'File hors ligne',
                    sousTitre:
                        'Pointages et saisies en attente, rejoués à la reconnexion.',
                    ecran: const FileHorsLigneScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.notifications_outlined,
                    titre: 'Notifications',
                    sousTitre: 'Push et SMS, boîte d’envoi et paramètres.',
                    ecran: const NotificationsScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.phonelink_lock_outlined,
                    titre: 'Double authentification',
                    sousTitre:
                        'Code à 6 chiffres pour Pasteur, Trésorier et Admin.',
                    ecran: const DeuxFaScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.fact_check_outlined,
                    titre: 'Journal d’audit',
                    sousTitre:
                        'Historique immuable, chaîne vérifiée, lectures sensibles.',
                    ecran: const AuditScreen(),
                  ),
                  const SectionTitle(title: 'Église'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.church_outlined),
                            title: const Text('Mon église'),
                            subtitle: const Text(
                                'Logo, présentation, horaires des cultes, pasteur et antennes.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MonEgliseScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.home_work_outlined),
                            title: const Text('Biens de l’église'),
                            subtitle: const Text(
                                'Salles, réservations, matériel et maintenance.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const BiensScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.list_outlined),
                            title: const Text('Listes configurables'),
                            subtitle: const Text(
                                'Rôles, catégories, statuts, départements, seuils et dîme suggérée.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ListesConfigurablesScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.visibility_outlined),
                            title: const Text('Consultations sensibles'),
                            subtitle: const Text(
                                'Qui a consulté les données sensibles.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ConsultationsScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SectionTitle(title: 'Paramètres de l’église'),
                  _formulaireParametres(),
                  const SectionTitle(title: 'Rôles'),
                  _sectionRoles(),
                  const SectionTitle(title: 'Départements'),
                  _sectionDepartements(),
                  const SectionTitle(title: 'Compte'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Changer mon mot de passe'),
                            subtitle: const Text(
                                'Vérifie l’ancien mot de passe. Les autres sessions sont déconnectées.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showChangePasswordDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (estEgliseTest) ...[
                    const SectionTitle(title: 'Supprimer cette église'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_forever_outlined,
                                  color:
                                      Theme.of(context).colorScheme.error),
                              title: Text(
                                'Supprimer cette église',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error),
                              ),
                              subtitle: const Text(
                                  'Supprime définitivement votre église TEST, ses annexes et tout ce qu’elles contiennent (membres, contributions, campagnes, attestations, transferts). L’aperçu s’affiche avant toute suppression.'),
                              trailing: _suppressionEnCours
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: _suppressionEnCours
                                  ? null
                                  : _supprimerEglise,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SectionTitle(title: 'API réelle'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'URL de l’API',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _savingUrl ? null : _saveUrl,
                            child: const Text('Enregistrer l’URL'),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Changer l’URL déconnecte la session en cours : reconnectez-vous ensuite avec votre compte réel.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SectionTitle(title: 'Application'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.info_outline),
                            title: Text(AppConfig.appName),
                            subtitle:
                                Text('Version ${AppConfig.appVersion}'),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.language_outlined),
                            title: const Text('Langue et données'),
                            subtitle: const Text(
                                'Langue des nouveaux écrans, mode économique.'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const LangueDonneesScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.logout),
                            title: const Text('Se déconnecter'),
                            onTap: () async {
                              await context.read<AppState>().logout();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
