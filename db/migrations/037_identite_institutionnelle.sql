-- 037_identite_institutionnelle.sql — Identité institutionnelle (Phase 2)
--
-- `eglise_parametres` devient la source de référence de l'identité
-- institutionnelle (décision du rapport d'audit du 17 nov. 2026, §5) :
-- aujourd'hui `churches` et `eglise_parametres` portent les mêmes champs
-- (logo_url, devise, fuseau_horaire, adresse, téléphone, email, ville)
-- sans synchronisation. Les colonnes `churches` restent en place, en
-- lecture seule transitoire, synchronisées par le serveur.
--
-- Non destructive : que des ADD COLUMN IF NOT EXISTS et une copie de
-- données de `churches` vers `eglise_parametres` là où la cible est
-- vide ; aucune valeur existante de `eglise_parametres` n'est écrasée
-- (elle gagne en cas de conflit). Idempotente : un second passage ne
-- crée ni ne modifie aucune ligne (vérifié par
-- server/test-identite-institutionnelle.mjs).
-- Retour arrière : voir
-- ~/workspace/e-system-church-phoenix/retour-arriere-migration-037.md
-- (revert du code, puis DROP COLUMN des 8 colonnes ajoutées si besoin).

ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS sigle TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS slogan TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS site_web TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS numero_enregistrement TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS infos_legales JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS couleurs JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS parametres_documents JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'brouillon'
  CHECK (statut IN ('brouillon', 'publié'));

DO $$
DECLARE
  creees INT := 0;
  mises_a_jour INT := 0;
BEGIN
  -- Une ligne de paramètres par église (les églises créées sans passer
  -- par PATCH /parametres n'en ont pas encore).
  INSERT INTO eglise_parametres (church_id)
  SELECT id FROM churches
  ON CONFLICT (church_id) DO NOTHING;
  GET DIAGNOSTICS creees = ROW_COUNT;

  -- Copie depuis `churches` là où la cible est vide : la valeur déjà
  -- présente dans `eglise_parametres` gagne en cas de conflit. `devise`
  -- et `fuseau_horaire` sont NOT NULL avec défaut côté paramètres, donc
  -- « vide » y veut dire « le défaut » : on reprend la valeur de
  -- `churches` quand elle diffère du défaut (une église qui a défini sa
  -- devise par le profil ne doit pas la perdre), et on garde celle de
  -- `eglise_parametres` dès qu'elle diffère du défaut (valeur explicite).
  -- `couleurs` : si vide et que `churches` porte une couleur principale,
  -- elle devient `couleurs.principale`.
  UPDATE eglise_parametres p
     SET logo_url = CASE WHEN p.logo_url IS NULL THEN c.logo_url ELSE p.logo_url END,
         devise = CASE WHEN p.devise = 'FCFA' AND c.devise IS NOT NULL AND c.devise <> 'FCFA' THEN c.devise ELSE p.devise END,
         fuseau_horaire = CASE WHEN p.fuseau_horaire = 'Africa/Abidjan' AND c.fuseau_horaire IS NOT NULL AND c.fuseau_horaire <> 'Africa/Abidjan' THEN c.fuseau_horaire ELSE p.fuseau_horaire END,
         adresse = CASE WHEN p.adresse IS NULL THEN c.address ELSE p.adresse END,
         ville = CASE WHEN p.ville IS NULL THEN c.city ELSE p.ville END,
         telephone = CASE WHEN p.telephone IS NULL THEN c.phone ELSE p.telephone END,
         email = CASE WHEN p.email IS NULL THEN c.email ELSE p.email END,
         couleurs = CASE
           WHEN p.couleurs = '{}'::jsonb AND c.couleur_principale IS NOT NULL
           THEN jsonb_build_object('principale', c.couleur_principale)
           ELSE p.couleurs
         END
    FROM churches c
   WHERE p.church_id = c.id
     AND (
       (p.logo_url IS NULL AND c.logo_url IS NOT NULL)
       OR (p.devise = 'FCFA' AND c.devise IS NOT NULL AND c.devise <> 'FCFA')
       OR (p.fuseau_horaire = 'Africa/Abidjan' AND c.fuseau_horaire IS NOT NULL AND c.fuseau_horaire <> 'Africa/Abidjan')
       OR (p.adresse IS NULL AND c.address IS NOT NULL)
       OR (p.ville IS NULL AND c.city IS NOT NULL)
       OR (p.telephone IS NULL AND c.phone IS NOT NULL)
       OR (p.email IS NULL AND c.email IS NOT NULL)
       OR (p.couleurs = '{}'::jsonb AND c.couleur_principale IS NOT NULL)
     );
  GET DIAGNOSTICS mises_a_jour = ROW_COUNT;

  RAISE NOTICE 'migration 037 : % lignes eglise_parametres créées, % lignes mises à jour', creees, mises_a_jour;
END $$;
