import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Tranche A — Import des listes de fidèles (admin de l'église seulement).
/// 1) Télécharger le modèle CSV (ou choisir son propre fichier CSV / XLSX).
/// 2) Correspondance des colonnes (automatique si les en-têtes suivent le
///    modèle, modifiable par menus déroulants). 3) Aperçu avant import :
///    lignes valides, erreurs, doublons. 4) Confirmation et rapport.
///
/// Lecture des fichiers : en octets seulement (`withData: true`), jamais
/// par chemin, le sélecteur web n'a pas de chemin. Le XLSX est lu côté
/// client (paquet Dart `excel`, première feuille) puis envoyé en JSON ;
/// le CSV part en texte dans le même JSON. Le serveur n'a pas de support
/// multipart. Aucun compte utilisateur n'est créé par l'import.
class ImportMembresScreen extends StatefulWidget {
  const ImportMembresScreen({super.key});

  @override
  State<ImportMembresScreen> createState() => _ImportMembresScreenState();
}

/// Champs du modèle, dans l'ordre du fichier CSV.
const Map<String, String> _champs = {
  'nom': 'Nom',
  'prenom': 'Prénom',
  'nom_complet': 'Nom complet',
  'telephone': 'Téléphone',
  'email': 'E-mail',
  'naissance': 'Naissance (AAAA-MM-JJ)',
  'sexe': 'Sexe (M ou F)',
  'departement': 'Département',
  'fonction': 'Fonction',
  'poste': 'Poste',
  'cellule': 'Cellule',
};

/// En-têtes reconnus pour la correspondance automatique (mêmes alias que le
/// serveur, sans accent, en minuscules).
const Map<String, List<String>> _alias = {
  'nom': ['nom', 'nom_de_famille', 'family_name', 'lastname', 'last_name'],
  'prenom': ['prenom', 'first_name', 'firstname'],
  'nom_complet': ['nom_complet', 'full_name', 'fullname', 'nom_prenom'],
  'telephone': ['telephone', 'tel', 'phone'],
  'email': ['email', 'e_mail', 'courriel'],
  'naissance': ['naissance', 'date_naissance', 'date_de_naissance', 'birth_date'],
  'sexe': ['sexe', 'sex', 'genre'],
  'departement': ['departement', 'department'],
  'fonction': ['fonction', 'function'],
  'poste': ['poste', 'position'],
  'cellule': ['cellule', 'cell_group', 'groupe', 'groupe_cellule'],
};

String _normaliserEntete(String h) => h
    .toLowerCase()
    .replaceAll(RegExp('[àáâä]'), 'a')
    .replaceAll(RegExp('[èéêë]'), 'e')
    .replaceAll(RegExp('[ìíîï]'), 'i')
    .replaceAll(RegExp('[òóôö]'), 'o')
    .replaceAll(RegExp('[ùúûü]'), 'u')
    .replaceAll('ç', 'c')
    .trim()
    .replaceAll(RegExp(r'[\s-]+'), '_');

String _celluleEnTexte(Data? cellule) {
  final v = cellule?.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value.text ?? '';
  if (v is DateCellValue) {
    final d = v.asDateTimeUtc();
    final mm = d.month.toString().padLeft(2, '0');
    final jj = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$jj';
  }
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) {
    return v.value == v.value.truncateToDouble()
        ? v.value.truncate().toString()
        : v.value.toString();
  }
  if (v is BoolCellValue) return v.value.toString();
  return v.toString();
}

class _ImportMembresScreenState extends State<ImportMembresScreen> {
  String? _nomFichier;
  String? _contenuCsv;
  List<Map<String, String>>? _lignesXlsx;
  List<String> _colonnes = [];
  Map<String, String> _mapping = {};
  Map<String, dynamic>? _apercu;
  Map<String, dynamic>? _rapport;
  bool _enCours = false;

