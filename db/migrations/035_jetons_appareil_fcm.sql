-- 035 — Notifications push FCM (tranche Notifications push FCM, 16 novembre 2026).
-- Jetons d'appareil FCM des membres : un jeton par appareil (web ou
-- android), rattaché à un membre et à son église. Un même jeton ne peut
-- appartenir qu'à un seul appareil à la fois (UNIQUE sur le jeton).
-- Provenance de la configuration Firebase : le compte de service est lu
-- depuis la variable d'environnement FIREBASE_SERVICE_ACCOUNT_JSON, il
-- vient du projet Firebase séparé « e-system-church », dans le même
-- compte Google que CONNEXION PROPHÉTIQUE, et non du projet
-- « connexion-prophetique » lui-même, pour ne pas mélanger les
-- notifications des deux applications. Le projet est créé par Axel ;
-- aucun secret ni clé n'est stocké dans le dépôt.
-- Idempotente : CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
-- politique créée seulement si absente (motif de la migration 034).

CREATE TABLE IF NOT EXISTS device_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id    UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    token        TEXT NOT NULL,
    platform     TEXT NOT NULL CHECK (platform IN ('web', 'android')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    is_active    BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (token)
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_church_member
    ON device_tokens (church_id, member_id);

-- ---------------------------------------------------------------------------
-- RLS Postgres : deuxième ligne de défense, en complément de l'isolation
-- applicative (jamais en remplacement), même motif que la migration 034.
-- ---------------------------------------------------------------------------
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'device_tokens') THEN
    CREATE POLICY isolement_eglise ON device_tokens
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
END $$;
