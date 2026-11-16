import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Un pays et son indicatif téléphonique international.
class IndicatifPays {
  const IndicatifPays(this.iso, this.nom, this.indicatif);

  /// Code ISO 3166-1 alpha-2, il identifie le pays dans la liste.
  final String iso;

  /// Nom du pays, en français.
  final String nom;

  /// Indicatif international, « +225 » par exemple.
  final String indicatif;
}

/// Liste unique des indicatifs pays, partagée par la connexion et
/// les deux inscriptions : un seul endroit à mettre à jour. La Côte
/// d’Ivoire est en tête, c’est la valeur de départ partout ; la
/// suite est par ordre alphabétique du nom français.
const List<IndicatifPays> indicatifsPays = [
  IndicatifPays('CI', 'Côte d’Ivoire', '+225'),
  IndicatifPays('AF', 'Afghanistan', '+93'),
  IndicatifPays('ZA', 'Afrique du Sud', '+27'),
  IndicatifPays('AL', 'Albanie', '+355'),
  IndicatifPays('DZ', 'Algérie', '+213'),
  IndicatifPays('DE', 'Allemagne', '+49'),
  IndicatifPays('AD', 'Andorre', '+376'),
  IndicatifPays('AO', 'Angola', '+244'),
  IndicatifPays('AG', 'Antigua-et-Barbuda', '+1'),
  IndicatifPays('SA', 'Arabie saoudite', '+966'),
  IndicatifPays('AR', 'Argentine', '+54'),
  IndicatifPays('AM', 'Arménie', '+374'),
  IndicatifPays('AU', 'Australie', '+61'),
  IndicatifPays('AT', 'Autriche', '+43'),
  IndicatifPays('AZ', 'Azerbaïdjan', '+994'),
  IndicatifPays('BS', 'Bahamas', '+1'),
  IndicatifPays('BH', 'Bahreïn', '+973'),
  IndicatifPays('BD', 'Bangladesh', '+880'),
  IndicatifPays('BB', 'Barbade', '+1'),
  IndicatifPays('BE', 'Belgique', '+32'),
  IndicatifPays('BZ', 'Belize', '+501'),
  IndicatifPays('BJ', 'Bénin', '+229'),
  IndicatifPays('BT', 'Bhoutan', '+975'),
  IndicatifPays('BY', 'Biélorussie', '+375'),
  IndicatifPays('MM', 'Birmanie', '+95'),
  IndicatifPays('BO', 'Bolivie', '+591'),
  IndicatifPays('BA', 'Bosnie-Herzégovine', '+387'),
  IndicatifPays('BW', 'Botswana', '+267'),
  IndicatifPays('BR', 'Brésil', '+55'),
  IndicatifPays('BN', 'Brunei', '+673'),
  IndicatifPays('BG', 'Bulgarie', '+359'),
  IndicatifPays('BF', 'Burkina Faso', '+226'),
  IndicatifPays('BI', 'Burundi', '+257'),
  IndicatifPays('KH', 'Cambodge', '+855'),
  IndicatifPays('CM', 'Cameroun', '+237'),
  IndicatifPays('CA', 'Canada', '+1'),
  IndicatifPays('CV', 'Cap-Vert', '+238'),
  IndicatifPays('CF', 'Centrafrique', '+236'),
  IndicatifPays('CL', 'Chili', '+56'),
  IndicatifPays('CN', 'Chine', '+86'),
  IndicatifPays('CY', 'Chypre', '+357'),
  IndicatifPays('CO', 'Colombie', '+57'),
  IndicatifPays('KM', 'Comores', '+269'),
  IndicatifPays('CG', 'Congo', '+242'),
  IndicatifPays('CD', 'Congo (RDC)', '+243'),
  IndicatifPays('KP', 'Corée du Nord', '+850'),
  IndicatifPays('KR', 'Corée du Sud', '+82'),
  IndicatifPays('CR', 'Costa Rica', '+506'),
  IndicatifPays('HR', 'Croatie', '+385'),
  IndicatifPays('CU', 'Cuba', '+53'),
  IndicatifPays('DK', 'Danemark', '+45'),
  IndicatifPays('DJ', 'Djibouti', '+253'),
  IndicatifPays('DM', 'Dominique', '+1'),
  IndicatifPays('EG', 'Égypte', '+20'),
  IndicatifPays('AE', 'Émirats arabes unis', '+971'),
  IndicatifPays('EC', 'Équateur', '+593'),
  IndicatifPays('ER', 'Érythrée', '+291'),
  IndicatifPays('ES', 'Espagne', '+34'),
  IndicatifPays('EE', 'Estonie', '+372'),
  IndicatifPays('SZ', 'Eswatini', '+268'),
  IndicatifPays('US', 'États-Unis', '+1'),
  IndicatifPays('ET', 'Éthiopie', '+251'),
  IndicatifPays('FJ', 'Fidji', '+679'),
  IndicatifPays('FI', 'Finlande', '+358'),
  IndicatifPays('FR', 'France', '+33'),
  IndicatifPays('GA', 'Gabon', '+241'),
  IndicatifPays('GM', 'Gambie', '+220'),
  IndicatifPays('GE', 'Géorgie', '+995'),
  IndicatifPays('GH', 'Ghana', '+233'),
  IndicatifPays('GR', 'Grèce', '+30'),
  IndicatifPays('GD', 'Grenade', '+1'),
  IndicatifPays('GT', 'Guatemala', '+502'),
  IndicatifPays('GN', 'Guinée', '+224'),
  IndicatifPays('GW', 'Guinée-Bissau', '+245'),
  IndicatifPays('GQ', 'Guinée équatoriale', '+240'),
  IndicatifPays('GY', 'Guyana', '+592'),
  IndicatifPays('HT', 'Haïti', '+509'),
  IndicatifPays('HN', 'Honduras', '+504'),
  IndicatifPays('HU', 'Hongrie', '+36'),
  IndicatifPays('IN', 'Inde', '+91'),
  IndicatifPays('ID', 'Indonésie', '+62'),
  IndicatifPays('IQ', 'Irak', '+964'),
  IndicatifPays('IR', 'Iran', '+98'),
  IndicatifPays('IE', 'Irlande', '+353'),
  IndicatifPays('IS', 'Islande', '+354'),
  IndicatifPays('IL', 'Israël', '+972'),
  IndicatifPays('IT', 'Italie', '+39'),
  IndicatifPays('JM', 'Jamaïque', '+1'),
  IndicatifPays('JP', 'Japon', '+81'),
  IndicatifPays('JO', 'Jordanie', '+962'),
  IndicatifPays('KZ', 'Kazakhstan', '+7'),
  IndicatifPays('KE', 'Kenya', '+254'),
  IndicatifPays('KG', 'Kirghizistan', '+996'),
  IndicatifPays('KI', 'Kiribati', '+686'),
  IndicatifPays('KW', 'Koweït', '+965'),
  IndicatifPays('LA', 'Laos', '+856'),
  IndicatifPays('LS', 'Lesotho', '+266'),
  IndicatifPays('LV', 'Lettonie', '+371'),
  IndicatifPays('LB', 'Liban', '+961'),
  IndicatifPays('LR', 'Liberia', '+231'),
  IndicatifPays('LY', 'Libye', '+218'),
  IndicatifPays('LI', 'Liechtenstein', '+423'),
  IndicatifPays('LT', 'Lituanie', '+370'),
  IndicatifPays('LU', 'Luxembourg', '+352'),
  IndicatifPays('MG', 'Madagascar', '+261'),
  IndicatifPays('MY', 'Malaisie', '+60'),
  IndicatifPays('MW', 'Malawi', '+265'),
  IndicatifPays('MV', 'Maldives', '+960'),
  IndicatifPays('ML', 'Mali', '+223'),
  IndicatifPays('MT', 'Malte', '+356'),
  IndicatifPays('MA', 'Maroc', '+212'),
  IndicatifPays('MU', 'Maurice', '+230'),
  IndicatifPays('MR', 'Mauritanie', '+222'),
  IndicatifPays('MX', 'Mexique', '+52'),
  IndicatifPays('MD', 'Moldavie', '+373'),
  IndicatifPays('MC', 'Monaco', '+377'),
  IndicatifPays('MN', 'Mongolie', '+976'),
  IndicatifPays('ME', 'Monténégro', '+382'),
  IndicatifPays('MZ', 'Mozambique', '+258'),
  IndicatifPays('NA', 'Namibie', '+264'),
  IndicatifPays('NR', 'Nauru', '+674'),
  IndicatifPays('NP', 'Népal', '+977'),
  IndicatifPays('NI', 'Nicaragua', '+505'),
  IndicatifPays('NE', 'Niger', '+227'),
  IndicatifPays('NG', 'Nigeria', '+234'),
  IndicatifPays('NO', 'Norvège', '+47'),
  IndicatifPays('NZ', 'Nouvelle-Zélande', '+64'),
  IndicatifPays('OM', 'Oman', '+968'),
  IndicatifPays('UG', 'Ouganda', '+256'),
  IndicatifPays('UZ', 'Ouzbékistan', '+998'),
  IndicatifPays('PK', 'Pakistan', '+92'),
  IndicatifPays('PW', 'Palaos', '+680'),
  IndicatifPays('PS', 'Palestine', '+970'),
  IndicatifPays('PA', 'Panama', '+507'),
  IndicatifPays('PG', 'Papouasie-Nouvelle-Guinée', '+675'),
  IndicatifPays('PY', 'Paraguay', '+595'),
  IndicatifPays('NL', 'Pays-Bas', '+31'),
  IndicatifPays('PE', 'Pérou', '+51'),
  IndicatifPays('PH', 'Philippines', '+63'),
  IndicatifPays('PL', 'Pologne', '+48'),
  IndicatifPays('PT', 'Portugal', '+351'),
  IndicatifPays('QA', 'Qatar', '+974'),
  IndicatifPays('RO', 'Roumanie', '+40'),
  IndicatifPays('GB', 'Royaume-Uni', '+44'),
  IndicatifPays('RU', 'Russie', '+7'),
  IndicatifPays('RW', 'Rwanda', '+250'),
  IndicatifPays('KN', 'Saint-Christophe-et-Niévès', '+1'),
  IndicatifPays('LC', 'Sainte-Lucie', '+1'),
  IndicatifPays('SM', 'Saint-Marin', '+378'),
  IndicatifPays('VC', 'Saint-Vincent-et-les-Grenadines', '+1'),
  IndicatifPays('SB', 'Salomon', '+677'),
  IndicatifPays('SV', 'Salvador', '+503'),
  IndicatifPays('WS', 'Samoa', '+685'),
  IndicatifPays('ST', 'Sao Tomé-et-Principe', '+239'),
  IndicatifPays('SN', 'Sénégal', '+221'),
  IndicatifPays('RS', 'Serbie', '+381'),
  IndicatifPays('SC', 'Seychelles', '+248'),
  IndicatifPays('SL', 'Sierra Leone', '+232'),
  IndicatifPays('SG', 'Singapour', '+65'),
  IndicatifPays('SK', 'Slovaquie', '+421'),
  IndicatifPays('SI', 'Slovénie', '+386'),
  IndicatifPays('SO', 'Somalie', '+252'),
  IndicatifPays('SD', 'Soudan', '+249'),
  IndicatifPays('SS', 'Soudan du Sud', '+211'),
  IndicatifPays('LK', 'Sri Lanka', '+94'),
  IndicatifPays('SE', 'Suède', '+46'),
  IndicatifPays('CH', 'Suisse', '+41'),
  IndicatifPays('SR', 'Suriname', '+597'),
  IndicatifPays('SY', 'Syrie', '+963'),
  IndicatifPays('TJ', 'Tadjikistan', '+992'),
  IndicatifPays('TZ', 'Tanzanie', '+255'),
  IndicatifPays('TD', 'Tchad', '+235'),
  IndicatifPays('CZ', 'Tchéquie', '+420'),
  IndicatifPays('TH', 'Thaïlande', '+66'),
  IndicatifPays('TL', 'Timor-Leste', '+670'),
  IndicatifPays('TG', 'Togo', '+228'),
  IndicatifPays('TO', 'Tonga', '+676'),
  IndicatifPays('TT', 'Trinité-et-Tobago', '+1'),
  IndicatifPays('TN', 'Tunisie', '+216'),
  IndicatifPays('TM', 'Turkménistan', '+993'),
  IndicatifPays('TR', 'Turquie', '+90'),
  IndicatifPays('TV', 'Tuvalu', '+688'),
  IndicatifPays('UA', 'Ukraine', '+380'),
  IndicatifPays('UY', 'Uruguay', '+598'),
  IndicatifPays('VU', 'Vanuatu', '+678'),
  IndicatifPays('VA', 'Vatican', '+379'),
  IndicatifPays('VE', 'Venezuela', '+58'),
  IndicatifPays('VN', 'Vietnam', '+84'),
  IndicatifPays('YE', 'Yémen', '+967'),
  IndicatifPays('ZM', 'Zambie', '+260'),
  IndicatifPays('ZW', 'Zimbabwe', '+263'),
];

