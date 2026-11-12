-- Migration 010 — check-ins enfants, double QR ECODIM (11 novembre 2026)
-- École du dimanche : arrivée jumelée bracelet parent-enfant (QR parent =
-- matricule du parent, QR enfant = code #KIDS-XXXX), sortie sécurisée par
-- le même code enfant, alerte silencieuse au parent pendant le culte.
-- Pas de SMS, pas de notification push : l'alerte est un enregistrement en
-- base (alerte, alerte_message, alerte_at), renvoyé à l'app. Le canal SMS
-- appartient au Lot B.
-- Un seul check-in actif par enfant et par jour : un deuxième check-in le
-- même jour est refusé côté serveur (contrainte unique), une deuxième
-- sortie aussi (statut déjà CHECKED_OUT).
DO $$ BEGIN
  CREATE TYPE checkin_enfant_statut AS ENUM ('IN_CLASS', 'CHECKED_OUT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS checkins_enfants (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    enfant_member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    parent_member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    salle             TEXT,
    code_enfant       TEXT NOT NULL,
    allergie          TEXT,
    statut            checkin_enfant_statut NOT NULL DEFAULT 'IN_CLASS',
    alerte            BOOLEAN NOT NULL DEFAULT FALSE,
    alerte_message    TEXT,
    alerte_at         TIMESTAMPTZ,
    date_checkin      DATE NOT NULL DEFAULT CURRENT_DATE,
    checked_in_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    checked_out_at    TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT code_enfant_format CHECK (code_enfant ~ '^KIDS-[A-Z0-9]{4}$'),
    UNIQUE (church_id, date_checkin, enfant_member_id),
    UNIQUE (church_id, date_checkin, code_enfant)
);
CREATE INDEX IF NOT EXISTS idx_checkins_enfants_church_jour
    ON checkins_enfants (church_id, date_checkin);
CREATE INDEX IF NOT EXISTS idx_checkins_enfants_statut
    ON checkins_enfants (church_id, statut);
