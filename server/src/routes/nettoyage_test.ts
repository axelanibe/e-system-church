import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Nettoyage des données TEST (audit fonctionnel du 11 novembre 2026).
 *
 * L'application n'offre aucune suppression pour une contribution
 * confirmée, une dépense confirmée, une campagne, une attestation, une
 * demande de transfert acceptée ou une sous-église, et la suppression
 * d'un membre échoue tant qu'un transfert le référence
 * (`transferts_membre.membre_id` en ON DELETE RESTRICT). Cette route
 * supprime ces données TEST dans l'ordre qui lève les blocages, sans
 * jamais toucher autre chose.
 *
 * POST /admin/nettoyage-test — admin_eglise seulement.
 *   Corps : { confirmer?: boolean }.
 *   Sans `confirmer: true` : aperçu seulement, rien n'est supprimé.
 *   Avec `confirmer: true` : suppression, dans une seule transaction.
 *
 * Périmètre : l'église de la session et ses annexes directes
 * (parent_church_id = église de la session). Une donnée d'une autre
 * église, même marquée TEST, n'est jamais touchée.
 *
 * Garde-fou : chaque élément est sélectionné ET supprimé uniquement
 * par son marqueur TEST (nom commençant par TEST, référence TEST-…,
 * note contenant TEST, attestation d'un membre TEST, sous-église TEST
 * rattachée à la session). Chaque DELETE porte sa condition marqueur
 * et le nombre de lignes supprimées est vérifié : si une ligne ne
 * porte plus son marqueur, toute la transaction est annulée et rien
 * n'est supprimé. Chaque suppression est journalisée dans audit_logs.
 *
 * Ordre de suppression (contraintes de clés) : transferts d'abord
 * (RESTRICT sur le membre et sur les églises), puis attestations
 * (elles disparaîtraient en cascade à la suppression du membre, sans
 * journal explicite : on les supprime avant lui), puis contributions,
 * campagnes, membres, et enfin les sous-églises TEST.
 */
type ElementNettoyage = {
  type: "transfert" | "membre" | "contribution" | "campagne" | "attestation" | "eglise";
  id: string;
  label: string;
};

const LIBELLES_TYPE: Record<ElementNettoyage["type"], string> = {
  transfert: "Transfert",
  membre: "Membre",
  contribution: "Contribution",
  campagne: "Campagne",
  attestation: "Attestation",
  eglise: "Sous-église",
};

async function collecterTest(
  client: Pool | PoolClient,
  egliseIds: string[],
  egliseSession: string,
): Promise<ElementNettoyage[]> {
  const elements: ElementNettoyage[] = [];

  const membres = await client.query<{ id: string; matricule: string; full_name: string }>(
    `SELECT id, matricule, full_name FROM members
      WHERE church_id = ANY($1) AND full_name ILIKE 'TEST%'`,
    [egliseIds],
  );
  const membreIds = membres.rows.map((m) => m.id);

  const transferts = await client.query<{ id: string; membre_nom: string; ancien_matricule: string; nouveau_matricule: string | null; status: string }>(
    `SELECT id, membre_nom, ancien_matricule, nouveau_matricule, status
       FROM transferts_membre
      WHERE (membre_id = ANY($1) OR membre_nom ILIKE 'TEST%')
        AND (eglise_depart_id = ANY($2) OR eglise_arrivee_id = ANY($2))`,
    [membreIds.length > 0 ? membreIds : ["00000000-0000-0000-0000-000000000000"], egliseIds],
  );
  for (const t of transferts.rows) {
    elements.push({
      type: "transfert",
      id: t.id,
      label: `Transfert ${t.membre_nom} (${t.ancien_matricule} → ${t.nouveau_matricule ?? "—"}, ${t.status})`,
    });
  }

  const contributions = await client.query<{ id: string; type: string; amount_fcfa: number; payment_ref: string | null; note: string | null }>(
    `SELECT id, type, amount_fcfa, payment_ref, note FROM contributions
      WHERE church_id = ANY($1)
        AND (payment_ref ILIKE 'TEST%' OR note ILIKE '%TEST%')`,
    [egliseIds],
  );
  for (const c of contributions.rows) {
    const nomType = c.type === "depense" ? "Dépense" : c.type === "dime" ? "Dîme" : c.type === "offrande" ? "Offrande" : "Don";
    elements.push({
      type: "contribution",
      id: c.id,
      label: `${nomType} ${c.amount_fcfa.toLocaleString("fr-FR")} FCFA (${c.payment_ref ?? "sans référence"})`,
    });
  }

  const campagnes = await client.query<{ id: string; nom: string; objectif_fcfa: number }>(
    `SELECT id, nom, objectif_fcfa FROM campagnes
      WHERE church_id = ANY($1) AND nom ILIKE 'TEST%'`,
    [egliseIds],
  );
  for (const c of campagnes.rows) {
    elements.push({
      type: "campagne",
      id: c.id,
      label: `Campagne ${c.nom} (objectif ${c.objectif_fcfa.toLocaleString("fr-FR")} FCFA)`,
    });
  }

  if (membreIds.length > 0) {
    const attestations = await client.query<{ id: string; annee: number; numero: string; total_fcfa: number }>(
      `SELECT id, annee, numero, total_fcfa FROM attestations
        WHERE church_id = ANY($1) AND member_id = ANY($2)`,
      [egliseIds, membreIds],
    );
    for (const a of attestations.rows) {
      elements.push({
        type: "attestation",
        id: a.id,
        label: `Attestation ${a.numero} (${a.annee}, ${a.total_fcfa.toLocaleString("fr-FR")} FCFA)`,
      });
    }
  }

  for (const m of membres.rows) {
    elements.push({
      type: "membre",
      id: m.id,
      label: `Membre ${m.full_name} (${m.matricule})`,
    });
  }

  const eglises = await client.query<{ id: string; code: string; name: string }>(
    `SELECT id, code, name FROM churches
      WHERE parent_church_id = $1 AND name ILIKE 'TEST%' AND id <> $1`,
    [egliseSession],
  );
  for (const e of eglises.rows) {
    elements.push({
      type: "eglise",
      id: e.id,
      label: `Sous-église ${e.name} (${e.code})`,
    });
  }

  return elements;
}