/// Indicatif d’un pays par son code ISO, Côte d’Ivoire si inconnu.
IndicatifPays indicatifParIso(String iso) {
  for (final pays in indicatifsPays) {
    if (pays.iso == iso) return pays;
  }
  return indicatifsPays.first;
}

/// Vrai quand la saisie ressemble à un numéro de téléphone : que
/// des chiffres et la ponctuation d'un numéro (espaces, +, -, ()).
/// Un texte avec des lettres ou un @ est un e-mail, pas un numéro.
bool estNumeroTelephone(String saisie) {
  final texte = saisie.trim();
  if (texte.isEmpty) return true;
  return RegExp(r'^[0-9\s+\-()]+$').hasMatch(texte);
}

/// Préfixe l’indicatif choisi à un numéro saisi. Un e-mail (il
/// contient @ ou des lettres) est renvoyé tel quel : l’indicatif
/// est ignoré. Un numéro déjà international (il commence par +)
/// est renvoyé tel quel aussi, pour ne pas le préfixer deux fois.
/// Le serveur normalise ensuite le numéro (espaces retirés, 0
/// après +225 retiré, autre +… gardé tel quel) : la logique
/// d’envoi ne change pas, seul l’indicatif s’ajoute devant le
/// numéro.
String composerTelephoneAvecIndicatif(String indicatif, String saisie) {
  final texte = saisie.trim();
  if (texte.isEmpty || texte.startsWith('+') || !estNumeroTelephone(texte)) {
    return texte;
  }
  return '$indicatif $texte';
}

