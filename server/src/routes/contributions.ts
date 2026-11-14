import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { READ_ALL } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { genererRecuPdf } from "../pdf.js";
import { verifierCampagneAffectation } from "./campagnes.js";

/**
 * Finances de l'église de la session (dons sur le compte de CHAQUE église,
 * jamais centralisés — décision de Bouf). Enregistrement manuel avec
 * référence Mobile Money en MVP ; confirmation automatique par webhook
 * (Wave / Orange Money / MTN) depuis la tranche T8 — voir
 * routes/webhooks_paiements.ts, qui réutilise confirmerContribution
 * ci-dessous (mêmes effets : reçu numéroté, caisse, audit).
 * GET   /contributions      — liste + filtres + totaux par type (confirmées).
 * GET   /contributions/:id  — une contribution, avec son numéro de reçu.
 * POST  /contributions      — enregistrer (admin_eglise, tresorier).
 * PATCH /contributions/:id/statut — confirmer / annuler (voir ci-dessous).
 * GET   /contributions/:id/recu.pdf — reçu numéroté en PDF (confirmée).
 * GET   /cotisations/config — montant fixé par l'église.
 * POST  /cotisations/config — fixer le montant (admin_eglise, tresorier).
 * GET   /cotisations/suivi — payé et reste par membre, pour une période.
 * Le rôle « membre » simple n'a PAS accès aux finances (403), sauf à son
 * propre reçu et à sa propre ligne de cotisation.
 *
 * Double validation verrouillée (tranche T7, Lot B), dans la continuité
 * de la validation en deux temps des dépenses : le trésorier SAISIT
 * (POST, statut en_attente) ; seul le pasteur (admin_eglise) VALIDE
 * (PATCH {confirme}) — le trésorier qui confirme reçoit 403. À la
 * validation, la contribution est verrouillée (statut terminal, plus
 * d'annulation), un reçu numéroté est émis (REC-AAAA-NNNN, par église
 * et par année) et la caisse est écrite automatiquement (une seule
 * source de vérité : caisse_mouvements). L'annulation n'est possible
 * que depuis en_attente, par l'admin ou le trésorier.
 */

const TYPES_CONTRIBUTION = ["dime", "offrande", "don", "depense", "cotisation"] as const;

const LIBELLES_TYPE: Record<string, string> = {
  dime: "Dîme",
  offrande: "Offrande",
  don: "Don",
  depense: "Dépense",
  cotisation: "Cotisation",
};

const LIBELLES_PAIEMENT: Record<string, string> = {
  wave: "Wave",
  orange_money: "Orange Money",
  mtn_momo: "MTN Mobile Money",
  especes: "Espèces",
  virement: "Virement",
};

/** Prochain numéro de reçu REC-AAAA-NNNN pour une église et une année
 *  (même structure que DEP- et ATT- : MAX + 1, index unique en garde). */
async function prochainNumeroRecu(
  client: Pool | PoolClient,
  churchId: string,
  annee: number,
): Promise<string> {
  const { rows } = await client.query(
    `SELECT coalesce(max(CAST(substr(recu_numero, 10) AS int)), 0)::int AS n
       FROM contributions WHERE church_id = $1 AND recu_numero LIKE $2`,
    [churchId, `REC-${annee}-%`],
  );
  return `REC-${annee}-${String(rows[0].n + 1).padStart(4, "0")}`;
}

/** Résultat d'une tentative de confirmation. */
export type ConfirmationContribution =
  | {
      ok: true;
      contribution: {
        id: string;
        type: string;
        amount_fcfa: number;
        status: string;
        recu_numero: string | null;
      };
    }
  | { ok: false; raison: "introuvable" };

/**
 * Confirme une contribution en_attente — mêmes effets que la confirmation
 * manuelle du pasteur (tranche T7) : reçu numéroté REC-AAAA-NNNN,
 * écriture automatique en caisse (source 'contribution', index
 * anti-doublon) et verrouillage (statut terminal).
 *
 * À exécuter DANS une transaction (client passé par l'appelant), la ligne
 * étant verrouillée FOR UPDATE : une contribution déjà confirmée ou
 * annulée retourne { ok: false } — jamais de double effet, même si le
 * fournisseur renotifie la même notification.
 *
 * `validePar` : id de l'utilisateur qui valide, ou null quand la
 * confirmation vient d'un webhook (aucun humain ne valide — le reçu
 * n'est pas « validé par » quelqu'un, et l'action d'audit est
 * `contribution.confirmee_webhook`).
 */
