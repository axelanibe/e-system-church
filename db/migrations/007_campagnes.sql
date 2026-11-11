-- 007 — Campagnes de collecte (US2).
-- Idempotente : peut être rejouée sans doublon.
-- - `campagnes` : une campagne par église, nom, objectif FCFA strictement
--   positif, période (date_fin postérieure à date_debut), statut
--   brouillon, active ou cloturee. Clôturer est définitif.
-- - `visible_membres` : l'église choisit si les membres voient le total
--   de la campagne ; faux par défaut (confidentialité par défaut, US17).
-- - `contributions.campagne_id` : affectation d'une contribution confirmée
--   à une campagne active de son église ; sans affectation, la contribution
--   va au fonds général. Une contribution ne peut jamais être affectée à
--   une campagne d'une autre église (vérifié côté serveur, pas seulement
--   par la clé étrangère) ; une dépense ne peut pas être affectée.
-- - Le total collecté est la somme des contributions confirmées affectées,
--   calculée à la lecture, jamais stockée (pas de dérive possible).

CREATE TABLE IF NOT EXISTS campagnes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom             TEXT NOT NULL,
    objectif_fcfa   INT NOT NULL CHECK (objectif_fcfa > 0),
    date_debut      DATE NOT NULL,
    date_fin        DATE NOT NULL,
    statut          TEXT NOT NULL DEFAULT 'brouillon'
                    CHECK (statut IN ('brouillon', 'active', 'cloturee')),
    visible_membres BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (date_fin > date_debut)
);
CREATE INDEX IF NOT EXISTS idx_campagnes_church ON campagnes (church_id, statut);

ALTER TABLE contributions
  ADD COLUMN IF NOT EXISTS campagne_id UUID REFERENCES campagnes (id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_contributions_campagne ON contributions (campagne_id);
