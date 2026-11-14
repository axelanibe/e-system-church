-- 029 — Socle de confiance (T11, 13 novembre 2026).
-- Sauvegarde chiffrée avec restauration, file d'actions hors ligne
-- avec rejeu idempotent, notifications (boîte d'envoi configurable,
-- aucun fournisseur branché), 2FA TOTP (secret chiffré), journal
-- d'audit immuable à hash chaîné avec journalisation des lectures
-- sensibles, RLS Postgres en complément de l'isolation applicative.
-- Idempotente : db/schema.sql reprend ce miroir pour les nouvelles
-- bases, et les tests appliquent le schéma puis toutes les migrations.

-- Journal d'audit : hash chaîné (chaque ligne scelle la précédente).
-- seq (séquence monotone) ordonne la chaîne sans ambiguïté quand deux
-- lignes partagent la même milliseconde.
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS hash TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS hash_precedent TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS seq BIGSERIAL;
CREATE INDEX IF NOT EXISTS idx_audit_hash ON audit_logs (church_id, created_at, id);

-- Immuabilité : aucune modification ni suppression d'une ligne d'audit.
-- Les lignes créées avant T11 ont un hash NULL (avant la chaîne) ; la
-- vérification ne porte que sur le suffixe chaîné.
CREATE OR REPLACE FUNCTION audit_logs_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_immutable : le journal d''audit ne se modifie pas.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();

-- Lectures sensibles (US17) : qui a lu quelle fiche sensible, quand.
CREATE TABLE IF NOT EXISTS consultations_sensibles (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id       UUID REFERENCES users (id) ON DELETE SET NULL,
    ressource     TEXT NOT NULL,
    ressource_id  UUID,
    action        TEXT NOT NULL DEFAULT 'lecture',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_consultations_church
    ON consultations_sensibles (church_id, created_at);

-- Double authentification TOTP (Pasteur, Trésorier, Admin) : le secret
-- est chiffré AES-256-GCM comme les secrets marchands, jamais en clair.
CREATE TABLE IF NOT EXISTS auth_2fa (
    user_id         UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    secret_chiffre  TEXT NOT NULL,
    secret_iv       TEXT NOT NULL,
    secret_tag      TEXT NOT NULL,
    actif           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_auth_2fa_church ON auth_2fa (church_id, actif);

-- Sauvegardes chiffrées : le contenu est le JSON de toutes les tables
-- à church_id de l'église, chiffré AES-256-GCM. La restauration
-- réinsère les lignes dans l'ordre des dépendances.
CREATE TABLE IF NOT EXISTS sauvegardes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    cree_par        UUID REFERENCES users (id) ON DELETE SET NULL,
    taille_octets   INT NOT NULL CHECK (taille_octets >= 0),
    empreinte       TEXT NOT NULL,
    nb_tables       INT NOT NULL DEFAULT 0 CHECK (nb_tables >= 0),
    tables          TEXT[] NOT NULL DEFAULT '{}',
    contenu_chiffre TEXT NOT NULL,
    iv              TEXT NOT NULL,
    tag             TEXT NOT NULL,
    statut          TEXT NOT NULL DEFAULT 'ok'
                    CHECK (statut IN ('ok', 'restauree')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sauvegardes_church ON sauvegardes (church_id, created_at);

-- Notifications : boîte d'envoi. Aucun fournisseur n'est branché :
-- tant qu'aucun fournisseur n'est configuré, l'envoi échoue proprement
-- (fournisseur_non_configure) et rien ne part. La clé du fournisseur,
-- quand Axel en choisira un, est chiffrée comme les secrets marchands.
CREATE TABLE IF NOT EXISTS notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users (id) ON DELETE SET NULL,
    canal       TEXT NOT NULL DEFAULT 'push' CHECK (canal IN ('push', 'sms')),
    titre       TEXT NOT NULL,
    message     TEXT NOT NULL,
    statut      TEXT NOT NULL DEFAULT 'en_attente'
                CHECK (statut IN ('en_attente', 'envoyee', 'echouee', 'non_configurée')),
    erreur      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    envoyee_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notifications_church ON notifications (church_id, created_at);

-- File d'actions hors ligne : pointages et saisies mis en file sur
-- l'appareil, rejoués dans l'ordre à la reconnexion. cle_client rend
-- le rejeu idempotent (même action soumise deux fois = une seule ligne).
CREATE TABLE IF NOT EXISTS actions_hors_ligne (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id       UUID REFERENCES users (id) ON DELETE SET NULL,
    type_action   TEXT NOT NULL
                  CHECK (type_action IN ('presence.pointer', 'contribution.creer')),
    charge        JSONB NOT NULL DEFAULT '{}'::jsonb,
    cle_client    TEXT NOT NULL,
    statut        TEXT NOT NULL DEFAULT 'en_attente'
                  CHECK (statut IN ('en_attente', 'rejouee', 'echouee')),
    erreur        TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    rejoue_at     TIMESTAMPTZ,
    UNIQUE (church_id, cle_client)
);
CREATE INDEX IF NOT EXISTS idx_actions_hors_ligne_church
    ON actions_hors_ligne (church_id, statut, created_at);

-- Paramètres de confiance par église (vides / désactivés par défaut).
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notification_fournisseur TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notification_cle_chiffree TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notification_cle_iv TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notification_cle_tag TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notification_plafond_mensuel INT NOT NULL DEFAULT 0;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS notifications_actives BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS sauvegarde_frequence TEXT NOT NULL DEFAULT 'jamais'
  CHECK (sauvegarde_frequence IN ('jamais', 'quotidienne', 'hebdomadaire'));
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS sauvegarde_heure TEXT NOT NULL DEFAULT '03:00';
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS sauvegarde_auto_derniere_at TIMESTAMPTZ;

-- ---------------------------------------------------------------------------
-- RLS Postgres : deuxième ligne de défense, en complément de l'isolation
-- applicative (jamais en remplacement). Les tables appartiennent au
-- rôle propriétaire, qui contourne la RLS : les politiques ne filtrent
-- rien aujourd'hui, elles prendront effet quand l'application se
-- connectera avec un rôle restreint (avec app.church_id positionné par
-- transaction). La migration ne change donc aucun comportement actuel.
-- ---------------------------------------------------------------------------
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultations_sensibles ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_2fa ENABLE ROW LEVEL SECURITY;
ALTER TABLE sauvegardes ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE actions_hors_ligne ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'audit_logs') THEN
    CREATE POLICY isolement_eglise ON audit_logs
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'consultations_sensibles') THEN
    CREATE POLICY isolement_eglise ON consultations_sensibles
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'auth_2fa') THEN
    CREATE POLICY isolement_eglise ON auth_2fa
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'sauvegardes') THEN
    CREATE POLICY isolement_eglise ON sauvegardes
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'notifications') THEN
    CREATE POLICY isolement_eglise ON notifications
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'actions_hors_ligne') THEN
    CREATE POLICY isolement_eglise ON actions_hors_ligne
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
END $$;
