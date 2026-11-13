import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'common_widgets.dart';
import 'dialog_helpers.dart';

/// Dialogue « Changer mon mot de passe » (ancien + nouveau + confirmation).
/// Le changement invalide les autres sessions (token_version côté serveur).
Future<void> showChangePasswordDialog(BuildContext context) async {
  final ancienController = TextEditingController();
  final nouveauController = TextEditingController();
  final confirmController = TextEditingController();
  await showCreateDialog(
    context: context,
    title: 'Changer mon mot de passe',
    saveLabel: 'Changer',
    fields: [
      dialogTextField(
          controller: ancienController,
          label: 'Mot de passe actuel',
          obscureText: true),
      dialogTextField(
          controller: nouveauController,
          label: 'Nouveau mot de passe (8 caractères minimum)',
          obscureText: true),
      dialogTextField(
          controller: confirmController,
          label: 'Confirmer le nouveau mot de passe',
          obscureText: true),
    ],
    isValid: () =>
        ancienController.text.isNotEmpty &&
        nouveauController.text.length >= 8 &&
        nouveauController.text == confirmController.text,
    onSave: () async {
      try {
        await context.read<AppState>().api.changePassword(
              ancien: ancienController.text,
              nouveau: nouveauController.text,
            );
        if (context.mounted) {
          showSuccess(context,
              'Mot de passe changé. Vos autres sessions ont été déconnectées.');
        }
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    },
  );
}
