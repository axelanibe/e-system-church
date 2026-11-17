-- 036_signatures_electroniques.sql — Signature électronique V1
-- (signature dessinée dans l'application, sans prestataire externe).
--
-- Table `signatures` : une signature par document en V1 (attestation ou
-- procès-verbal), tracé normalisé 0..1 en JSONB et image PNG figée en
-- BYTEA, avec son empreinte SHA-256. Le nom et la fonction sont figés à
-- la signature : ils survivent à un changement de nom ou de rôle.
-- Le PNG n'est jamais décodé côté serveur : le PDF redessine le tracé
-- depuis les points, l'image sert de preuve consultable par l'API.
-- Idempotente (IF NOT EXISTS) ; l'index unique est créé APRÈS la table,
-- comme l'exige le garde-fou de test-migrations-t13.mjs (bug 028).
CREATE TABLE IF NOT EXISTS signatures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    document_type       TEXT NOT NULL CHECK (document_type IN ('attestation', 'proces_verbal')),
    document_id         UUID NOT NULL,
    signataire_user_id  UUID REFERENCES users (id) ON DELETE SET NULL,
    signataire_nom      TEXT NOT NULL,
    signataire_fonction TEXT NOT NULL,
    points              JSONB NOT NULL DEFAULT '[]'::jsonb,
    image_png           BYTEA NOT NULL,
    empreinte_sha256     TEXT NOT NULL,
    methode             TEXT NOT NULL DEFAULT 'dessin' CHECK (methode = 'dessin'),
    date_signature      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_signatures_document_unique
    ON signatures (church_id, document_type, document_id);
CREATE INDEX IF NOT EXISTS idx_signatures_signataire
    ON signatures (church_id, signataire_user_id);
