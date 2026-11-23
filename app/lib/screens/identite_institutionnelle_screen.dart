import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/identite.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Identité institutionnelle (phase 2, `GET` / `PATCH /identite`) :
/// l'église mère définit son identité, ses branches en héritent.
/// Deux sections seulement : informations de l'église, puis logo et
/// identité visuelle. Les champs JSONB (infos légales, couleurs au-delà
/// de la principale, paramètres des documents) ne sont pas éditables
/// dans cette phase : ils ne sont ni affichés ni envoyés.
class IdentiteInstitutionnelleScreen extends StatefulWidget {
  const IdentiteInstitutionnelleScreen({super.key});

  @override
  State<IdentiteInstitutionnelleScreen> createState() =>
      _IdentiteInstitutionnelleScreenState();
}

class _IdentiteInstitutionnelleScreenState
    extends State<IdentiteInstitutionnelleScreen> {
  late Future<IdentiteInstitutionnelle> _future;
  IdentiteInstitutionnelle? _identite;
  final Map<String, TextEditingController> _controleurs = {};
  String _statut = 'brouillon';
  bool _enregistrement = false;

  /// Clés JSON des champs éditables, dans l'ordre d'affichage.
  // Tranche Formulaires (21 nov. 2026) : chaque champ porte son aide
  // concrète (exemple plutôt que règle).
  static const _champs = [
    ('nom_officiel', 'Nom officiel', 'Ex. Église Évangélique de Cocody'),
    ('sigle', 'Sigle', 'Ex. EEC'),
    ('slogan', 'Slogan', 'Ex. L’église sans frontière'),
    ('adresse', 'Adresse', 'Ex. Cocody, rue des Jardins'),
    ('ville', 'Ville', 'Ex. Abidjan'),
    ('pays', 'Pays', 'Ex. Côte d’Ivoire'),
    ('telephone', 'Téléphone', 'Ex. 07 07 07 07 07'),
    ('email', 'E-mail', 'Ex. contact@eglise.ci'),
    ('site_web', 'Site web', 'Ex. https://www.moneglise.ci'),
    (
      'numero_enregistrement',
      'Numéro d’enregistrement',
      'Numéro officiel de l’église, si elle en a un.',
    ),
    (
      'ncc',
      'Numéro de compte contribuable (NCC)',
      'Numéro délivré par la DGI. Il sert au dépôt SYCEBNL sur e-impots.',
    ),
    ('devise', 'Devise', 'Ex. FCFA'),
    ('fuseau_horaire', 'Fuseau horaire', 'Ex. Africa/Abidjan'),
    (
      'description',
      'Description',
      'Ce que les visiteurs doivent savoir.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in _controleurs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _charger() {
    _future = context.read<AppState>().api.getIdentite().then((identite) {
      _remplir(identite);
      return identite;
    });
  }

  void _remplir(IdentiteInstitutionnelle identite) {
    _identite = identite;
    _statut = identite.statut ?? 'brouillon';
    for (final c in _controleurs.values) {
      c.dispose();
    }
    _controleurs.clear();
    for (final (cle, _, _) in _champs) {
      _controleurs[cle] =
          TextEditingController(text: _valeur(identite, cle) ?? '');
    }
    _controleurs['couleur_principale'] =
        TextEditingController(text: identite.couleurPrincipale ?? '');
  }

  static String? _valeur(IdentiteInstitutionnelle identite, String cle) {
    switch (cle) {
      case 'nom_officiel':
        return identite.nomOfficiel;
      case 'sigle':
        return identite.sigle;
      case 'slogan':
        return identite.slogan;
      case 'adresse':
        return identite.adresse;
      case 'ville':
        return identite.ville;
      case 'pays':
        return identite.pays;
      case 'telephone':
        return identite.telephone;
      case 'email':
        return identite.email;
      case 'site_web':
        return identite.siteWeb;
      case 'numero_enregistrement':
        return identite.numeroEnregistrement;
      case 'ncc':
        return identite.ncc;
      case 'devise':
        return identite.devise;
      case 'fuseau_horaire':
        return identite.fuseauHoraire;
      case 'description':
        return identite.description;
      default:
        return null;
    }
  }

  /// Vrai quand l'utilisateur peut modifier : mère et admin d'église.
  /// Une annexe est toujours en lecture seule, même quand sa mère n'a
  /// pas encore publié son identité (`heritee` faux) : `PATCH /identite`
  /// est réservé à l'admin de la mère (403 sinon). Un trésorier ou un
  /// responsable de culte lit seulement.
  bool get _modifiable {
    final identite = _identite;
    if (identite == null ||
        identite.heritee ||
        identite.estAnnexe) {
      return false;
    }
    return context.read<AppState>().isAdmin;
  }

  Future<void> _enregistrer() async {
    final identite = _identite;
    if (identite == null) return;
    final champs = <String, dynamic>{};
    for (final (cle, _, _) in _champs) {
      final saisi = _controleurs[cle]!.text.trim();
      if (saisi != (_valeur(identite, cle) ?? '')) {
        champs[cle] = saisi;
      }
    }
    final couleur = _controleurs['couleur_principale']!.text.trim();
    if (couleur != (identite.couleurPrincipale ?? '')) {
      champs['couleur_principale'] = couleur;
    }
    if (_statut != identite.statut) champs['statut'] = _statut;
    if (champs.isEmpty) {
      showSuccess(context, 'Aucune modification à enregistrer.');
      return;
    }
    setState(() => _enregistrement = true);
    try {
      await context.read<AppState>().api.patchIdentite(champs);
      if (!mounted) return;
      showSuccess(context, 'Identité enregistrée.');
      setState(_charger);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  /// Logo : même flux que « Mon église » (sélecteur de fichier, image,
  /// 2 Mo max, envoi base64 par `uploadLogo`), puis l'URL renvoyée est
  /// enregistrée par `PATCH /identite` et l'identité est rechargée.
  Future<void> _changerLogo() async {
    final identite = _identite;
    if (identite == null) return;
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
        churchId: identite.egliseId,
        base64: base64Encode(bytes),
        filename: file.name,
      );
      await api.patchIdentite({'logo_url': url});
      if (!mounted) return;
      showSuccess(context, 'Logo téléversé.');
      setState(_charger);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  static Color? _couleurHex(String? hex) {
    final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex ?? '');
    if (m == null) return null;
    return Color(int.parse('FF${m.group(1)}', radix: 16));
  }

  Widget _champ(String cle, String label, bool modifiable,
      {int maxLines = 1, TextInputType? clavier, String? aide}) {
    return TextField(
      key: Key('champ_$cle'),
      controller: _controleurs[cle],
      enabled: modifiable,
      maxLines: maxLines,
      keyboardType: clavier,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        helperText: aide,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identité institutionnelle')),
      body: FutureBuilder<IdentiteInstitutionnelle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Impossible de charger l’identité.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(_charger),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 48),
                    ),
                    child: const Text('Réessayer',
                        style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
          }
          final identite = snapshot.data!;
          final modifiable = _modifiable;
          final couleur =
              _couleurHex(identite.couleurPrincipale) ?? AppTheme.or;
          final nom = (identite.nomOfficiel ?? identite.egliseNom).trim();
          final initiale = nom.isEmpty ? 'E' : nom[0].toUpperCase();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (identite.estAnnexe && identite.mere != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.orClair,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.or),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_outlined,
                            color: AppTheme.orFonce),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            identite.heritee
                                ? 'Identité héritée de votre église mère '
                                    '${identite.mere!.nom}'
                                : 'Votre église mère ${identite.mere!.nom} '
                                    'n’a pas encore publié son identité. '
                                    'Vos valeurs actuelles restent affichées, '
                                    'en lecture seule.',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!identite.estAnnexe) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Statut de diffusion',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'brouillon', label: Text('Brouillon')),
                      ButtonSegment(value: 'publié', label: Text('Publié')),
                    ],
                    selected: {_statut},
                    onSelectionChanged: modifiable
                        ? (selection) =>
                            setState(() => _statut = selection.first)
                        : null,
                    style: ButtonStyle(
                      minimumSize: WidgetStateProperty.all(
                          const Size(double.infinity, 48)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Seule l’identité publiée est diffusée aux branches.',
                    style: TextStyle(fontSize: 16),
                  ),
                  if (!identite.heritee && _statut == 'brouillon') ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Non publiée : vos branches voient encore leurs '
                      'valeurs actuelles.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                _section(
                  'Informations de l’église',
                  [
                    for (final (cle, label, aide) in _champs)
                      _champ(
                        cle,
                        label,
                        modifiable,
                        aide: aide,
                        maxLines: cle == 'description' ? 3 : 1,
                        clavier: cle == 'email'
                            ? TextInputType.emailAddress
                            : cle == 'telephone'
                                ? TextInputType.phone
                                : cle == 'site_web'
                                    ? TextInputType.url
                                    : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  'Logo et identité visuelle',
                  [
                    Row(
                      children: [
                        if (identite.logoUrl != null &&
                            identite.logoUrl!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: Image.network(
                              identite.logoUrl!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarInitiale(initiale),
                            ),
                          )
                        else
                          _avatarInitiale(initiale),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: couleur,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppTheme.bordure),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  identite.couleurPrincipale ??
                                      'Couleur non définie',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _champ('couleur_principale', 'Couleur principale',
                        modifiable,
                        aide: 'Code hexadécimal, ex. #2A0059.'),
                    if (modifiable) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _changerLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text(
                          'Changer le logo (PNG/JPG, max 2 Mo)',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                  ],
                ),
                if (modifiable) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _enregistrement ? null : _enregistrer,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: Text(
                      _enregistrement ? 'Enregistrement…' : 'Enregistrer',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _avatarInitiale(String initiale) => CircleAvatar(
        radius: 36,
        backgroundColor: AppTheme.violetProfond,
        child: Text(
          initiale,
          style: const TextStyle(fontSize: 28, color: Colors.white),
        ),
      );

  Widget _section(String titre, List<Widget> enfants) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titre,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < enfants.length; i++) ...[
              enfants[i],
              if (i < enfants.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
