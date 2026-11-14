import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';

/// À propos : ce qu'est e-System Church, son objectif, son utilité,
/// son créateur et son contact. Textes repris mot pour mot de la
/// projection validée par Axel le 12 novembre 2026. Aucun numéro de
/// version inventé.
class AProposScreen extends StatelessWidget {
  const AProposScreen({super.key});

  static const String _telephone = '+1 873 307 5022';

  Future<void> _appeler(BuildContext context) async {
    final ouvert = await launchUrl(
      Uri.parse('tel:+18733075022'),
      mode: LaunchMode.externalApplication,
    );
    if (!ouvert && context.mounted) {
      showApiError(context, 'Impossible d’ouvrir l’appel. $_telephone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.violetProfond,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      // Logo de l'application (projection couleurs du
                      // logo), dans le héros violet.
                      LogoApp(taille: 96),
                      SizedBox(height: 12),
                      Text(
                        'e-System Church',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '« L’église sans frontière »',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.or,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle(title: 'C’est quoi'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'e-System Church est une seule plateforme qui centralise les églises en Côte d’Ivoire. Plusieurs églises peuvent l’utiliser en simultané. Chaque membre est rattaché à une seule église, sans mélange entre les églises.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SectionTitle(title: 'Son objectif'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aider chaque église à gérer ses membres, ses cultes, ses finances, ses campagnes et ses attestations, depuis une seule application. L’application fonctionne sur le web et sur téléphone, avec les mêmes données partout.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SectionTitle(title: 'Son utilité'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _UtiliteLigne(
                          qui: 'Pour la Plateforme',
                          quoi: 'Voir l’ensemble des églises.',
                        ),
                        SizedBox(height: 12),
                        _UtiliteLigne(
                          qui: 'Pour l’église mère',
                          quoi: 'Gérer son église et ses annexes.',
                        ),
                        SizedBox(height: 12),
                        _UtiliteLigne(
                          qui: 'Pour les annexes',
                          quoi: 'Gérer leur propre église.',
                        ),
                        SizedBox(height: 12),
                        _UtiliteLigne(
                          qui: 'Pour le fidèle',
                          quoi:
                              'Retrouver sa carte, sa Bible, ses cotisations, son journal et sa messagerie avec son église.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Son créateur'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Axel Maurice Anibe, fondateur du projet e-System Church.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SectionTitle(title: 'Version et contact'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text('Version'),
                          subtitle: Text(
                              'Version ${AppConfig.appVersion}'),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_outlined),
                          title: const Text('Contact'),
                          subtitle: const Text(
                              'Axel Maurice Anibe\n$_telephone'),
                          trailing: const Icon(Icons.call_outlined),
                          onTap: () => _appeler(context),
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
    );
  }
}

class _UtiliteLigne extends StatelessWidget {
  final String qui;
  final String quoi;

  const _UtiliteLigne({required this.qui, required this.quoi});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 16),
        children: [
          TextSpan(
            text: '$qui — ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: quoi),
        ],
      ),
    );
  }
}
