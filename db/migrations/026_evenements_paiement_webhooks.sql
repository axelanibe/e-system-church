-- Migration 026 — Événements de paiement et webhooks (tranche T8, Lot B,
-- 13 novembre 2026). Confirmation automatique des contributions en_attente
-- quand Wave / Orange Money / MTN notifie le paiement.
--
-- (1) Table evenements_paiement : journal de CHAQUE notification reçue
--     (fournisseur + identifiant d'événement unique) — c'est elle qui
--     rend la confirmation idempotente : une même notification ne
--     confirme jamais deux fois (le statut 'confirme' bloque tout
--     retraitement, et la confirmation elle-même ne s'applique qu'à une
--     contribution encore 'en_attente', verrouillée FOR UPDATE).
--     On ne stocke JAMAIS la charge utile brute ni aucune signature :
--     seulement l'identifiant d'événement, la référence résolue, le
--     montant, la devise et l'empreinte SHA-256 du corps brut (pour
--     retrouver une notification sans la conserver).
-- (2) Secret de signature du webhook Wave : nouveau champ (facultatif)
--     du fournisseur 'wave' — la signature Wave-Signature (HMAC-SHA256)
--     ne peut être vérifiée que si l'église a saisi ce secret (portail
--     Wave → Webhooks). Sans secret configuré, le webhook Wave est
--     rejeté (401). Le champ est facultatif : la création d'une
--     configuration Wave sans lui reste possible (l'exécution par
--     session de paiement n'en a pas besoin).
-- Idempotente (IF NOT EXISTS, gardes DO, UPDATE conditionnel).
-- Miroir dans db/schema.sql.

-- -- (1) Journal des événements de paiement ----------------------------------
CREATE TABLE IF NOT EXISTS evenements_paiement (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID REFERENCES churches (id) ON DELETE CASCADE,
    fournisseur         TEXT NOT NULL
                        CHECK (fournisseur IN ('wave', 'orange_money', 'mtn_momo')),
    evenement_id        TEXT NOT NULL,
    contribution_id     UUID REFERENCES contributions (id) ON DELETE SET NULL,
    statut              TEXT NOT NULL DEFAULT 'recu'
                        CHECK (statut IN ('recu', 'confirme', 'ignore', 'rejete', 'a_verifier')),
    montant_fcfa        INT,
    devise              TEXT,
    reference_externe   TEXT,
    payload_hash        TEXT,
    recu_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    traite_at           TIMESTAMPTZ,
    UNIQUE (fournisseur, evenement_id)
);
CREATE INDEX IF NOT EXISTS idx_evenements_paiement_church
    ON evenements_paiement (church_id, recu_at DESC);
CREATE INDEX IF NOT EXISTS idx_evenements_paiement_contribution
    ON evenements_paiement (contribution_id);

-- -- (2) Champ « webhook_secret » du fournisseur Wave -------------------------
--     (facultatif : 'optionnel': true — voir routes/paiements.ts).
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM fournisseurs_paiement f,
      jsonb_array_elements(f.champs_requis) c
     WHERE f.code = 'wave' AND c->>'nom' = 'webhook_secret'
  ) THEN
    UPDATE fournisseurs_paiement
       SET champs_requis = champs_requis ||
         '[{"nom":"webhook_secret","label":"Secret de signature du webhook Wave","secret":true,"optionnel":true}]'::jsonb
     WHERE code = 'wave';
  END IF;
END $$;
