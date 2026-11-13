-- Migration 025 — Finances complètes, partie serveur (tranche T7, Lot B,
-- 13 novembre 2026). Une seule source de vérité pour la caisse :
-- les écritures de caisse_mouvements (manuelles + automatiques) ; le
-- solde (GET /finances/caisse) n'est que la somme de cette table.
--
-- (1) Cotisations : nouveau type de contribution 'cotisation'. Le type
--     était un ENUM PostgreSQL (contribution_type) ; ALTER TYPE ADD VALUE
--     est impossible (les migrations tournent en une seule requête,
--     donc en transaction implicite) — la colonne passe en TEXT avec
--     un CHECK. Les sommes de dons (rapports, attestations, plateforme)
--     filtrent déjà explicitement type IN ('dime','offrande','don') :
--     la cotisation n'y entre pas.
-- (2) Reçus numérotés : contributions.recu_numero (REC-AAAA-NNNN, par
--     église et par année), recu_emis_le, valide_par (le pasteur qui a
--     validé). Index unique (church_id, recu_numero) : un numéro n'est
--     émis qu'une fois par église.
-- (3) Caisse automatique : caisse_mouvements.source ('manuelle' par
--     défaut — les saisies de l'appli restent possibles —, 'contribution',
--     'depense'), source_id (la contribution ou la dépense d'origine) et
--     canal (wave, orange_money, mtn_momo, especes, virement, cheque).
--     Index unique (source, source_id) hors manuelles : une contribution
--     confirmée et une dépense payée n'écrivent qu'une seule fois.
-- (4) Comptes bancaires par église (table comptes_bancaires).
-- (5) Cotisations : montant fixé par l'église (table cotisations_config,
--     une ligne par église) ; le suivi payé / reste par membre est calculé
--     depuis les contributions confirmées de type 'cotisation', pas stocké.
-- (6) Budgets par département : table budgets_departements (par mois,
--     comme budgets_mensuels) ; le réalisé vient des dépenses portées par
--     le département (depenses.departement_id, migration 031).
-- (7) Clôture de caisse verrouillée : table clotures_caisse (une ligne
--     par église et par mois) ; une clôture ne se rouvre ni ne se supprime
--     — une erreur se corrige par une écriture dans la période en cours.
-- Idempotente (IF NOT EXISTS, gardes DO). Miroir dans db/schema.sql.

-- -- (1) Type de contribution : ENUM -> TEXT + CHECK ------------------------
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_name = 'contributions' AND column_name = 'type'
       AND udt_name = 'contribution_type'
  ) THEN
    ALTER TABLE contributions ALTER COLUMN type TYPE TEXT USING type::text;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'contributions_type_check'
  ) THEN
    ALTER TABLE contributions
      ADD CONSTRAINT contributions_type_check
      CHECK (type IN ('dime', 'offrande', 'don', 'depense', 'cotisation'));
  END IF;
END $$;
DROP TYPE IF EXISTS contribution_type;

-- -- (2) Reçus numérotés sur contributions ------------------------------------
ALTER TABLE contributions
  ADD COLUMN IF NOT EXISTS recu_numero TEXT,
  ADD COLUMN IF NOT EXISTS recu_emis_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS valide_par UUID REFERENCES users (id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS contributions_recu_numero_unique
    ON contributions (church_id, recu_numero) WHERE recu_numero IS NOT NULL;

-- -- (3) Caisse : origine et canal de chaque écriture -------------------------
ALTER TABLE caisse_mouvements
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manuelle'
    CHECK (source IN ('manuelle', 'contribution', 'depense')),
  ADD COLUMN IF NOT EXISTS source_id UUID,
  ADD COLUMN IF NOT EXISTS canal TEXT
    CHECK (canal IN ('wave', 'orange_money', 'mtn_momo', 'especes', 'virement', 'cheque'));
CREATE UNIQUE INDEX IF NOT EXISTS caisse_mouvements_source_unique
    ON caisse_mouvements (source, source_id) WHERE source <> 'manuelle';
CREATE INDEX IF NOT EXISTS idx_caisse_canal
    ON caisse_mouvements (church_id, canal, created_at);

-- -- (4) Comptes bancaires par église ------------------------------------------
CREATE TABLE IF NOT EXISTS comptes_bancaires (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    banque        TEXT NOT NULL,
    titulaire     TEXT,
    numero_compte TEXT,
    type          TEXT NOT NULL DEFAULT 'banque'
                  CHECK (type IN ('banque', 'mobile_money')),
    devise        TEXT NOT NULL DEFAULT 'FCFA',
    actif         BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_comptes_bancaires_church
    ON comptes_bancaires (church_id, actif);

-- -- (5) Cotisations : montant fixé par l'église -------------------------------
CREATE TABLE IF NOT EXISTS cotisations_config (
    church_id     UUID PRIMARY KEY REFERENCES churches (id) ON DELETE CASCADE,
    montant_fcfa  INT NOT NULL CHECK (montant_fcfa > 0),
    periodicite   TEXT NOT NULL DEFAULT 'mensuelle'
                  CHECK (periodicite IN ('mensuelle', 'annuelle')),
    actif         BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -- (6) Budgets par département (mensuels, comme budgets_mensuels) ------------
CREATE TABLE IF NOT EXISTS budgets_departements (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    departement_id UUID NOT NULL REFERENCES departements (id) ON DELETE CASCADE,
    annee         INT NOT NULL CHECK (annee BETWEEN 2000 AND 2100),
    mois          INT NOT NULL CHECK (mois BETWEEN 1 AND 12),
    montant_prevu INT NOT NULL CHECK (montant_prevu >= 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, departement_id, annee, mois)
);
CREATE INDEX IF NOT EXISTS idx_budgets_departements_church
    ON budgets_departements (church_id, annee, mois);

-- -- (7) Clôtures de caisse verrouillées ---------------------------------------
CREATE TABLE IF NOT EXISTS clotures_caisse (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    periode           TEXT NOT NULL CHECK (periode ~ '^[0-9]{4}-[0-9]{2}$'),
    solde_calcule_fcfa INT NOT NULL,
    solde_compte_fcfa  INT NOT NULL,
    ecart_fcfa         INT NOT NULL,
    commentaire        TEXT,
    cloture_par        UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, periode)
);
CREATE INDEX IF NOT EXISTS idx_clotures_caisse_church
    ON clotures_caisse (church_id, periode DESC);
