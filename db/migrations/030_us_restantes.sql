-- 030 — US4 à US17 restantes (T12, 14 novembre 2026).
-- Promesses de don avec échéancier, dons en nature, fiche visiteur,
-- alertes pour l'église mère, listes configurables par église
-- (rôles, catégories, statuts de membre, départements), lectures
-- sensibles (US17, même définition que la migration 029 de la T11 :
-- la première des deux migrations appliquée crée la table, l'autre
-- est sans effet), consentements WhatsApp et repli SMS, événements
-- de vie masquables, paramètres de transparence, de dîme suggérée
-- et de seuils d'alerte, archivage des départements, lien
-- contribution → promesse.
-- Idempotente : db/schema.sql reprend ce miroir pour les nouvelles
-- bases. Dans ce fichier, chaque CREATE INDEX suit le CREATE TABLE
-- de sa table (leçon de la migration 028 : migrate.ts exécute le
-- fichier seul en production, un index avant sa table échoue).

CREATE TABLE IF NOT EXISTS promesses (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id        UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    montant_total_fcfa INT NOT NULL CHECK (montant_total_fcfa > 0),
    date_debut       DATE NOT NULL DEFAULT CURRENT_DATE,
    nb_versements    INT NOT NULL DEFAULT 1 CHECK (nb_versements BETWEEN 1 AND 120),
    periodicite      TEXT NOT NULL DEFAULT 'mensuelle'
                     CHECK (periodicite IN ('mensuelle')),
    statut           TEXT NOT NULL DEFAULT 'en_cours'
                     CHECK (statut IN ('en_cours', 'terminee', 'annulee')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_promesses_church ON promesses (church_id, member_id, statut);

CREATE TABLE IF NOT EXISTS echeances_promesses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promesse_id     UUID NOT NULL REFERENCES promesses (id) ON DELETE CASCADE,
    date_echeance   DATE NOT NULL,
    montant_fcfa    INT NOT NULL CHECK (montant_fcfa > 0),
    statut          TEXT NOT NULL DEFAULT 'en_attente'
                    CHECK (statut IN ('en_attente', 'recu', 'annulee')),
    contribution_id UUID REFERENCES contributions (id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_echeances_promesse
    ON echeances_promesses (promesse_id, date_echeance);

CREATE TABLE IF NOT EXISTS dons_nature (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id    UUID REFERENCES members (id) ON DELETE SET NULL,
    description  TEXT NOT NULL,
    quantite     INT NOT NULL DEFAULT 1 CHECK (quantite >= 0),
    unite        TEXT,
    type_don     TEXT NOT NULL DEFAULT 'materiel'
                 CHECK (type_don IN ('materiel', 'nourriture', 'temps')),
    heures       NUMERIC(6, 2) CHECK (heures IS NULL OR heures >= 0),
    date_don     DATE NOT NULL DEFAULT CURRENT_DATE,
    anonyme      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dons_nature_church ON dons_nature (church_id, date_don);

CREATE TABLE IF NOT EXISTS visiteurs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom            TEXT NOT NULL,
    date_venue     DATE NOT NULL DEFAULT CURRENT_DATE,
    telephone      TEXT,
    email          TEXT,
    moyen_contact  TEXT,
    statut         TEXT NOT NULL DEFAULT 'nouveau'
                   CHECK (statut IN ('nouveau', 'recontacte', 'devenu_membre')),
    member_id      UUID REFERENCES members (id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_visiteurs_church ON visiteurs (church_id, date_venue);

CREATE TABLE IF NOT EXISTS alertes_mere (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    annexe_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type        TEXT NOT NULL
                CHECK (type IN ('inactive', 'baisse_contributions', 'rapport_manquant')),
    periode     TEXT NOT NULL,
    statut      TEXT NOT NULL DEFAULT 'ouverte'
                CHECK (statut IN ('ouverte', 'traitee')),
    traitee_par UUID REFERENCES users (id) ON DELETE SET NULL,
    traitee_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_alertes_mere_church ON alertes_mere (church_id, statut, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_alertes_mere_une_ouverte
    ON alertes_mere (church_id, annexe_id, type) WHERE statut = 'ouverte';

CREATE TABLE IF NOT EXISTS listes_configurables (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type       TEXT NOT NULL
               CHECK (type IN ('role', 'categorie_depense', 'categorie_recette', 'statut_membre', 'departement')),
    libelle    TEXT NOT NULL,
    niveau     TEXT CHECK (niveau IS NULL OR niveau IN ('admin_eglise', 'tresorier', 'responsable_culte', 'membre')),
    archive    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, type, libelle)
);
CREATE INDEX IF NOT EXISTS idx_listes_configurables_church
    ON listes_configurables (church_id, type, archive);

-- Lectures sensibles (US17) : même définition que la migration 029
-- (T11). La première des deux appliquée crée la table ; l'autre est
-- sans effet (IF NOT EXISTS).
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

-- Versement reçu = contribution confirmée rattachée à la promesse.
ALTER TABLE contributions ADD COLUMN IF NOT EXISTS promesse_id UUID REFERENCES promesses (id) ON DELETE SET NULL;

-- Consentements du membre (WhatsApp US10, repli SMS US16) et
-- événements de vie masqués (US7).
ALTER TABLE members ADD COLUMN IF NOT EXISTS whatsapp_consentement BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS sms_repli_consentement BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS evenements_vie_masques TEXT[] NOT NULL DEFAULT '{}';

-- Paramètres par église : dîme suggérée US14 (NULL = désactivée),
-- transparence financière US8, seuils d'alerte US11.
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS montant_dime_suggere INT CHECK (montant_dime_suggere IS NULL OR montant_dime_suggere >= 0);
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS transparence_visible_membres BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS seuil_inactivite_semaines INT NOT NULL DEFAULT 4 CHECK (seuil_inactivite_semaines > 0);
ALTER TABLE eglise_parametres ADD COLUMN IF NOT EXISTS seuil_baisse_contributions_pct INT NOT NULL DEFAULT 30 CHECK (seuil_baisse_contributions_pct BETWEEN 0 AND 100);

-- Archivage des départements (US13) : un département archivé n'est
-- plus proposé, les affectations existantes restent affichées.
ALTER TABLE departements ADD COLUMN IF NOT EXISTS archive BOOLEAN NOT NULL DEFAULT FALSE;

-- Statuts de membre configurables (US13) : la contrainte figée aux
-- 7 statuts riches est levée ; la validation passe par la liste
-- configurée de l'église (défauts + libellés ajoutés), côté serveur.
-- La définition stockée par PostgreSQL est `statut = ANY (ARRAY[...])`,
-- jamais `statut IN (...)` : les deux formes sont testées.
DO $$ DECLARE c text; BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'membre_statuts'::regclass AND contype = 'c'
              AND (pg_get_constraintdef(oid) LIKE '%statut = ANY%'
                   OR pg_get_constraintdef(oid) LIKE '%statut IN%') LOOP
    EXECUTE 'ALTER TABLE membre_statuts DROP CONSTRAINT ' || quote_ident(c);
  END LOOP;
END $$;
