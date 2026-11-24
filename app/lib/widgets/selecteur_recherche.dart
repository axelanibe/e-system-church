import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Une option du sélecteur avec recherche : valeur, libellé affiché,
/// détail affiché en plus petit (ex. le matricule d'un membre).
class OptionSelecteur<T> {
  const OptionSelecteur({
    required this.valeur,
    required this.libelle,
    this.detail,
  });

  final T valeur;
  final String libelle;
  final String? detail;
}

/// Libellé + aide concrète d'un champ, au-dessus du champ
/// (inspiration e-justice.ci : l'aide est intégrée au champ, pas
/// reléguée dans une FAQ — exemple plutôt que règle).
Widget etiquetteChamp({
  required String label,
  String? aide,
  bool obligatoire = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        obligatoire ? '$label *' : label,
        // Le libellé tient sur une seule ligne : dans un dialogue
        // étroit, il s'enroulait lettre par lettre à la verticale
        // (« Choisir dans la base », dialogue Modifier l'activité).
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.violetProfond,
        ),
      ),
      if (aide != null) ...[
        const SizedBox(height: 2),
        Text(
          aide,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppTheme.texteSecondaire,
          ),
        ),
      ],
      const SizedBox(height: 6),
    ],
  );
}

/// Sélecteur avec recherche en deux temps (Tranche Formulaires P0,
/// 21/11/2026), reproduction du composant observé en direct sur
/// e-justice.ci — couleurs AppTheme (violet profond / or), pas celles
/// du portail :
///
/// 1. Au repos : un champ fermé (libellé ou choix affiché, chevron bas).
/// 2. Un clic ouvre un panneau qui se superpose au contenu ; en haut
///    du panneau, une barre de recherche séparée.
/// 3. Filtrage par sous-chaîne insensible à la casse (pas seulement
///    préfixe) : « bou » retrouve BOUAKÉ comme DABOU.
/// 4. Un clic sur un choix ferme le panneau et affiche le choix.
/// 5. Après choix : croix d'effacement (×) à droite du champ +
///    bouton « Effacer la sélection » sous le champ.
///
/// Pour les longues listes seulement (membres, églises,
/// départements) : 2 à 7 choix se font par boutons ou radios.
class SelecteurRecherche<T> extends StatefulWidget {
  const SelecteurRecherche({
    super.key,
    required this.options,
    required this.valeur,
    required this.onChanged,
    required this.label,
    this.aide,
    this.placeholder = 'Sélectionnez',
    this.obligatoire = false,
    this.texteVide = 'Aucun choix disponible.',
    this.texteAucunResultat = 'Aucun résultat pour cette recherche.',
    this.texteRecherche = 'Rechercher…',
  });

  /// Options proposées, dans l'ordre d'affichage.
  final List<OptionSelecteur<T>> options;

  /// Valeur sélectionnée (null = aucune sélection).
  final T? valeur;

  final ValueChanged<T?> onChanged;

  /// Libellé affiché au-dessus du champ.
  final String label;

  /// Aide concrète sous le libellé (exemple plutôt que règle).
  final String? aide;

  /// Texte du champ fermé quand rien n'est sélectionné.
  final String placeholder;

  final bool obligatoire;

  /// Message quand la liste d'options est vide.
  final String texteVide;

  /// Message quand la recherche ne trouve rien.
  final String texteAucunResultat;

  /// Indication dans la barre de recherche du panneau.
  final String texteRecherche;

  @override
  State<SelecteurRecherche<T>> createState() => _SelecteurRechercheState<T>();
}

class _SelecteurRechercheState<T> extends State<SelecteurRecherche<T>> {
  final _lien = LayerLink();
  final _rechercheController = TextEditingController();
  OverlayEntry? _entree;
  bool _ouvert = false;
  String _requete = '';
  late T? _valeur;

  @override
  void initState() {
    super.initState();
    _valeur = widget.valeur;
  }

