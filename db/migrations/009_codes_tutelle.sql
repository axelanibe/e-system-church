-- Migration 009 — codes de tutelle à usage unique et rattachement (11 novembre 2026)
-- Une église mère génère un code de tutelle `ESC-T-XXXXXX` pour une église
-- qui veut se rattacher à elle. Le code ne sert qu'une fois : à l'acceptation
-- du rattachement il passe à `utilise` (utilisée par, date), automatiquement,
-- sans action manuelle. Un deuxième usage est refusé côté serveur.
-- Le code permanent ESC-… de l'église mère n'est pas touché : il sert toujours
-- à l'inscription des membres et aux demandes par `parent_code`.
-- `rattachements.code_tutelle_id` relie la demande au code utilisé.
-- Le schéma initial (db/schema.sql) définit déjà ce type : sur une base
-- neuve la migration est rejouée après le schéma, on ignore le doublon.
DO $$ BEGIN
  CREATE TYPE code_tutelle_status AS ENUM ('actif', 'utilise', 'annule');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS codes_tutelle (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    code       TEXT NOT NULL UNIQUE,
    status     code_tutelle_status NOT NULL DEFAULT 'actif',
    used_by    UUID REFERENCES churches (id) ON DELETE SET NULL,
    used_at    TIMESTAMPTZ,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT code_tutelle_format CHECK (code ~ '^ESC-T-[A-Z0-9]{6}$')
);
CREATE INDEX IF NOT EXISTS idx_codes_tutelle_church ON codes_tutelle (church_id);
CREATE INDEX IF NOT EXISTS idx_codes_tutelle_code ON codes_tutelle (code);

ALTER TABLE rattachements
  ADD COLUMN IF NOT EXISTS code_tutelle_id UUID REFERENCES codes_tutelle (id) ON DELETE SET NULL;