  Map<String, String> get _mappingUtile => {
        for (final e in _mapping.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  Future<void> _telechargerModele() async {
    setState(() => _enCours = true);
    try {
      final bytes =
          await context.read<AppState>().api.telechargerModeleImport();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes,
                name: 'modele-import-fideles.csv', mimeType: 'text/csv'),
          ],
          subject: 'Modèle import fidèles',
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _choisirFichier() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final fichier = result.files.single;
    final bytes = fichier.bytes;
    if (bytes == null) {
      if (mounted) {
        showApiError(
            context, 'Impossible de lire ce fichier sur cet appareil.');
      }
      return;
    }
    final nom = fichier.name;
    final extension = nom.split('.').last.toLowerCase();
    try {
      if (extension == 'xlsx') {
        final lignes = _lireXlsx(bytes);
        if (lignes.isEmpty) throw 'Le fichier XLSX est vide.';
        final colonnes = lignes.first.keys.toList();
        setState(() {
          _nomFichier = nom;
          _contenuCsv = null;
          _lignesXlsx = lignes;
          _colonnes = colonnes;
          _mapping = _mappingAuto(colonnes);
          _apercu = null;
          _rapport = null;
        });
      } else {
        final texte = utf8.decode(bytes).replaceAll('\uFEFF', '');
        final premiereLigne =
            texte.split(RegExp(r'\r\n|\n|\r')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (premiereLigne.isEmpty) throw 'Le fichier CSV est vide.';
        final separateur = premiereLigne.contains(';') ? ';' : ',';
        final colonnes =
            premiereLigne.split(separateur).map((c) => c.trim()).toList();
        setState(() {
          _nomFichier = nom;
          _contenuCsv = texte;
          _lignesXlsx = null;
          _colonnes = colonnes;
          _mapping = _mappingAuto(colonnes);
          _apercu = null;
          _rapport = null;
        });
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Première feuille, première ligne non vide = en-têtes.
  List<Map<String, String>> _lireXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) throw 'Le fichier XLSX ne contient aucune feuille.';
    final lignes = excel.tables.values.first.rows;
    final debut = lignes.indexWhere(
        (r) => r.any((c) => _celluleEnTexte(c).trim().isNotEmpty));
    if (debut < 0) throw 'Le fichier XLSX est vide.';
    final entetes =
        lignes[debut].map((c) => _celluleEnTexte(c).trim()).toList();
    final sorties = <Map<String, String>>[];
    for (var i = debut + 1; i < lignes.length; i++) {
      final ligne = <String, String>{};
      var vide = true;
      for (var j = 0; j < entetes.length; j++) {
        final valeur =
            j < lignes[i].length ? _celluleEnTexte(lignes[i][j]).trim() : '';
        if (valeur.isNotEmpty) vide = false;
        if (entetes[j].isNotEmpty) ligne[entetes[j]] = valeur;
      }
      if (!vide) sorties.add(ligne);
    }
    return sorties;
  }

  Map<String, String> _mappingAuto(List<String> colonnes) {
    final mapping = <String, String>{};
    for (final colonne in colonnes) {
      final normalise = _normaliserEntete(colonne);
      var champ = '';
      for (final e in _alias.entries) {
        if (e.value.contains(normalise)) champ = e.key;
      }
      mapping[colonne] = champ;
    }
    return mapping;
  }

  Future<void> _voirApercu() async {
    setState(() => _enCours = true);
    try {
      final apercu = await context.read<AppState>().api.apercuImport(
            contenuCsv: _contenuCsv,
            lignes: _lignesXlsx,
            mapping: _mappingUtile,
            nomFichier: _nomFichier,
          );
      setState(() => _apercu = apercu);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _confirmer() async {
    final api = context.read<AppState>().api;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer l’import'),
        content: Text(
          '${_apercu?['valides'] ?? 0} membre(s) seront créés. '
          'Les doublons seront ignorés, les lignes en erreur ne seront pas créées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    if (!mounted) return;
    setState(() => _enCours = true);
    try {
      final rapport = await api.confirmerImport(
            contenuCsv: _contenuCsv,
            lignes: _lignesXlsx,
            mapping: _mappingUtile,
            nomFichier: _nomFichier,
          );
      setState(() => _rapport = rapport);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _recommencer() => setState(() {
        _nomFichier = null;
        _contenuCsv = null;
        _lignesXlsx = null;
        _colonnes = [];
        _mapping = {};
        _apercu = null;
        _rapport = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importer des fidèles')),
      body: _enCours
          ? const AppLoading()
          : _rapport != null
              ? _buildRapport()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Importez la liste de fidèles de votre église depuis un fichier CSV ou Excel (.xlsx). '
                      'Nom et prénom obligatoires, le reste est facultatif. '
                      'Le matricule est attribué automatiquement, aucun compte n’est créé. '
                      'Supprimez la ligne d’exemple du modèle avant l’import.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _telechargerModele,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Modèle CSV'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _choisirFichier,
                          icon: const Icon(Icons.upload_outlined),
                          label: const Text('Choisir un fichier'),
                        ),
                      ],
                    ),
                    if (_nomFichier != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(_nomFichier!),
                          subtitle: Text(
                            _lignesXlsx != null
                                ? '${_lignesXlsx!.length} ligne(s) lue(s) du fichier Excel'
                                : 'Fichier CSV',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Retirer le fichier',
                            onPressed: _recommencer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Correspondance des colonnes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._colonnes.map((colonne) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DropdownButtonFormField<String>(
                              initialValue: _mapping[colonne] ?? '',
                              decoration: InputDecoration(
                                labelText: colonne,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: '', child: Text('Ignorer')),
                                for (final e in _champs.entries)
                                  DropdownMenuItem(
                                      value: e.key, child: Text(e.value)),
                              ],
                              onChanged: (v) => setState(
                                  () => _mapping[colonne] = v ?? ''),
                            ),
                          )),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _voirApercu,
                        icon: const Icon(Icons.preview_outlined),
                        label: const Text('Voir l’aperçu'),
                      ),
                    ],
                    if (_apercu != null) ...[
                      const SizedBox(height: 24),
                      _buildApercu(),
                    ],
                  ],
                ),
    );
  }

  Widget _buildApercu() {
    final apercu = _apercu!;
    final lignes = (apercu['lignes'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final valides = (apercu['valides'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aperçu',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${apercu['total_lignes']} lignes')),
            Chip(label: Text('$valides à créer')),
            Chip(
                label: Text('${apercu['doublons']} doublons ignorés')),
            Chip(label: Text('${apercu['invalides']} en erreur')),
          ],
        ),
        const SizedBox(height: 8),
        ...lignes.map((l) {
          final erreurs = (l['erreurs'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          final doublon = l['doublon'] == true;
          final valide = l['valide'] == true;
          return Card(
            child: ListTile(
              leading: Icon(
                valide
                    ? Icons.check_circle_outline
                    : doublon
                        ? Icons.copy_outlined
                        : Icons.error_outline,
                color: valide
                    ? Colors.green
                    : doublon
                        ? Colors.orange
                        : Colors.red,
              ),
              title: Text((l['nom_complet'] as String?)?.isNotEmpty == true
                  ? l['nom_complet'] as String
                  : 'Ligne ${l['ligne']}'),
              subtitle: Text(
                valide
                    ? 'Sera créé'
                    : doublon
                        ? 'Doublon : ne sera pas créé'
                        : erreurs.join(' '),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: valides > 0 ? _confirmer : null,
          icon: const Icon(Icons.check_outlined),
          label: const Text('Confirmer l’import'),
        ),
        if (valides == 0)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Aucune ligne valide à importer.'),
          ),
      ],
    );
  }

  Widget _buildRapport() {
    final rapport = _rapport!;
    final erreurs = (rapport['erreurs'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final membres = (rapport['membres'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Import terminé',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${rapport['total_lignes']} lignes')),
            Chip(label: Text('${rapport['crees']} créés')),
            Chip(label: Text('${rapport['ignores']} doublons ignorés')),
            Chip(label: Text('${rapport['invalides']} en erreur')),
          ],
        ),
        const SizedBox(height: 12),
        if (membres.isNotEmpty) ...[
          const Text('Membres créés',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...membres.take(20).map((m) => ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(m['full_name'] as String? ?? ''),
                subtitle: Text(m['matricule'] as String? ?? ''),
              )),
          if (membres.length > 20)
            Text('… et ${membres.length - 20} autre(s).'),
          const SizedBox(height: 12),
        ],
        if (erreurs.isNotEmpty) ...[
          const Text('Lignes en erreur',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...erreurs.map((e) => ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text('Ligne ${e['ligne']}'),
                subtitle: Text(
                  ((e['erreurs'] as List<dynamic>? ?? [])
                          .map((x) => x.toString())
                          .join(' ')),
                ),
              )),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: const Text('Terminer'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _recommencer,
          child: const Text('Importer un autre fichier'),
        ),
      ],
    );
  }
}