export function registerNettoyageTestRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/admin/nettoyage-test",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const body = (req.body ?? {}) as { confirmer?: boolean };
      const confirmer = body.confirmer === true;
      const client = await db.connect();
      try {
        // Périmètre : église de la session + annexes directes.
        const annexes = await client.query<{ id: string }>(
          `SELECT id FROM churches WHERE parent_church_id = $1`,
          [req.session.churchId],
        );
        const egliseIds = [req.session.churchId, ...annexes.rows.map((r) => r.id)];

        if (!confirmer) {
          const elements = await collecterTest(client, egliseIds, req.session.churchId);
          return reply.send({ elements, total: elements.length });
        }

        await client.query("BEGIN");
        try {
          const elements = await collecterTest(client, egliseIds, req.session.churchId);
          const parType = (type: ElementNettoyage["type"]) =>
            elements.filter((e) => e.type === type);

          // 1. Transferts (RESTRICT sur le membre et sur les églises).
          for (const e of parType("transfert")) {
            const r = await client.query(
              `DELETE FROM transferts_membre
                WHERE id = $1 AND (membre_nom ILIKE 'TEST%' OR membre_id IN
                  (SELECT id FROM members WHERE full_name ILIKE 'TEST%'))`,
              [e.id],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (transfert)");
          }
          // 2. Attestations, avant les membres : la suppression d'un
          // membre les efface en cascade, sans journal explicite.
          for (const e of parType("attestation")) {
            const r = await client.query(
              `DELETE FROM attestations
                WHERE id = $1 AND member_id IN
                  (SELECT id FROM members WHERE full_name ILIKE 'TEST%')`,
              [e.id],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (attestation)");
          }
          // 3. Contributions et dépenses TEST.
          for (const e of parType("contribution")) {
            const r = await client.query(
              `DELETE FROM contributions
                WHERE id = $1 AND (payment_ref ILIKE 'TEST%' OR note ILIKE '%TEST%')`,
              [e.id],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (contribution)");
          }
          // 4. Campagnes TEST.
          for (const e of parType("campagne")) {
            const r = await client.query(
              `DELETE FROM campagnes WHERE id = $1 AND nom ILIKE 'TEST%'`,
              [e.id],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (campagne)");
          }
          // 5. Membres TEST (le transfert qui les bloquait est supprimé).
          for (const e of parType("membre")) {
            const r = await client.query(
              `DELETE FROM members WHERE id = $1 AND full_name ILIKE 'TEST%'`,
              [e.id],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (membre)");
          }
          // 6. Sous-églises TEST rattachées à l'église de la session.
          for (const e of parType("eglise")) {
            const r = await client.query(
              `DELETE FROM churches
                WHERE id = $1 AND id <> $2 AND parent_church_id = $2 AND name ILIKE 'TEST%'`,
              [e.id, req.session.churchId],
            );
            if ((r.rowCount ?? 0) !== 1) throw new Error("marqueur TEST manquant (église)");
          }

          for (const e of elements) {
            await auditLog(client, {
              churchId: req.session.churchId,
              userId: req.session.userId,
              action: "nettoyage_test.supprime",
              details: { type: e.type, id: e.id, label: e.label },
            });
          }
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "nettoyage_test.execute",
            details: {
              total: elements.length,
              par_type: Object.fromEntries(
                (Object.keys(LIBELLES_TYPE) as ElementNettoyage["type"][]).map((t) => [
                  t,
                  parType(t).length,
                ]),
              ),
            },
          });
          await client.query("COMMIT");
          return reply.send({ ok: true, supprimes: elements, total: elements.length });
        } catch (e) {
          await client.query("ROLLBACK");
          throw e;
        }
      } catch (e) {
        const err = e as { code?: string; message?: string };
        if (err?.message?.startsWith("marqueur TEST manquant")) {
          return reply.code(409).send({
            error: "marqueur_manquant",
            message: "Un élément ne porte plus son marqueur TEST : rien n'a été supprimé.",
          });
        }
        if (err?.code === "23503") {
          // Clé étrangère restante (ex. un transfert non TEST) : rien
          // n'est supprimé, et le message reste simple, en français.
          return reply.code(409).send({
            error: "lien_restant",
            message: "Suppression impossible : un élément TEST est encore lié à une autre donnée. Rien n'a été supprimé.",
          });
        }
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );
}