  @override
  void didUpdateWidget(SelecteurRecherche<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valeur != _valeur) _valeur = widget.valeur;
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    _retirerPanneau();
    super.dispose();
  }

  /// Options filtrées par sous-chaîne insensible à la casse, sur le
  /// libellé et le détail (ex. un fragment de nom ou de prénom).
  List<OptionSelecteur<T>> get _filtrees {
    final q = _requete.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) {
      final cible = '${o.libelle} ${o.detail ?? ''}'.toLowerCase();
      return cible.contains(q);
    }).toList();
  }

  OptionSelecteur<T>? get _selectionne {
    if (_valeur == null) return null;
    for (final o in widget.options) {
      if (o.valeur == _valeur) return o;
    }
    return null;
  }

  void _ouvrir() {
    if (_ouvert) {
      _fermer();
      return;
    }
    final largeur = context.size?.width ?? 300;
    _entree = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Clic hors du panneau : le ferme.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _fermer,
            ),
          ),
          CompositedTransformFollower(
            link: _lien,
            showWhenUnlinked: false,
            offset: const Offset(0, 60),
            child: SizedBox(
              width: largeur,
              child: Material(
                elevation: 4,
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                shadowColor: AppTheme.violetProfond.withValues(alpha: 0.3),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Barre de recherche séparée, en haut du panneau.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: TextField(
                          controller: _rechercheController,
                          autofocus: true,
                          onChanged: (v) {
                            // L'entrée de surcouche ne fait pas partie
                            // du sous-arbre reconstruit par setState :
                            // il faut la marquer explicitement, sinon
                            // le filtrage ne s'affiche jamais.
                            _requete = v;
                            _entree?.markNeedsBuild();
                          },
                          decoration: InputDecoration(
                            hintText: widget.texteRecherche,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppTheme.orFonce,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: _contenuPanneau(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entree!);
    setState(() => _ouvert = true);
  }

  Widget _contenuPanneau() {
    if (widget.options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.texteVide,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppTheme.texteSecondaire,
          ),
        ),
      );
    }
    final filtrees = _filtrees;
    if (filtrees.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.texteAucunResultat,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppTheme.texteSecondaire,
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtrees.length,
      itemBuilder: (context, index) {
        final option = filtrees[index];
        final estSelectionne = option.valeur == _valeur;
        return ListTile(
          dense: true,
          title: Text(
            option.libelle,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppTheme.violetProfond,
            ),
          ),
          subtitle: option.detail == null
              ? null
              : Text(
                  option.detail!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.texteSecondaire,
                  ),
                ),
          trailing: estSelectionne
              ? const Icon(Icons.check, color: AppTheme.orFonce)
              : null,
          onTap: () => _choisir(option.valeur),
        );
      },
    );
  }

  void _retirerPanneau() {
    _entree?.remove();
    _entree = null;
  }

  void _fermer() {
    if (!_ouvert) return;
    _retirerPanneau();
    _rechercheController.clear();
    setState(() {
      _ouvert = false;
      _requete = '';
    });
  }

  void _choisir(T valeur) {
    setState(() => _valeur = valeur);
    _fermer();
    widget.onChanged(valeur);
  }

  void _effacer() {
    setState(() => _valeur = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final selectionne = _selectionne;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        etiquetteChamp(
          label: widget.label,
          aide: widget.aide,
          obligatoire: widget.obligatoire,
        ),
        CompositedTransformTarget(
          link: _lien,
          child: InkWell(
            onTap: _ouvrir,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _ouvert
                      ? AppTheme.violetProfond
                      : AppTheme.bordure,
                  width: _ouvert ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectionne?.libelle ?? widget.placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: selectionne == null
                            ? AppTheme.texteSecondaire
                            : AppTheme.violetProfond,
                      ),
                    ),
                  ),
                  if (selectionne != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Effacer la sélection',
                      color: AppTheme.violetProfond,
                      onPressed: _effacer,
                    )
                  else
                    Icon(
                      _ouvert
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppTheme.violetProfond,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (selectionne != null)
          TextButton(
            onPressed: _effacer,
            child: const Text(
              'Effacer la sélection',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
      ],
    );
  }
}
