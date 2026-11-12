-- 015 — Historique des imports de fidèles (tranche A, 11 nov. 2026).
-- Un rapport par import confirmé : fichier, totaux (lignes, créés,
-- ignorés en doublon), erreurs détaillées en JSONB, statut. Les membres
-- créés sont dans `members` ; l'import ne crée jamais de compte
-- utilisateur. Les migrations 012 à 014 sont réservées à d'autres
-- chantiers (Phoenix) ; ce numéro évite toute collision.
CREATE TABLE IF NOT EXISTS imports_membres (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users (id) ON DELETE SET NULL,
    nom_fichier TEXT NOT NULL,
    total_lignes INTEGER NOT NULL DEFAULT 0,
    crees       INTEGER NOT NULL DEFAULT 0,
    ignores     INTEGER NOT NULL DEFAULT 0,
    erreurs     JSONB NOT NULL DEFAULT '[]'::jsonb,
    statut      TEXT NOT NULL DEFAULT 'termine'
                CHECK (statut IN ('termine', 'partiel', 'echoue')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_imports_membres_church
    ON imports_membres (church_id, created_at DESC);
