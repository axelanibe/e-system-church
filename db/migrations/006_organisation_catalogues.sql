-- 006 — Départements, fonctions et postes pré-enregistrés à la création d'une église.
-- Idempotente : peut être rejouée sans doublon.
-- Listes de départ (catalogue, pas une structure rigide), toutes modifiables
-- par l'administrateur (ajout, renommage, suppression bloquée si utilisée).
-- Sources : document E_SYSTEM_CHURCH_Architecture_Fonctionnelle.pdf (§3, §4)
-- pour les 16 départements en 4 pôles et les 5 postes ; fonctions habituelles
-- dans les églises (liste d'Axel, pas celle de CONNEXION PROPHÉTIQUE).
-- - `fonctions` : catalogue par église (nom unique par église).
-- - `postes` : catalogue par église (nom unique par église).
-- - `members.fonction` / `members.poste` : fonction et poste du membre,
--   stockés séparément du département, comme `department` déjà en place ;
--   « Aucun » = NULL pour la fonction, la carte montre alors « Membre ».
-- - `membre_departements` : une personne peut avoir plusieurs affectations
--   distinctes ; période de validité (`date_debut`, `date_fin`) et `statut`
--   (`active`, `terminee`) : une affectation terminée est archivée, pas effacée.
-- - Amorçage des églises EXISTANTES avec les listes par défaut
--   (les nouvelles églises sont amorcées dans registerChurch, en transaction).

CREATE TABLE IF NOT EXISTS fonctions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_fonctions_church ON fonctions (church_id);

CREATE TABLE IF NOT EXISTS postes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_postes_org_church ON postes (church_id);

ALTER TABLE members ADD COLUMN IF NOT EXISTS fonction TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS poste TEXT;

ALTER TABLE membre_departements ADD COLUMN IF NOT EXISTS date_debut DATE;
ALTER TABLE membre_departements ADD COLUMN IF NOT EXISTS date_fin DATE;
ALTER TABLE membre_departements ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'active'
  CHECK (statut IN ('active', 'terminee'));

INSERT INTO departements (church_id, nom, description)
SELECT c.id, d.nom, 'Pôle : ' || d.pole
  FROM churches c
 CROSS JOIN (VALUES
   ('Prière et intercession', 'Spiritualité et ministère'),
   ('Évangélisation et missions', 'Spiritualité et ministère'),
   ('Formation biblique', 'Spiritualité et ministère'),
   ('Louange et adoration', 'Spiritualité et ministère'),
   ('Accompagnement pastoral', 'Spiritualité et ministère'),
   ('Administration générale', 'Administration et gestion'),
   ('Finances et comptabilité', 'Administration et gestion'),
   ('Ressources humaines', 'Administration et gestion'),
   ('Logistique et patrimoine', 'Administration et gestion'),
   ('Protocole, accueil et sécurité', 'Administration et gestion'),
   ('Communication et médias', 'Communication et développement'),
   ('Informatique et numérique', 'Communication et développement'),
   ('Événementiel', 'Communication et développement'),
   ('Jeunesse et enfants', 'Communauté et action sociale'),
   ('Femmes, hommes et familles', 'Communauté et action sociale'),
   ('Action sociale et solidarité', 'Communauté et action sociale')
 ) AS d(nom, pole)
ON CONFLICT (church_id, nom) DO NOTHING;

INSERT INTO fonctions (church_id, nom)
SELECT c.id, f.nom
  FROM churches c
 CROSS JOIN (VALUES
   ('Pasteur'),
   ('Ancien'),
   ('Diacre'),
   ('Diaconesse'),
   ('Intercesseur'),
   ('Chantre'),
   ('Responsable'),
   ('Secrétaire'),
   ('Trésorier'),
   ('Leader'),
   ('Membre'),
   ('Aucun')
 ) AS f(nom)
ON CONFLICT (church_id, nom) DO NOTHING;

INSERT INTO postes (church_id, nom)
SELECT c.id, p.nom
  FROM churches c
 CROSS JOIN (VALUES
   ('Directeur de département'),
   ('Directeur adjoint'),
   ('Chef de service ou d''équipe'),
   ('Responsable d''activité'),
   ('Collaborateur ou bénévole')
 ) AS p(nom)
ON CONFLICT (church_id, nom) DO NOTHING;
