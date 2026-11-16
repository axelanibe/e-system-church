-- 034 — Messagerie et Signalement (T-Msg-0, 16 novembre 2026).
-- Conversations (directes, groupes, pastorale, modération), messages et
-- pièces jointes, signalements avec escalade vers l'église mère ou le
-- référent protection de l'enfance, actions de modération, recours,
-- blocages et marquage des mineurs.
-- Idempotente : CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
-- politiques créées seulement si absentes (motif de la migration 029).

-- Conversations.
CREATE TABLE IF NOT EXISTS conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type            TEXT CHECK (type IN ('directe', 'groupe_departement', 'groupe_eglise', 'pastorale', 'moderation')),
    title           TEXT,
    created_by      UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_archived     BOOLEAN NOT NULL DEFAULT false,
    last_message_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_conversations_church
    ON conversations (church_id, created_at);

-- Participants d'une conversation.
CREATE TABLE IF NOT EXISTS conversation_participants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    role            TEXT,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_read_at    TIMESTAMPTZ,
    muted_until     TIMESTAMPTZ,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (conversation_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation
    ON conversation_participants (conversation_id);

-- Messages.
CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    type            TEXT CHECK (type IN ('text', 'image', 'file', 'system')) DEFAULT 'text',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ,
    is_reported     BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_church_conversation
    ON messages (church_id, conversation_id, created_at);

-- Pièces jointes d'un message.
CREATE TABLE IF NOT EXISTS message_attachments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id  UUID NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    storage_key TEXT NOT NULL,
    mime_type   TEXT,
    size_bytes  BIGINT,
    sha256      TEXT
);

-- Signalements.
CREATE TABLE IF NOT EXISTS reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    reporter_id         UUID NOT NULL,
    target_type         TEXT CHECK (target_type IN ('message', 'conversation', 'user')),
    target_id           UUID NOT NULL,
    reason              TEXT CHECK (reason IN ('harassment', 'hate_speech', 'threat', 'misinformation', 'spam', 'child_safety', 'other')),
    description         TEXT CHECK (char_length(description) <= 500),
    evidence_snapshot   JSONB,
    evidence_hash       TEXT,
    routed_to           TEXT CHECK (routed_to IN ('local', 'mother', 'child_safety_referent')) DEFAULT 'local',
    routed_to_church_id UUID REFERENCES churches (id),
    status              TEXT CHECK (status IN ('pending', 'in_review', 'resolved', 'dismissed', 'escalated', 'appealed')) DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at         TIMESTAMPTZ,
    resolution_notes    TEXT,
    retention_until     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_reports_church_status
    ON reports (church_id, status);
CREATE INDEX IF NOT EXISTS idx_reports_routed_to
    ON reports (routed_to, routed_to_church_id);

-- Actions de modération sur un signalement.
CREATE TABLE IF NOT EXISTS moderation_actions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id    UUID NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    moderator_id UUID NOT NULL,
    action       TEXT NOT NULL,
    notes        TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Recours contre une action de modération (15 jours pour contester).
CREATE TABLE IF NOT EXISTS appeals (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id            UUID NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    church_id            UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    moderation_action_id UUID REFERENCES moderation_actions (id),
    appellant_id         UUID NOT NULL,
    reason               TEXT,
    reviewer_id          UUID,
    status               TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'resolved', 'dismissed')),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at          TIMESTAMPTZ
);

-- Blocages entre membres.
CREATE TABLE IF NOT EXISTS blocks (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL,
    blocked_id UUID NOT NULL,
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (blocker_id, blocked_id, church_id)
);

-- Marquage des mineurs : visibilité restreinte, tuteurs déclarés.
CREATE TABLE IF NOT EXISTS minor_flags (
    member_id    UUID PRIMARY KEY REFERENCES members (id) ON DELETE CASCADE,
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    is_minor     BOOLEAN NOT NULL,
    guardian_ids UUID[] NOT NULL DEFAULT '{}',
    visibility   TEXT NOT NULL DEFAULT 'restricted' CHECK (visibility = 'restricted')
);

-- ---------------------------------------------------------------------------
-- RLS Postgres : deuxième ligne de défense, en complément de l'isolation
-- applicative (jamais en remplacement). Les tables appartiennent au
-- rôle propriétaire, qui contourne la RLS : les politiques ne filtrent
-- rien aujourd'hui, elles prendront effet quand l'application se
-- connectera avec un rôle restreint (avec app.church_id positionné par
-- transaction). La migration ne change donc aucun comportement actuel.
-- ---------------------------------------------------------------------------
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE appeals ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE minor_flags ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'conversations') THEN
    CREATE POLICY isolement_eglise ON conversations
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'conversation_participants') THEN
    CREATE POLICY isolement_eglise ON conversation_participants
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'messages') THEN
    CREATE POLICY isolement_eglise ON messages
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'message_attachments') THEN
    CREATE POLICY isolement_eglise ON message_attachments
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'reports') THEN
    CREATE POLICY isolement_eglise ON reports
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'moderation_actions') THEN
    CREATE POLICY isolement_eglise ON moderation_actions
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'appeals') THEN
    CREATE POLICY isolement_eglise ON appeals
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'blocks') THEN
    CREATE POLICY isolement_eglise ON blocks
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'minor_flags') THEN
    CREATE POLICY isolement_eglise ON minor_flags
      USING (church_id = current_setting('app.church_id', true)::uuid)
      WITH CHECK (church_id = current_setting('app.church_id', true)::uuid);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Escalade vers l'église mère : un signalement routé vers la mère
-- (routed_to = 'mother') est lisible par la direction de l'église mère
-- désignée (routed_to_church_id), en lecture seule.
--
-- Le rôle 'direction_eglise_mere' n'existe pas encore dans l'enum
-- user_role : il est comparé en texte (cu.role::text) pour ne pas
-- toucher à l'enum maintenant. Il sera ajouté à l'enum et branché au
-- RBAC dans une tranche ultérieure.
--
-- La restriction aux seules colonnes evidence_snapshot, reason,
-- description, status, created_at exige un rôle restreint avec GRANT
-- par colonnes : à faire quand l'application quittera le rôle
-- propriétaire (la RLS seule ne restreint pas les colonnes).
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'escalade_mere' AND tablename = 'reports') THEN
    CREATE POLICY escalade_mere ON reports
      FOR SELECT
      USING (
        routed_to = 'mother'
        AND routed_to_church_id = current_setting('app.church_id', true)::uuid
        AND EXISTS (
          SELECT 1 FROM users u
          JOIN church_users cu ON cu.user_id = u.id
          WHERE u.member_id = current_setting('app.member_id', true)::uuid
            AND cu.church_id = current_setting('app.church_id', true)::uuid
            AND cu.role::text = 'direction_eglise_mere'
        )
      );
  END IF;
END $$;
