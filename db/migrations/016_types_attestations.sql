-- Migration 016 — types d'attestations en PDF exclusivement (12 novembre 2026)
-- Tranche B : attestations de mariage, de naissance et de baptême, en plus
-- de l'attestation annuelle de dons US3 (type 'don', inchangée).
-- Une seule colonne ajoutée : `type` ('don' par défaut, pour les lignes
-- existantes). `total_fcfa` et `nb_dons` deviennent nullables : ils ne
-- concernent que les dons, une attestation d'événement n'a ni total ni
-- nombre de dons. L'index partiel d'unicité passe à
-- (church_id, member_id, type, annee) : une seule attestation émise par
-- membre, église, type et année. Le numéro reste unique par église, année
-- et type, préfixes MAR, NAI, BAP (ATT gardé pour les dons), même
-- structure XXX-AAAA-NNNN. Idempotente.
-- 012 à 015 sont réservées aux autres tranches en cours (Lot B).

ALTER TABLE attestations ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'don';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'attestations_type_check') THEN
    ALTER TABLE attestations
      ADD CONSTRAINT attestations_type_check
      CHECK (type IN ('don', 'mariage', 'naissance', 'bapteme'));
  END IF;
END $$;

ALTER TABLE attestations ALTER COLUMN total_fcfa DROP NOT NULL;
ALTER TABLE attestations ALTER COLUMN nb_dons DROP NOT NULL;

-- Les anciennes contraintes CHECK (total_fcfa > 0) et (nb_dons > 0) ont des
-- noms générés : on les retrouve par leur définition et on les remplace
-- par des versions qui acceptent NULL.
DO $$ DECLARE c text; BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'attestations'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) LIKE '%total_fcfa%' LOOP
    EXECUTE 'ALTER TABLE attestations DROP CONSTRAINT ' || quote_ident(c);
  END LOOP;
  ALTER TABLE attestations
    ADD CONSTRAINT attestations_total_fcfa_check
    CHECK (total_fcfa IS NULL OR total_fcfa > 0);
END $$;

DO $$ DECLARE c text; BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'attestations'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) LIKE '%nb_dons%' LOOP
    EXECUTE 'ALTER TABLE attestations DROP CONSTRAINT ' || quote_ident(c);
  END LOOP;
  ALTER TABLE attestations
    ADD CONSTRAINT attestations_nb_dons_check
    CHECK (nb_dons IS NULL OR nb_dons > 0);
END $$;

-- Une seule attestation émise par membre, église, type et année.
DROP INDEX IF EXISTS idx_attestations_une_emise;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attestations_une_emise
    ON attestations (church_id, member_id, type, annee) WHERE statut = 'emise';
