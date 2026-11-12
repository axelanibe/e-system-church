-- Migration 018 — espace membre (tranche T2, 12 novembre 2026)
-- Photo du membre et bannière de l'église : emplacements seulement.
-- Les images sont fournies par le membre ou l'église, jamais inventées :
-- tant qu'elles ne sont pas fournies, les colonnes restent NULL et
-- l'application affiche les initiales et aucun visuel. Compteur
-- d'annonces non lues : table de lectures par membre (une ligne par
-- annonce lue), le compteur est calculé, jamais stocké. Idempotente.
-- 017 reste réservée à Phoenix (tranche T1, RBAC).

ALTER TABLE members ADD COLUMN IF NOT EXISTS photo_url TEXT;

ALTER TABLE churches ADD COLUMN IF NOT EXISTS banniere_url TEXT;

CREATE TABLE IF NOT EXISTS annonces_lectures (
  annonce_id UUID NOT NULL REFERENCES announcements (id) ON DELETE CASCADE,
  member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
  lu_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (annonce_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_annonces_lectures_membre
    ON annonces_lectures (member_id, lu_at);