export async function confirmerContribution(
  client: PoolClient,
  churchId: string,
  contributionId: string,
  opts: { validePar: string | null; actionAudit?: string },
): Promise<ConfirmationContribution> {
  const { rows: existantes } = await client.query(
    `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.status,
            m.full_name AS membre_nom
       FROM contributions c
       LEFT JOIN members m ON m.id = c.member_id
      WHERE c.id = $1 AND c.church_id = $2
      FOR UPDATE OF c`,
    [contributionId, churchId],
  );
  if (existantes.length === 0 || existantes[0].status !== "en_attente") {
    return { ok: false, raison: "introuvable" };
  }
  const contribution = existantes[0];
  const annee = new Date().getFullYear();
  const recuNumero = await prochainNumeroRecu(client, churchId, annee);
  const { rows } = await client.query(
    `UPDATE contributions
        SET status = 'confirme', recu_numero = $3, recu_emis_le = now(),
            valide_par = $4
      WHERE id = $1 AND church_id = $2
      RETURNING id, type, amount_fcfa, status, recu_numero, promesse_id`,
    [contributionId, churchId, recuNumero, opts.validePar],
  );
  // T12 (US4) : la confirmation d'un versement marque son échéance reçue.
  if (rows[0].promesse_id) {
    await client.query(
      `UPDATE echeances_promesses SET statut = 'recu'
        WHERE contribution_id = $1 AND statut = 'en_attente'`,
      [contributionId],
    );
    const { rows: reste } = await client.query(
      `SELECT count(*)::text AS n FROM echeances_promesses
        WHERE promesse_id = $1 AND statut = 'en_attente'`,
      [rows[0].promesse_id],
    );
    if (Number(reste[0]?.n ?? 0) === 0) {
      await client.query(
        `UPDATE promesses SET statut = 'terminee' WHERE id = $1 AND statut = 'en_cours'`,
        [rows[0].promesse_id],
      );
    }
  }
  const libelle = LIBELLES_TYPE[contribution.type as string] ?? contribution.type;
  await client.query(
    `INSERT INTO caisse_mouvements
       (church_id, type, montant_fcfa, motif, reference, source, source_id, canal)
     VALUES ($1, 'entree', $2, $3, $4, 'contribution', $5, $6)`,
    [
      churchId,
      contribution.amount_fcfa,
      `Contribution ${libelle} — ${contribution.membre_nom ?? "donateur non identifié"} — reçu ${recuNumero}`,
      recuNumero,
      contribution.id,
      contribution.payment_method,
    ],
  );
  await auditLog(client, {
    churchId,
    userId: opts.validePar,
    action: opts.actionAudit ?? "contribution.confirmee",
    details: {
      contribution_id: rows[0].id,
      type: rows[0].type,
      amount_fcfa: rows[0].amount_fcfa,
      recu_numero: recuNumero,
    },
  });
  return { ok: true, contribution: rows[0] };
}

/** Fiche membre liée à un compte (pour le « membre lui-même »). */
async function membreLie(db: Pool, userId: string): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [userId],
  );
  return rows[0]?.member_id ?? null;
}

/** AAAA-MM-JJ ou ISO → JJ/MM/AAAA, sans passer par Date (pas de décalage). */
function formaterDateCourte(valeur: string): string {
  const iso = String(valeur).slice(0, 10);
  const [a, m, j] = iso.split("-");
  return `${j}/${m}/${a}`;
}

const createSchema = z.object({
  type: z.enum(TYPES_CONTRIBUTION),
  amount_fcfa: z.number().int().positive().max(100_000_000),
  payment_method: z.enum(["wave", "orange_money", "mtn_momo", "especes", "virement"]),
  payment_ref: z.string().min(1).max(120).optional(),
  member_id: z.string().uuid().optional(),
  campagne_id: z.string().uuid().optional(),
  note: z.string().max(500).optional(),
});

const statutSchema = z.object({
  status: z.enum(["confirme", "annule"]),
});

