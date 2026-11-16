import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../models/paiements.dart';
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
import 'langue_donnees_screen.dart';
import 'listes_configurables_screen.dart';
import 'sauvegarde_screen.dart';

/// Réglages et confidentialité (fusion E-CF4 + E-RG1, modèle projection,
/// écran « Réglages et confidentialité ») : un seul parcours. Les 3 entrées
/// Confiance en tête, dans l'ordre de la maquette (Double authentification,
/// Journal d'audit, Mot de passe), puis les sections Réglages (Église,
/// Paramètres de l'église, Clés marchandes et API, Rôles, API réelle,
/// Application). Les clés marchandes (Wave, Orange Money, MTN) et la clé
/// du fournisseur de notifications se saisissent uniquement ici, masquées
/// et chiffrées, jamais affichées en clair ni pré-remplies, vidées après
/// enregistrement. Le Journal d'audit ouvre l'écran Audit, qui montre les
/// mêmes données que l'ancien onglet Journal des paramètres. Les anciens
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

  late Future<EgliseParametres> _parametresFuture;
  late Future<List<RoleEglise>> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
        text: context.read<AppState>().apiBaseUrl);
    final api = context.read<AppState>().api;
    _parametresFuture = api.getParametres();
    _rolesFuture = api.getRoles();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _adresseController.dispose();
    _villeController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _logoUrlController.dispose();
    _deviseController.dispose();
    _fuseauController.dispose();
    _signataireNominationsController.dispose();
    _signataireProcesVerbauxController.dispose();
    _rechercheRolesController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _parametresFuture = api.getParametres();
      _rolesFuture = api.getRoles();
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
    final confirmationController = TextEditingController();
    var nomConfirme = false;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Supprimer cette église ?', style: TextStyle(fontSize: 17)),
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
              const SizedBox(height: 12),
              TextField(
                controller: confirmationController,
                decoration: const InputDecoration(
                  labelText: 'Tapez le nom de l’église pour confirmer',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setDialogState(
                  () => nomConfirme = v.trim() == apercu.eglise.nom,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler', style: TextStyle(fontSize: 13.5)),
          ),
          TextButton(
            onPressed: nomConfirme
                ? () => Navigator.of(ctx).pop(true)
                : null,
            child: Text(
              'Supprimer définitivement',
              style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                  fontSize: 13.5),
            ),
          ),
        ],
      ),
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
        title: const Text('Église supprimée', style: TextStyle(fontSize: 17)),
        content: Text(
            '${apercu.eglise.nom} n’existe plus. Vous allez être déconnecté(e).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK', style: TextStyle(fontSize: 13.5)),
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

  Widget _carteConfiance({
    required BuildContext context,
    required IconData icone,
    required String titre,
    required String sousTitre,
    Widget? ecran,
    VoidCallback? onTap,
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
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        subtitle: Text(
          sousTitre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? (ecran == null ? null : () => _ouvrir(context, ecran)),
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
            const SectionTitle(title: 'Préférences'),
            dialogTextField(controller: _deviseController, label: 'Devise'),
            dialogTextField(
                controller: _fuseauController, label: 'Fuseau horaire'),
            const SectionTitle(title: 'Gouvernance'),
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
              child: const Text('Enregistrer les paramètres', style: TextStyle(fontSize: 13.5)),
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
                message: 'Aucun utilisateur.',
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
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5),
                            ),
                            Text(r.email ?? '',
                                style: const TextStyle(fontSize: 11.5)),
                            const SizedBox(height: 4),
                            DropdownButton<String>(
                              value: r.role,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'admin_eglise',
                                  child: Text('Admin d’église', style: TextStyle(fontSize: 13.5)),
                                ),
                                DropdownMenuItem(
                                  value: 'tresorier',
                                  child: Text('Trésorier', style: TextStyle(fontSize: 13.5)),
                                ),
                                DropdownMenuItem(
                                  value: 'responsable_culte',
                                  child: Text('Responsable de culte', style: TextStyle(fontSize: 13.5)),
                                ),
                                DropdownMenuItem(
                                    value: 'membre',
                                    child: Text('Membre', style: TextStyle(fontSize: 13.5))),
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final estEgliseTest =
        state.isAdmin && (state.church?.name.startsWith('TEST') ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages et confidentialité')),
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
                    icone: Icons.phonelink_lock_outlined,
                    titre: 'Double authentification',
                    sousTitre:
                        'Un code supplémentaire protège les comptes sensibles.',
                    ecran: const DeuxFaScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.fact_check_outlined,
                    titre: 'Journal d’audit',
                    sousTitre:
                        'Actions sensibles tracées, avec auteur et horodatage.',
                    ecran: const AuditScreen(),
                  ),
                  _carteConfiance(
                    context: context,
                    icone: Icons.lock_outline,
                    titre: 'Mot de passe',
                    sousTitre:
                        'Vérifie l’ancien mot de passe. Les autres sessions sont déconnectées.',
                    onTap: () => showChangePasswordDialog(context),
                  ),
                  const SectionTitle(title: 'Église'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.home_work_outlined),
                            title: const Text('Biens de l’église', style: TextStyle(fontSize: 13.5)),
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
                            title: const Text('Listes configurables', style: TextStyle(fontSize: 13.5)),
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
                            title: const Text('Consultations sensibles', style: TextStyle(fontSize: 13.5)),
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
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.backup_outlined),
                            title: const Text('Sauvegardes', style: TextStyle(fontSize: 13.5)),
                            subtitle: const Text(
                                'Dernière sauvegarde affichée ici, avec son état.',
                                style: TextStyle(fontSize: 11.5)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SauvegardeScreen(),
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
                  const SectionTitle(title: 'Clés marchandes et API'),
                  if (state.church != null)
                    _ClesMarchandesSection(churchId: state.church!.id),
                  const SectionTitle(title: 'Rôles'),
                  _sectionRoles(),
                  if (estEgliseTest) ...[
                    const SectionTitle(title: 'Supprimer cette église', taille: 12),
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
                                        .error,
                                    fontSize: 13.5),
                              ),
                              subtitle: const Text(
                                  'Supprime définitivement votre église TEST, ses annexes et tout ce qu’elles contiennent. L’aperçu s’affiche avant toute suppression.',
                                  style: TextStyle(fontSize: 11.5)),
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
                            child: const Text('Enregistrer l’URL', style: TextStyle(fontSize: 13.5)),
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
                            title: Text(AppConfig.appName,
                                style: TextStyle(fontSize: 13.5)),
                            subtitle:
                                Text('Version ${AppConfig.appVersion}',
                                    style: TextStyle(fontSize: 11.5)),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.language_outlined),
                            title: const Text('Langue et données', style: TextStyle(fontSize: 13.5)),
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