/// Sélecteur d’indicatif pays, à mettre en préfixe d’un champ de
/// téléphone (InputDecoration.prefix) : dans le champ, seul
/// l’indicatif s’affiche (« +225 ») ; le menu déroulant montre le
/// nom du pays avec son indicatif. Une seule liste, un seul
/// sélecteur, utilisés par la connexion et les deux inscriptions.
/// Texte à 16 px, comme les champs de saisie.
class SelecteurIndicatifPays extends StatelessWidget {
  const SelecteurIndicatifPays({
    super.key,
    required this.iso,
    required this.onChanged,
  });

  /// Code ISO du pays choisi.
  final String iso;

  /// Appelé avec le code ISO du pays choisi.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const styleIndicatif = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppTheme.violetProfond,
    );
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: iso,
        isDense: true,
        icon: const Icon(
          Icons.arrow_drop_down,
          size: 18,
          color: AppTheme.violetProfond,
        ),
        style: styleIndicatif,
        menuMaxHeight: 320,
        items: indicatifsPays
            .map(
              (pays) => DropdownMenuItem<String>(
                value: pays.iso,
                child: Text(
                  '${pays.nom} (${pays.indicatif})',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            )
            .toList(),
        selectedItemBuilder: (context) => indicatifsPays
            .map((pays) => Text(pays.indicatif, style: styleIndicatif))
            .toList(),
        onChanged: (nouvelIso) {
          if (nouvelIso != null) onChanged(nouvelIso);
        },
      ),
    );
  }
}
