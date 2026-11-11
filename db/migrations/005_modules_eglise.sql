-- Migration 005 — modules activables par église, US1 (11 novembre 2026)
-- Appliquée par `npm run migrate` (server/src/migrate.ts), dans l'ordre.
-- Idempotente (IF NOT EXISTS, ON CONFLICT DO NOTHING).
-- Voir db/schema.sql pour le commentaire complet de la table.
--
-- Règle de reprise : les églises créées AVANT US1 avaient tous les modules
-- visibles ; on les remplit toutes à « actif » pour ne rien leur couper.
-- Les églises créées APRÈS US1 n'ont aucune ligne : seuls le noyau
-- (membres, finances, rapports) est actif, l'admin active ensuite ce
-- qu'il faut. Chaque église décide seule pour elle-même ; la mère ne
-- force pas ses antennes.

CREATE TABLE IF NOT EXISTS eglise_modules (
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    module     TEXT NOT NULL CHECK (module IN
                 ('annonces','familles','cultes','presences','budget',
                  'prieres','pastoral','serviteurs','enfants','medias',
                  'biens','parametres','mon_eglise')),
    actif      BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (church_id, module)
);
CREATE INDEX IF NOT EXISTS idx_eglise_modules_church ON eglise_modules (church_id);

INSERT INTO eglise_modules (church_id, module, actif)
SELECT c.id, m.module, TRUE
  FROM churches c
 CROSS JOIN (VALUES
   ('annonces'), ('familles'), ('cultes'), ('presences'), ('budget'),
   ('prieres'), ('pastoral'), ('serviteurs'), ('enfants'), ('medias'),
   ('biens'), ('parametres'), ('mon_eglise')
 ) AS m(module)
ON CONFLICT (church_id, module) DO NOTHING;
