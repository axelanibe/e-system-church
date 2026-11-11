import 'package:flutter/material.dart';

/// Champ de saisie standard pour les dialogues de création des modules.
Widget dialogTextField({
  required TextEditingController controller,
  required String label,
  TextInputType keyboardType = TextInputType.text,
  String? hintText,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}

/// Champ de date (AAAA-MM-JJ) avec bouton calendrier qui remplit le champ.
Widget dialogDateField({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          locale: const Locale('fr'),
        );
        if (picked != null) {
          controller.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    ),
  );
}

/// Dialogue de confirmation de suppression. Renvoie vrai si confirmé.
Future<bool> confirmDelete(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Supprimer ?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Petit menu déroulant de choix simple (valeur → libellé).
Widget dialogDropdown<T>({
  required T? value,
  required String label,
  required Map<T, String> options,
  required ValueChanged<T?> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: options.entries
          .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
    ),
  );
}

/// Champ de recherche standard en tête de liste.
Widget searchField({
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  String label = 'Rechercher',
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

/// Affiche un dialogue de création/édition : [fields] puis Annuler/Valider.
/// [onSave] n'est appelé que si [isValid] est vrai.
Future<void> showCreateDialog({
  required BuildContext context,
  required String title,
  required String saveLabel,
  required List<Widget> fields,
  required bool Function() isValid,
  required Future<void> Function() onSave,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: fields),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () async {
            if (!isValid()) return;
            Navigator.of(dialogContext).pop();
            await onSave();
          },
          child: Text(saveLabel),
        ),
      ],
    ),
  );
}
