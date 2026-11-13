-- Migration 031 — plan comptable des dépenses (tranche dépenses prévisibles,
-- 12 novembre 2026). Dix catégories comptables globales, identiques pour
-- toutes les églises ; les postes budgétaires se rattachent à une catégorie
-- et portent le marqueur récurrente ou ponctuelle ; les huit postes
-- prévisibles sont créés pour chaque église existante ; chaque dépense
-- porte de nouveaux champs (référence auto, département, mode de paiement,
-- fournisseur, responsables, devise) ; budgets mensuels par poste.
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases (Lot B),
-- comme pour les migrations 019 à 023. Idempotente (IF NOT EXISTS,
-- ON CONFLICT DO NOTHING, WHERE NOT EXISTS).

CREATE TABLE IF NOT EXISTS categories_depenses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE CHECK (code ~ '^[0-9]{2}$'),
    nom         TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO categories_depenses (code, nom, description) VALUES
    ('01', 'Administration', 'Fournitures, télécommunications, frais bancaires'),
    ('02', 'Infrastructures', 'Loyer, eau, électricité, entretien'),
    ('03', 'Culte et spiritualité', 'Louange, communion, matériel de culte'),
    ('04', 'Personnel', 'Salaires, indemnités, formations'),
    ('05', 'Départements', 'Dépenses propres à chaque ministère'),
    ('06', 'Événements', 'Conférences, conventions, retraites'),
    ('07', 'Transport et missions', 'Carburant, déplacements, hébergement'),
    ('08', 'Action sociale', 'Assistance, solidarité, œuvres sociales'),
    ('09', 'Communication et numérique', 'Publicité, logiciels, hébergement web'),
    ('10', 'Imprévus', 'Urgences et dépenses exceptionnelles')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE postes_budgetaires
    ADD COLUMN IF NOT EXISTS categorie_id UUID REFERENCES categories_depenses (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS est_recurrente BOOLEAN NOT NULL DEFAULT false;

-- Huit postes prévisibles pour chaque église existante. Un poste du même
-- nom déjà créé à la main dans une église n'est pas dupliqué.
INSERT INTO postes_budgetaires (church_id, nom, categorie, categorie_id, est_recurrente)
SELECT c.id, v.nom, 'depense', cat.id, v.recurrente
FROM churches c
CROSS JOIN (VALUES
    ('Électricité', '02', true),
    ('Eau', '02', true),
    ('Transports', '07', true),
    ('Cas sociaux', '08', false),
    ('Location de sono', '03', false),
    ('Achat d''équipement', '03', false),
    ('Maintenance', '03', true),
    ('Location d''équipement', '03', false)
) AS v(nom, code, recurrente)
JOIN categories_depenses cat ON cat.code = v.code
ON CONFLICT (church_id, nom) DO NOTHING;

ALTER TABLE depenses
    ADD COLUMN IF NOT EXISTS reference TEXT,
    ADD COLUMN IF NOT EXISTS departement_id UUID REFERENCES departements (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS mode_paiement TEXT CHECK (mode_paiement IN ('especes', 'wave', 'orange_money', 'mtn_money', 'virement', 'cheque')),
    ADD COLUMN IF NOT EXISTS fournisseur_beneficiaire TEXT,
    ADD COLUMN IF NOT EXISTS responsable_depense TEXT,
    ADD COLUMN IF NOT EXISTS responsable_autorisation TEXT,
    ADD COLUMN IF NOT EXISTS devise TEXT NOT NULL DEFAULT 'FCFA';

-- Références des dépenses déjà enregistrées : DEP-AAAA-NNNN par église
-- et par année, dans l'ordre chronologique.
UPDATE depenses d
   SET reference = 'DEP-' || EXTRACT(YEAR FROM d.date_depense)::text || '-' || lpad(s.n::text, 4, '0')
  FROM (
    SELECT id, row_number() OVER (
      PARTITION BY church_id, EXTRACT(YEAR FROM date_depense)
      ORDER BY date_depense, created_at
    ) AS n
    FROM depenses WHERE reference IS NULL
  ) s
 WHERE d.id = s.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_depenses_reference_unique
    ON depenses (church_id, reference);

CREATE TABLE IF NOT EXISTS budgets_mensuels (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    poste_id      UUID NOT NULL REFERENCES postes_budgetaires (id) ON DELETE CASCADE,
    annee         INT NOT NULL CHECK (annee BETWEEN 2000 AND 2100),
    mois          INT NOT NULL CHECK (mois BETWEEN 1 AND 12),
    montant_prevu INT NOT NULL CHECK (montant_prevu >= 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, poste_id, annee, mois)
);
CREATE INDEX IF NOT EXISTS idx_budgets_mensuels_church
    ON budgets_mensuels (church_id, annee, mois);
