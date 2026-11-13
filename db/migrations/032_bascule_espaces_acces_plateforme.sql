-- 032 — Bascule entre espaces indépendants + accès spécial Plateforme
-- (13 novembre 2026).
-- Nouveau rôle : aide de la Plateforme. Un aide voit les chiffres globaux
-- (droit « chiffres ») mais ne gère pas les accès : seul le super_admin
-- crée et révoque les accès Plateforme.
-- Idempotente (comme la 031) : db/schema.sql reprend ce miroir pour les
-- nouvelles bases, et les tests appliquent le schéma puis toutes les
-- migrations.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'user_role' AND e.enumlabel = 'aide_plateforme'
  ) THEN
    ALTER TYPE user_role ADD VALUE 'aide_plateforme';
  END IF;
END $$;

-- Droits choisis par le super_admin pour chaque aide. Un seul droit
-- existe aujourd'hui (« chiffres » : voir les chiffres globaux) ; la
-- liste s'allongera avec les capacités de la Plateforme.
CREATE TABLE IF NOT EXISTS acces_plateforme (
    user_id   UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    droits    TEXT[] NOT NULL DEFAULT '{}',
    cree_par  UUID REFERENCES users (id) ON DELETE SET NULL,
    cree_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT acces_plateforme_droits_connus CHECK (droits <@ ARRAY['chiffres']::text[])
);
