import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';

/// À propos : ce qu'est e-System Church, son objectif, son utilité,
/// son créateur et son contact. Textes repris mot pour mot de la
/// projection validée par Axel le 12 novembre 2026. Aucun numéro de
/// version inventé, et aucun numéro de téléphone : la maquette
/// (écran 18) dit « Contact à ajouter une fois un numéro public
/// confirmé ».
class AProposScreen extends StatelessWidget {
  const AProposScreen({super.key});

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
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.violetProfond,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      // Logo de l'application (projection couleurs du
                      // logo), dans le héros violet.
                      LogoApp(taille: 88),
                      SizedBox(height: 12),
                      Text(
                        'e-System Church',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'L’église sans frontières',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.or,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle(title: 'C’est quoi'),
                // Maquette, écran 18 : les deux paragraphes (c'est
                // quoi, puis l'objectif) dans une seule carte, sans
                // section « Son objectif » séparée.
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'e-System Church est une seule plateforme qui centralise les églises dans le monde entier — l’église sans frontières. Plusieurs églises peuvent l’utiliser en simultané, où qu’elles se trouvent. Chaque membre est rattaché à une seule église, sans mélange entre les églises.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Aider chaque église à gérer ses membres, ses cultes, ses finances, ses campagnes et ses attestations, depuis une seule application. L’application fonctionne sur le web et sur téléphone, avec les mêmes données partout.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Son utilité'),
                const Card(
                  child: Column(
                    children: [
                      _UtiliteLigne(
                        icone: Icons.public_outlined,
                        qui: 'Plateforme',
                        quoi: 'Voir l’ensemble des églises.',
                      ),
                      Divider(height: 1),
                      _UtiliteLigne(
                        icone: Icons.home_work_outlined,
                        qui: 'Église mère',
                        quoi: 'Gérer son église et ses annexes.',
                      ),
                      Divider(height: 1),
                      _UtiliteLigne(
                        icone: Icons.apartment_outlined,
                        qui: 'Annexes',
                        quoi: 'Gérer leur propre église.',
                      ),
                      Divider(height: 1),
                      _UtiliteLigne(
                        icone: Icons.person_outlined,
                        qui: 'Fidèle',
                        quoi:
                            'Retrouver sa carte, sa Bible, ses cotisations, son journal et sa messagerie avec son église.',
                      ),
                    ],
                  ),
                ),
                const SectionTitle(title: 'Version et contact'),
                // Maquette, écran 18 : Version, Fondateur et contact
                // dans la même carte, sans section « Son créateur »
                // séparée.
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text(
                            'Version ${AppConfig.appVersion}',
                            style: TextStyle(fontSize: 13.5)),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.auto_awesome_outlined),
                        title: Text('Fondateur',
                            style: TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                            'Axel Maurice Anibe, créateur du projet',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.person_outlined),
                        title: Text('Axel Maurice Anibe',
                            style: TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                            'Contact à ajouter une fois un numéro public confirmé',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
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
  final IconData icone;
  final String qui;
  final String quoi;

  const _UtiliteLigne(
      {required this.icone, required this.qui, required this.quoi});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone, color: AppTheme.or),
      title: Text(
        qui,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        quoi,
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}
