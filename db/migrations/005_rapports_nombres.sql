-- Migration 005 — rapports consolidés : nombres, pas chaînes (11 novembre 2026)
-- La vue v_rapports_consolides renvoyait ses agrégats `count(*)` / `sum()`
-- (bigint) sans cast : node-postgres les transmet comme des chaînes, et
-- l'appli plantait sur l'écran Rapports (« type 'String' is not a subtype
-- of type 'num?' in type cast », constaté le 11/11 sur Render). Désormais
-- les trois agrégats sont castés en `::int`. Le même correctif est appliqué
-- dans db/schema.sql (schéma initial) pour les nouvelles bases. La route
-- /rapports/consolide normalise aussi les lignes avec Number() et l'appli
-- parse désormais les nombres défensivement (rapport.dart) : triple
-- protection.
-- Correctif 11 nov. 2026 (déploiement Render dep-dbqb1kjncjis7390edvg) :
-- CREATE OR REPLACE VIEW ne peut PAS changer le type d'une colonne de vue
-- existante (erreur 42P16 « cannot change data type of view column
-- "membres_actifs" from bigint to integer ») : sur la base en ligne, la
-- vue créée par la 002 a ses agrégats en bigint, la 005 n'a jamais été
-- appliquée, donc elle est rejouée à chaque déploiement et bloque la 006.
-- La vue est donc supprimée puis recréée (DROP + CREATE) au lieu d'être
-- remplacée. Sûr ici : une vue ne contient aucune donnée, et aucune autre
-- vue ne dépend de v_rapports_consolides (seules les routes la lisent).
DROP VIEW IF EXISTS v_rapports_consolides;
CREATE VIEW v_rapports_consolides AS
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