/// Clés marchandes et API (maquette, écran 14) : le seul endroit où
/// se saisissent les clés Wave, Orange Money, MTN et celle du
/// fournisseur de notifications. Les champs sont masqués à la saisie,
/// jamais pré-remplis (l'API ne renvoie aucune valeur), et vidés après
/// enregistrement. L'état affiché est seulement « •••••••• —
/// chiffrée, jamais affichée en clair » ou « Aucune clé enregistrée ».
class _ClesMarchandesSection extends StatefulWidget {
  final String churchId;

  const _ClesMarchandesSection({required this.churchId});

  @override
  State<_ClesMarchandesSection> createState() =>
      _ClesMarchandesSectionState();
}

class _ClesMarchandesSectionState extends State<_ClesMarchandesSection> {
  static const _codesMarchands = {'wave', 'orange_money', 'mtn_momo'};

  List<FournisseurPaiement> _fournisseurs = [];
  List<EglisePaiement> _configs = [];
  ParametresConfiance? _confiance;
  EgliseParametres? _parametres;
  bool _chargement = true;
  bool _enregistrement = false;

  /// Contrôleurs par fournisseur puis par champ, créés après le
  /// chargement du catalogue (les champs viennent du serveur).
  final Map<String, Map<String, TextEditingController>> _cles = {};

  /// Numéros marchands, un champ par fournisseur : jamais pré-remplis
  /// depuis le serveur, l'état affiché est seulement « Aucun numéro
  /// enregistré » ou le numéro enregistré. Enregistrés par le seul
  /// bouton « Enregistrer les clés ».
  final Map<String, TextEditingController> _numeros = {};
  final _cleNotificationController = TextEditingController();

