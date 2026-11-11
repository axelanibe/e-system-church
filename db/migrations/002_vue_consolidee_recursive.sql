-- Migration 002 — vue consolidée récursive (10 novembre 2026)
-- Appliquée par `npm run migrate` (server/src/migrate.ts), dans l'ordre.
-- La vue v_rapports_consolides couvrait seulement les sous-églises directes :
-- une petite-fille (par exemple Bouaké Centre sous Bouaké) n'était pas vue
-- par sa grand-mère. Désormais, eglise_mere_id est la racine du réseau et
-- chaque descendant porte son niveau (1 = sous-église directe, 2 = antenne
-- d'une sous-église, …). CREATE OR REPLACE VIEW : rejouable sans erreur.
-- Voir db/schema.sql pour le commentaire complet de la vue.
-- Correctif 11 nov. 2026 (tranche aménagement église mère) : les agrégats
-- sont castés en `::int`, comme dans le schéma initial et la migration 005.
-- Sans cela, une base neuve échoue ici : le schéma crée déjà la vue avec
-- `membres_actifs` en integer, et ce CREATE OR REPLACE tentait de repasser
-- la colonne en bigint. Sur les bases existantes, la 002 est déjà marquée
-- appliquée : aucun changement pour elles.
CREATE OR REPLACE VIEW v_rapports_consolides AS
WITH RECURSIVE descendants AS (
    SELECT id AS eglise_id, id AS racine_id, 0 AS niveau
      FROM churches
     UNION ALL
    SELECT c.id, d.racine_id, d.niveau + 1
      FROM churches c
      JOIN descendants d ON c.parent_church_id = d.eglise_id
)
SELECT
    d.racine_id AS eglise_mere_id,
    c.id        AS eglise_id,
    c.name      AS eglise_nom,
    d.niveau    AS niveau,
    (SELECT count(*)::int FROM members m WHERE m.church_id = c.id AND m.status = 'actif') AS membres_actifs,
    (SELECT count(*)::int FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS nombre_contributions,
    (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS total_fcfa
FROM churches c
JOIN descendants d ON d.eglise_id = c.id
WHERE d.racine_id <> c.id;
