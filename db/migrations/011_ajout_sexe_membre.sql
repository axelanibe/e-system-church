-- 011 — Sexe du membre (décision de Bouf, 11 nov. 2026).
-- Le matricule suit le système du permis du Québec : la règle « +50 au
-- mois pour les femmes » s'applique au segment JJMMAA (femme née en
-- décembre → mois 62). Le champ est NULLABLE et reste NULL pour les
-- membres existants (aucun membre n'est modifié) ; quand il est
-- inconnu, le mois de naissance reste tel quel dans le matricule.
ALTER TABLE members ADD COLUMN IF NOT EXISTS sexe TEXT
  CHECK (sexe IS NULL OR sexe IN ('M', 'F'));