  /// Libellé du numéro marchand par code fournisseur.
  static const _labelsNumero = {
    'wave': 'Wave',
    'orange_money': 'Orange Money',
    'mtn_momo': 'MTN Mobile Money',
  };

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final parChamp in _cles.values) {
      for (final c in parChamp.values) {
        c.dispose();
      }
    }
    for (final c in _numeros.values) {
      c.dispose();
    }
    _cleNotificationController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final api = context.read<AppState>().api;
      final fournisseurs = await api.getFournisseursPaiement();
      final configs = await api.getMesPaiements(widget.churchId);
      final confiance = await api.getParametresConfiance();
      final parametres = await api.getParametres();
      if (!mounted) return;
      setState(() {
        _fournisseurs = fournisseurs
            .where((f) => _codesMarchands.contains(f.code))
            .toList();
        _configs = configs;
        _confiance = confiance;
        _parametres = parametres;
        for (final f in _fournisseurs) {
          _cles[f.code] ??= {
            for (final champ in f.champsRequis)
              champ.nom: TextEditingController(),
          };
          _numeros[f.code] ??= TextEditingController();
        }
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      showApiError(context, e);
    }
  }

  EglisePaiement? _configPour(String code) =>
      _configs.where((c) => c.fournisseurCode == code).firstOrNull;

  /// Numéro marchand enregistré pour ce fournisseur, ou null.
  String? _numeroPour(String code) => switch (code) {
        'wave' => _parametres?.waveNumero,
        'orange_money' => _parametres?.orangeNumero,
        'mtn_momo' => _parametres?.mtnNumero,
        _ => null,
      };

  void _vider() {
    for (final parChamp in _cles.values) {
      for (final c in parChamp.values) {
        c.clear();
      }
    }
    for (final c in _numeros.values) {
      c.clear();
    }
    _cleNotificationController.clear();
  }

  Future<void> _enregistrer() async {
    final api = context.read<AppState>().api;
    setState(() => _enregistrement = true);
    try {
      var nbEnregistres = 0;
      for (final f in _fournisseurs) {
        final parChamp = _cles[f.code] ?? {};
        final secrets = <Map<String, String>>[];
        for (final champ in f.champsRequis) {
          final valeur = parChamp[champ.nom]?.text.trim() ?? '';
          if (valeur.isNotEmpty) {
            secrets.add({'nom_champ': champ.nom, 'valeur': valeur});
          }
        }
        if (secrets.isEmpty) continue;
        final config = _configPour(f.code);
        if (config == null) {
          final manquants = f.champsRequis
              .where((c) =>
                  !c.optionnel &&
                  !secrets.any((s) => s['nom_champ'] == c.nom))
              .map((c) => c.label)
              .toList();
          if (manquants.isNotEmpty) {
            if (!mounted) return;
            showApiError(context,
                'Champs obligatoires manquants pour ${f.nom} : ${manquants.join(', ')}.');
            return;
          }
        }
        await api.configurerPaiement(
          churchId: widget.churchId,
          fournisseurCode: f.code,
          pays: config?.pays ?? f.pays.first,
          secrets: secrets,
        );
        nbEnregistres++;
      }
      final cleNotification = _cleNotificationController.text.trim();
      if (cleNotification.isNotEmpty) {
        await api.patchParametresConfiance(
            notificationCle: cleNotification);
        nbEnregistres++;
      }
      // Numéros marchands : seuls les champs remplis partent, par le
      // même bouton « Enregistrer les clés ».
      final numeros = <String, String>{
        for (final f in _fournisseurs)
          if ((_numeros[f.code]?.text.trim() ?? '').isNotEmpty)
            f.code: _numeros[f.code]!.text.trim(),
      };
      if (numeros.isNotEmpty) {
        await api.saveParametres(
          waveNumero: numeros['wave'],
          orangeNumero: numeros['orange_money'],
          mtnNumero: numeros['mtn_momo'],
        );
        nbEnregistres++;
      }
      if (nbEnregistres == 0) {
        if (!mounted) return;
        showApiError(context, 'Saisissez au moins un numéro ou une clé.');
        return;
      }
      _vider();
      if (mounted) {
        showSuccess(
            context, 'Clés enregistrées. Elles ne sont jamais affichées.');
      }
      await _charger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const AppLoading();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tout ce qui se rapporte à la sécurité se saisit ici, dans Réglages — et nulle part ailleurs. Les clés restent chiffrées et masquées : elles ne s’affichent jamais en clair.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            for (final f in _fournisseurs) ...[
              Text(
                f.nom,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final numero = _numeroPour(f.code);
                  final sansNumero =
                      numero == null || numero.isEmpty;
                  // « Aucun numéro enregistré » est un état vide
                  // atténué (gris), pas une valeur.
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_labelsNumero[f.code] ?? f.nom} — '
                              'numéro marchand : ',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        TextSpan(
                          text: sansNumero
                              ? 'Aucun numéro enregistré'
                              : numero,
                          style: sansNumero
                              ? TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12.5,
                                )
                              : const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _numeros[f.code]!,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Numéro ${_labelsNumero[f.code] ?? f.nom}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final config = _configPour(f.code);
                  if (config == null) {
                    return const Text('Aucune clé enregistrée.', style: TextStyle(fontSize: 12.5));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          '•••••••• — chiffrée, jamais affichée en clair.',
                          style: TextStyle(fontSize: 12.5)),
                      for (final champ in config.champs)
                        Text(
                          '${champ.label} : ${champ.configure ? 'configuré' : 'non configuré'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              for (final champ in f.champsRequis) ...[
                TextField(
                  controller: _cles[f.code]![champ.nom]!,
                  obscureText: champ.secret,
                  enableSuggestions: !champ.secret,
                  autocorrect: !champ.secret,
                  decoration: InputDecoration(
                    labelText: champ.optionnel
                        ? '${champ.label} (facultatif)'
                        : champ.label,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
            const Text(
              'Fournisseur de notifications',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
            ),
            const SizedBox(height: 4),
            Text(
              _confiance?.notificationsConfigurees == true
                  ? '•••••••• — chiffrée, jamais affichée en clair.'
                  : 'Aucune clé enregistrée.',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cleNotificationController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Clé du fournisseur de notifications',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _enregistrement ? null : _enregistrer,
              child: const Text('Enregistrer les clés', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }
}
