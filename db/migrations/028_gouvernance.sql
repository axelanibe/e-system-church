-- 028 — Gouvernance, secrétariat, documents, action sociale (T10,
-- 13 novembre 2026).
-- Mandats et nominations, réunions du conseil, décisions,
-- procès-verbaux, documents (modèles et courriers entrants/sortants),
-- bénéficiaires et suivi des aides. Patrimoine : bâtiments et biens
-- avec valeur, assurance, photo et code d'inventaire ; maintenance
-- reliée aux dépenses (depense_id facultatif).
-- Signataires configurables par église (vides par défaut, décision
-- d'Axel toujours ouverte) : signataire_nominations et
-- signataire_proces_verbaux sur eglise_parametres.
-- Certificat de membre : le type 'membre' rejoint la contrainte des
-- attestations d'événement (baptême et mariage existent déjà).
-- Idempotente : db/schema.sql reprend ce miroir pour les nouvelles
-- bases, et les tests appliquent le schéma puis toutes les migrations.

CREATE TABLE IF NOT EXISTS reunions_conseil (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre         TEXT NOT NULL,
    date_reunion  TIMESTAMPTZ NOT NULL,
    lieu          TEXT,
    ordre_du_jour TEXT,
    statut        TEXT NOT NULL DEFAULT 'prevue'
                  CHECK (statut IN ('prevue','tenue','annulee')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reunions_church ON reunions_conseil (church_id, date_reunion);

CREATE TABLE IF NOT EXISTS decisions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    reunion_id    UUID REFERENCES reunions_conseil (id) ON DELETE SET NULL,
    titre         TEXT NOT NULL,
    description   TEXT,
    date_decision DATE NOT NULL DEFAULT CURRENT_DATE,
    statut        TEXT NOT NULL DEFAULT 'adoptee'
                  CHECK (statut IN ('adoptee','rejetee','reportee')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_decisions_church ON decisions (church_id, reunion_id);

CREATE TABLE IF NOT EXISTS mandats (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    fonction    TEXT NOT NULL,
    date_debut  DATE NOT NULL,
    date_fin    DATE,
    statut      TEXT NOT NULL DEFAULT 'en_cours'
                CHECK (statut IN ('en_cours','termine')),
    decision_id UUID REFERENCES decisions (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mandats_church ON mandats (church_id, statut);

CREATE TABLE IF NOT EXISTS proces_verbaux (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    reunion_id  UUID REFERENCES reunions_conseil (id) ON DELETE SET NULL,
    numero      TEXT,
    contenu     TEXT NOT NULL,
    date_pv     DATE NOT NULL DEFAULT CURRENT_DATE,
    signataire  TEXT,
    statut      TEXT NOT NULL DEFAULT 'brouillon'
                CHECK (statut IN ('brouillon','signe','archive')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_pv_church ON proces_verbaux (church_id, date_pv);

CREATE TABLE IF NOT EXISTS documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre         TEXT NOT NULL,
    categorie     TEXT NOT NULL DEFAULT 'autre'
                  CHECK (categorie IN ('statuts','reglement','decision','courrier','modele','autre')),
    sens          TEXT CHECK (sens IN ('entrant','sortant','interne')),
    reference     TEXT,
    fichier_url   TEXT,
    description   TEXT,
    date_document DATE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_church ON documents (church_id, categorie);

CREATE TABLE IF NOT EXISTS beneficiaires (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    telephone  TEXT,
    adresse    TEXT,
    besoin     TEXT,
    statut     TEXT NOT NULL DEFAULT 'actif' CHECK (statut IN ('actif','clos')),
    member_id  UUID REFERENCES members (id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_beneficiaires_church ON beneficiaires (church_id, statut);

CREATE TABLE IF NOT EXISTS aides (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    beneficiaire_id  UUID NOT NULL REFERENCES beneficiaires (id) ON DELETE CASCADE,
    type_aide        TEXT NOT NULL
                     CHECK (type_aide IN ('vivres','financier','medical','autre')),
    montant_fcfa     INT CHECK (montant_fcfa >= 0),
    date_aide        DATE NOT NULL DEFAULT CURRENT_DATE,
    description      TEXT,
    statut           TEXT NOT NULL DEFAULT 'prevue'
                     CHECK (statut IN ('prevue','versee','annulee')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_aides_church ON aides (church_id, beneficiaire_id);

CREATE TABLE IF NOT EXISTS biens_patrimoine (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom             TEXT NOT NULL,
    categorie       TEXT NOT NULL
                    CHECK (categorie IN ('batiment','terrain','vehicule','equipement','autre')),
    valeur_fcfa     INT CHECK (valeur_fcfa >= 0),
    assurance       TEXT,
    photo_url       TEXT,
    code_inventaire TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, code_inventaire)
);
CREATE INDEX IF NOT EXISTS idx_patrimoine_church ON biens_patrimoine (church_id, categorie);

CREATE TABLE IF NOT EXISTS maintenance_patrimoine (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    bien_id          UUID NOT NULL REFERENCES biens_patrimoine (id) ON DELETE CASCADE,
    date_maintenance DATE NOT NULL DEFAULT CURRENT_DATE,
    description      TEXT NOT NULL,
    cout_fcfa        INT CHECK (cout_fcfa >= 0),
    realise_par      TEXT,
    depense_id       UUID REFERENCES depenses (id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_maintenance_patrimoine_church
    ON maintenance_patrimoine (church_id, bien_id);

-- Signataires configurables par église, vides par défaut.
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS signataire_nominations TEXT;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS signataire_proces_verbaux TEXT;

-- Certificat de membre : le type 'membre' rejoint les attestations
-- d'événement. La contrainte est remplacée, le nom est conservé.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'attestations_type_check') THEN
    ALTER TABLE attestations DROP CONSTRAINT attestations_type_check;
  END IF;
  ALTER TABLE attestations
    ADD CONSTRAINT attestations_type_check
    CHECK (type IN ('don', 'mariage', 'naissance', 'bapteme', 'membre'));
END $$;