const listQuerySchema = z.object({
  type: z.enum(TYPES_CONTRIBUTION).optional(),
  status: z.enum(["en_attente", "confirme", "annule"]).optional(),
  member_id: z.string().uuid().optional(),
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte"];
const WRITE_ROLES = ["admin_eglise", "tresorier"];

export function registerContributionsRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/contributions",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      const parsed = listQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Paramètres de recherche invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { type, status, member_id, from, to, limit, offset } = parsed.data;
      try {
        const conditions = [`c.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (type) {
          values.push(type);
          conditions.push(`c.type = $${values.length}`);
        }
        if (status) {
          values.push(status);
          conditions.push(`c.status = $${values.length}`);
        }
        if (member_id) {
          values.push(member_id);
          conditions.push(`c.member_id = $${values.length}`);
        }
        if (from) {
          values.push(from);
          conditions.push(`c.created_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(`c.created_at < ($${values.length}::date + interval '1 day')`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;

        const { rows } = await db.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.payment_ref,
                  c.status, c.note, c.created_at, c.campagne_id,
                  c.recu_numero, c.recu_emis_le,
                  c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
             ${where}
            ORDER BY c.created_at DESC
            LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
          [...values, limit, offset],
        );
        // Totaux par type, contributions confirmées uniquement.
        const { rows: totauxRows } = await db.query(
          `SELECT c.type, coalesce(sum(c.amount_fcfa), 0)::int AS total_fcfa,
                  count(*)::int AS nombre
             FROM contributions c ${where} AND c.status = 'confirme'
            GROUP BY c.type`,
          values,
        );
        const totaux: Record<string, { total_fcfa: number; nombre: number }> = {};
        for (const t of totauxRows) totaux[t.type as string] = { total_fcfa: t.total_fcfa, nombre: t.nombre };
        // « Dépenses confirmées » : contributions de type dépense + dépenses
        // du module Budget & caisse (hors refusées, mêmes bornes de dates
        // quand elles sont demandées). Sans ça, le tableau de bord affichait
        // 0 alors que Budget & caisse contenait des dépenses. Pas de fusion
        // quand on filtre par membre (les dépenses n'ont pas de membre).
        if (!member_id && (!type || type === "depense")) {
          const depValues: unknown[] = [req.session.churchId];
          const depConditions = [`church_id = $1`, `statut <> 'refusee'`];
          if (from) {
            depValues.push(from);
            depConditions.push(`date_depense >= $${depValues.length}::date`);
          }
          if (to) {
            depValues.push(to);
            depConditions.push(
              `date_depense < ($${depValues.length}::date + interval '1 day')`,
            );
          }
          const { rows: depRows } = await db.query(
            `SELECT coalesce(sum(montant_fcfa), 0)::int AS total_fcfa,
                    count(*)::int AS nombre
               FROM depenses WHERE ${depConditions.join(" AND ")}`,
            depValues,
          );
          const precedent = totaux["depense"] ?? { total_fcfa: 0, nombre: 0 };
          totaux["depense"] = {
            total_fcfa: precedent.total_fcfa + Number(depRows[0].total_fcfa),
            nombre: precedent.nombre + Number(depRows[0].nombre),
          };
        }
        return reply.send({ contributions: rows, totaux });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/contributions/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.payment_ref,
                  c.status, c.note, c.created_at, c.recu_numero, c.recu_emis_le,
                  c.valide_par, c.campagne_id, ca.nom AS campagne_nom,
                  c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule,
                  ch.name AS eglise_nom, ch.code AS eglise_code
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
             LEFT JOIN campagnes ca ON ca.id = c.campagne_id
             JOIN churches ch ON ch.id = c.church_id
            WHERE c.id = $1 AND c.church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Contribution introuvable." });
        }
        // Le reçu numéroté est émis à la validation (PDF : /recu.pdf) ;
        // la contribution elle-même porte son numéro (recu_numero).
        return reply.send({ recu: rows[0] });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/contributions",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de la contribution invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const data = parsed.data;
      try {
        // Une cotisation est le paiement d'un membre : pas de cotisation
        // anonyme (le suivi payé / reste est par membre).
        if (data.type === "cotisation" && !data.member_id) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Une cotisation est liée à un membre.",
          });
        }
        // Le membre éventuel doit appartenir à mon église.
        if (data.member_id) {
          const member = await db.query(
            `SELECT id FROM members WHERE id = $1 AND church_id = $2`,
            [data.member_id, req.session.churchId],
          );
          if (member.rowCount === 0) {
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Ce membre n'appartient pas à votre église.",
            });
          }
        }
        // Une contribution affectée à une campagne : campagne active de
        // mon église, jamais une dépense, jamais une autre église.
        if (data.campagne_id) {
          const erreur = await verifierCampagneAffectation(
            db, req.session.churchId, data.campagne_id, data.type,
          );
          if (erreur) {
            return reply.code(erreur.code).send({ error: erreur.error, message: erreur.message });
          }
        }
        const { rows } = await db.query(
          `INSERT INTO contributions
             (church_id, member_id, type, amount_fcfa, payment_method, payment_ref, status, received_by, note, campagne_id)
           VALUES ($1, $2, $3, $4, $5, $6, 'en_attente', $7, $8, $9)
           RETURNING id, church_id, member_id, type, amount_fcfa, payment_method,
                     payment_ref, status, note, campagne_id, created_at`,
          [
            req.session.churchId,
            data.member_id ?? null,
            data.type,
            data.amount_fcfa,
            data.payment_method,
            data.payment_ref ?? null,
            req.session.userId,
            data.note ?? null,
            data.campagne_id ?? null,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "contribution.enregistree",
          details: { contribution_id: rows[0].id, type: data.type, amount_fcfa: data.amount_fcfa },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Double validation verrouillée (tranche T7) : le trésorier saisit,
  //    seul le pasteur (admin_eglise) confirme. À la confirmation :
  //    reçu numéroté émis + caisse écrite automatiquement, en transaction
  //    (tout ou rien). Une contribution confirmée est verrouillée : plus
  //    d'annulation possible (409). -----------------------------------------
  app.patch(
    "/contributions/:id/statut",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = statutSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Statut invalide (confirme ou annule).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      // Seul le pasteur valide : le trésorier enregistre, il ne confirme pas.
      if (parsed.data.status === "confirme" && req.session.role !== "admin_eglise") {
        return reply.code(403).send({
          error: "forbidden",
          message: "Seul le pasteur (admin de l'église) valide une contribution. Le trésorier l'enregistre.",
        });
      }
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows: existantes } = await client.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.status,
                  m.full_name AS membre_nom
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
            WHERE c.id = $1 AND c.church_id = $2
            FOR UPDATE OF c`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (existantes.length === 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "conflict",
            message: "Contribution introuvable, ou déjà confirmée / annulée.",
          });
        }
        const contribution = existantes[0];
        if (contribution.status !== "en_attente") {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "conflict",
            message: "Contribution introuvable, ou déjà confirmée / annulée.",
          });
        }
        if (parsed.data.status === "confirme") {
          // Mêmes effets que la confirmation manuelle (reçu + caisse +
          // audit) — voir confirmerContribution, partagée avec les
          // webhooks (tranche T8). Le SELECT FOR UPDATE ci-dessus a déjà
          // vérifié que la contribution est en_attente.
          const confirme = await confirmerContribution(
            client,
            req.session.churchId,
            (req.params as { id: string }).id,
            { validePar: req.session.userId },
          );
          if (!confirme.ok) {
            await client.query("ROLLBACK");
            return reply.code(409).send({
              error: "conflict",
              message: "Contribution introuvable, ou déjà confirmée / annulée.",
            });
          }
          await client.query("COMMIT");
          return reply.send(confirme.contribution);
        }
        const { rows } = await client.query(
          `UPDATE contributions SET status = 'annule'
            WHERE id = $1 AND church_id = $2
            RETURNING id, type, amount_fcfa, status, recu_numero`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "contribution.annulee",
          details: { contribution_id: rows[0].id, type: rows[0].type, amount_fcfa: rows[0].amount_fcfa },
        });
        await client.query("COMMIT");
        return reply.send(rows[0]);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  app.patch(
    "/contributions/:id/campagne",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      // Affecter une contribution confirmée à une campagne active de son
      // église, ou la retirer (campagne_id null) vers le fonds général.
      const parsed = z.object({ campagne_id: z.string().uuid().nullable() }).safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Campagne invalide.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows: existantes } = await db.query(
          `SELECT type FROM contributions WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (existantes.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Contribution introuvable." });
        }
        if (parsed.data.campagne_id) {
          const erreur = await verifierCampagneAffectation(
            db, req.session.churchId, parsed.data.campagne_id, existantes[0].type as string,
          );
          if (erreur) {
            return reply.code(erreur.code).send({ error: erreur.error, message: erreur.message });
          }
        }
        const { rows } = await db.query(
          `UPDATE contributions SET campagne_id = $3
            WHERE id = $1 AND church_id = $2
            RETURNING id, type, amount_fcfa, status, campagne_id`,
          [(req.params as { id: string }).id, req.session.churchId, parsed.data.campagne_id],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "contribution.campagne_affectee",
          details: { contribution_id: rows[0].id, campagne_id: parsed.data.campagne_id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Reçu numéroté en PDF (tranche T7) : contribution confirmée
  //    seulement. Admin, trésorier et responsable de culte ; un membre
  //    ne télécharge que son propre reçu (même règle que les attestations).
  app.get(
    "/contributions/:id/recu.pdf",
    { preHandler: [requireAuth(db)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.status,
                  c.recu_numero, c.recu_emis_le, c.created_at, c.campagne_id,
                  ca.nom AS campagne_nom,
                  c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule,
                  ch.name AS eglise_nom, ch.code AS eglise_code
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
             LEFT JOIN campagnes ca ON ca.id = c.campagne_id
             JOIN churches ch ON ch.id = c.church_id
            WHERE c.id = $1 AND c.church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Contribution introuvable." });
        }
        const contribution = rows[0];
        const role = req.session.role;
        if (role === "membre") {
          const memberId = await membreLie(db, req.session.userId);
          if (!memberId || memberId !== contribution.member_id) {
            return reply.code(403).send({
              error: "forbidden",
              message: "Ce reçu n'est pas le vôtre.",
            });
          }
        } else if (!["admin_eglise", "tresorier", "responsable_culte"].includes(role)) {
          return reply.code(403).send({ error: "forbidden", message: "Accès refusé." });
        }
        if (contribution.status !== "confirme" || !contribution.recu_numero) {
          return reply.code(409).send({
            error: "conflict",
            message: "Reçu non émis : la contribution n'est pas confirmée.",
          });
        }
        const pdf = genererRecuPdf({
          egliseNom: contribution.eglise_nom,
          egliseCode: contribution.eglise_code,
          numero: contribution.recu_numero,
          dateEmission: formaterDateCourte(String(contribution.recu_emis_le)),
          membreNom: contribution.membre_nom ?? null,
          membreMatricule: contribution.membre_matricule ?? null,
          typeLibelle: LIBELLES_TYPE[contribution.type as string] ?? contribution.type,
          montantFcfa: Number(contribution.amount_fcfa),
          paiementLibelle: LIBELLES_PAIEMENT[contribution.payment_method as string] ?? contribution.payment_method,
          dateContribution: formaterDateCourte(String(contribution.created_at)),
          campagneNom: contribution.campagne_nom ?? null,
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "contribution.recu_pdf",
          details: { contribution_id: contribution.id, recu_numero: contribution.recu_numero },
        });
        reply
          .type("application/pdf")
          .header(
            "Content-Disposition",
            `attachment; filename="recu-${contribution.recu_numero}.pdf"`,
          )
          .send(pdf);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Cotisations : montant fixé par l'église (tranche T7). -----------------
  const configCotisationSchema = z.object({
    montant_fcfa: z.number().int().positive().max(100_000_000),
    periodicite: z.enum(["mensuelle", "annuelle"]).optional(),
    actif: z.boolean().optional(),
  });

  app.get(
    "/cotisations/config",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT church_id, montant_fcfa, periodicite, actif, created_at, updated_at
             FROM cotisations_config WHERE church_id = $1`,
          [req.session.churchId],
        );
        return reply.send(rows[0] ?? null);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/cotisations/config",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = configCotisationSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Montant de cotisation invalide.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { montant_fcfa, periodicite, actif } = parsed.data;
      try {
        const { rows } = await db.query(
          `INSERT INTO cotisations_config (church_id, montant_fcfa, periodicite, actif, updated_at)
           VALUES ($1, $2, $3, $4, now())
           ON CONFLICT (church_id)
           DO UPDATE SET montant_fcfa = EXCLUDED.montant_fcfa,
                         periodicite = COALESCE(EXCLUDED.periodicite, cotisations_config.periodicite),
                         actif = COALESCE(EXCLUDED.actif, cotisations_config.actif),
                         updated_at = now()
           RETURNING church_id, montant_fcfa, periodicite, actif, created_at, updated_at`,
          [
            req.session.churchId,
            montant_fcfa,
            periodicite ?? "mensuelle",
            actif ?? true,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "cotisation.config_modifiee",
          details: { montant_fcfa, periodicite: rows[0].periodicite, actif: rows[0].actif },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Cotisations : suivi payé / reste par membre (tranche T7). -------------
  //    Le suivi est CALCULÉ depuis les contributions confirmées de type
  //    'cotisation' sur la période, jamais stocké : pas de double
  //    comptabilité. Le montant dû est le montant configuré au moment de
  //    la lecture (un changement de montant ne réécrit pas le passé).
  //    Période mensuelle (AAAA-MM) pour une cotisation mensuelle, annuelle
  //    (AAAA) pour une cotisation annuelle.
  const suiviCotisationsQuerySchema = z.object({
    periode: z
      .string()
      .regex(/^\d{4}(-\d{2})?$/, "Période au format AAAA ou AAAA-MM.")
      .optional(),
  });

  app.get(
    "/cotisations/suivi",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = suiviCotisationsQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Période invalide (AAAA ou AAAA-MM).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows: configs } = await db.query(
          `SELECT montant_fcfa, periodicite, actif FROM cotisations_config WHERE church_id = $1`,
          [req.session.churchId],
        );
        const config = configs[0] ?? null;
        const maintenant = new Date();
        const periodeDemandee = parsed.data.periode;
        // Période par défaut : mois en cours (mensuelle) ou année en cours.
        const periode = periodeDemandee
          ?? (config?.periodicite === "annuelle"
            ? String(maintenant.getFullYear())
            : `${maintenant.getFullYear()}-${String(maintenant.getMonth() + 1).padStart(2, "0")}`);
        if (!config || !config.actif) {
          return reply.send({
            config,
            config_absente: !config,
            periode,
            membres: [],
            totaux: { total_du_fcfa: 0, total_paye_fcfa: 0, total_reste_fcfa: 0, membres_payes: 0, membres_total: 0 },
          });
        }
        const mensuelle = config.periodicite === "mensuelle";
        const estMois = /^\d{4}-\d{2}$/.test(periode);
        if (mensuelle && !estMois) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Cotisation mensuelle : période au format AAAA-MM.",
          });
        }
        if (!mensuelle && estMois) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Cotisation annuelle : période au format AAAA.",
          });
        }
        const mois = estMois ? Number(periode.slice(5, 7)) : null;
        if (mois !== null && (mois < 1 || mois > 12)) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Mois invalide (01 à 12).",
          });
        }
        const annee = Number(periode.slice(0, 4));
        const debut = estMois ? `${periode}-01` : `${annee}-01-01`;
        const fin = estMois
          ? (mois === 12 ? `${annee + 1}-01-01` : `${annee}-${String((mois as number) + 1).padStart(2, "0")}-01`)
          : `${annee + 1}-01-01`;
        // Un membre ne voit que sa propre ligne.
        let membreId: string | null = null;
        if (req.session.role === "membre") {
          membreId = await membreLie(db, req.session.userId);
          if (!membreId) {
            return reply.send({
              config,
              config_absente: false,
              periode,
              membres: [],
              totaux: { total_du_fcfa: 0, total_paye_fcfa: 0, total_reste_fcfa: 0, membres_payes: 0, membres_total: 0 },
            });
          }
        }
        const values: unknown[] = [req.session.churchId, debut, fin];
        let filtreMembre = "";
        if (membreId) {
          values.push(membreId);
          filtreMembre = ` AND m.id = $${values.length}`;
        }
        const { rows } = await db.query(
          `SELECT m.id AS member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule,
                  coalesce(sum(c.amount_fcfa) FILTER (WHERE c.status = 'confirme'), 0)::int AS montant_paye_fcfa
             FROM members m
             LEFT JOIN contributions c
               ON c.member_id = m.id AND c.type = 'cotisation'
              AND c.created_at >= $2::date AND c.created_at < $3::date
            WHERE m.church_id = $1 AND m.status = 'actif'${filtreMembre}
            GROUP BY m.id, m.full_name, m.matricule
            ORDER BY m.full_name ASC`,
          values,
        );
        const membres = rows.map((r) => {
          const du = Number(config.montant_fcfa);
          const paye = Number(r.montant_paye_fcfa);
          const reste = Math.max(0, du - paye);
          return {
            member_id: r.member_id,
            membre_nom: r.membre_nom,
            membre_matricule: r.membre_matricule,
            montant_du_fcfa: du,
            montant_paye_fcfa: paye,
            reste_fcfa: reste,
            surplus_fcfa: Math.max(0, paye - du),
            statut: paye >= du ? "payee" : paye > 0 ? "partielle" : "impayee",
          };
        });
        const totaux = {
          total_du_fcfa: membres.reduce((s, m) => s + m.montant_du_fcfa, 0),
          total_paye_fcfa: membres.reduce((s, m) => s + m.montant_paye_fcfa, 0),
          total_reste_fcfa: membres.reduce((s, m) => s + m.reste_fcfa, 0),
          membres_payes: membres.filter((m) => m.statut === "payee").length,
          membres_total: membres.length,
        };
        return reply.send({ config, config_absente: false, periode, membres, totaux });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
