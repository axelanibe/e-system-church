import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { genererAttestationPdf } from "../pdf.js";

/**
 * US3 — Attestations annuelles de dons.
 * Pour une année civile, un PDF par donateur identifié, listant ses dons
 * CONFIRMÉS (dîme, offrande, don ; jamais les dépenses, jamais en attente
 * ou annulés, jamais les dons anonymes sans fiche membre).
 * Attestation figée : le contenu est copié en JSONB à l'émission, le PDF
 * est généré depuis ce contenu, jamais recalculé. Une correction crée une
 * nouvelle attestation (nouveau numéro) et annule l'ancienne ; les deux
 * sont tracées dans audit_logs.
 * En Côte d'Ivoire, l'attestation n'a aucune valeur fiscale : reçu
 * justificatif seulement, le PDF le dit en clair.
 *
 * POST  /attestations/generer   — admin_eglise, tresorier.
 * GET   /attestations           — admin_eglise, tresorier (filtre annee).
 * GET   /attestations/:id/pdf   — admin_eglise, tresorier, ou le membre lui-même.
 * POST  /attestations/:id/corriger — admin_eglise, tresorier (motif obligatoire).
 * GET   /moi/attestations       — membre, ses attestations émises seulement.
 */

const TYPES_DONS = ["dime", "offrande", "don"] as const;
const LIBELLES: Record<string, string> = { dime: "Dîme", offrande: "Offrande", don: "Don" };

const genererSchema = z.object({
  annee: z.number().int().min(2000).max(2100),
});

const corrigerSchema = z.object({
  motif: z.string().min(2).max(500),
});

const listeQuerySchema = z.object({
  annee: z.coerce.number().int().min(2000).max(2100).optional(),
});

const GESTION = ["admin_eglise", "tresorier"] as const;

interface DonFige {
  date: string;
  type: string;
  montant_fcfa: number;
}

interface ContenuAttestation {
  donateur_nom: string;
  donateur_matricule: string | null;
  eglise: { nom: string; code: string; logo_url: string | null };
  dons: DonFige[];
  total_fcfa: number;
  nb_dons: number;
}

async function donsConfirmes(
  client: Pool | PoolClient,
  churchId: string,
  memberId: string,
  annee: number,
): Promise<{ dons: DonFige[]; total: number }> {
  const debut = `${annee}-01-01`;
  const fin = `${annee + 1}-01-01`;
  const { rows } = await client.query(
    `SELECT c.created_at::date AS date, c.type, c.amount_fcfa
       FROM contributions c
      WHERE c.church_id = $1 AND c.member_id = $2 AND c.status = 'confirme'
        AND c.type IN ('dime', 'offrande', 'don')
        AND c.created_at >= $3::date AND c.created_at < $4::date
      ORDER BY c.created_at ASC, c.id ASC`,
    [churchId, memberId, debut, fin],
  );
  const dons: DonFige[] = rows.map((r) => ({
    date: (r.date as Date).toISOString().slice(0, 10),
    type: LIBELLES[r.type as string] ?? (r.type as string),
    montant_fcfa: Number(r.amount_fcfa),
  }));
  return { dons, total: dons.reduce((s, d) => s + d.montant_fcfa, 0) };
}

async function prochainNumero(
  client: Pool | PoolClient,
  churchId: string,
  annee: number,
): Promise<string> {
  const { rows } = await client.query(
    `SELECT coalesce(max(CAST(substr(numero, 10) AS int)), 0)::int AS n
       FROM attestations WHERE church_id = $1 AND annee = $2`,
    [churchId, annee],
  );
  return `ATT-${annee}-${String(rows[0].n + 1).padStart(4, "0")}`;
}

async function membreLie(db: Pool, userId: string): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [userId],
  );
  return rows[0]?.member_id ?? null;
}

function formaterDateEmission(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getUTCDate()).padStart(2, "0")}/${String(d.getUTCMonth() + 1).padStart(2, "0")}/${d.getUTCFullYear()}`;
}

export function registerAttestationsRoutes(app: FastifyInstance, db: Pool) {
  // -- Génération pour une année : tous les donateurs identifiés avec au
  // moins un don confirmé cette année. Une attestation émise existante
  // n'est pas régénérée (voir /corriger pour une correction explicite).
  app.post(
    "/attestations/generer",
    { preHandler: [requireAuth(db), requireRole(...GESTION)] },
    async (req, reply) => {
      const parsed = genererSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Année invalide (2000 à 2100).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { annee } = parsed.data;
      try {
        const { rows: churchRows } = await db.query(
          `SELECT name, code, logo_url FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const church = churchRows[0];
        if (!church) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });

        const { rows: donateurs } = await db.query(
          `SELECT DISTINCT member_id FROM contributions
            WHERE church_id = $1 AND member_id IS NOT NULL
              AND status = 'confirme' AND type IN ('dime', 'offrande', 'don')
              AND created_at >= $2::date AND created_at < $3::date`,
          [req.session.churchId, `${annee}-01-01`, `${annee + 1}-01-01`],
        );
        const creees: unknown[] = [];
        let ignorees = 0;
        for (const d of donateurs) {
          const memberId = d.member_id as string;
          const existante = await db.query(
            `SELECT id FROM attestations
              WHERE church_id = $1 AND member_id = $2 AND annee = $3 AND statut = 'emise'`,
            [req.session.churchId, memberId, annee],
          );
          if ((existante.rowCount ?? 0) > 0) {
            ignorees += 1;
            continue;
          }
          const { rows: memberRows } = await db.query(
            `SELECT full_name, matricule FROM members WHERE id = $1 AND church_id = $2`,
            [memberId, req.session.churchId],
          );
          if (memberRows.length === 0) continue;
          const { dons, total } = await donsConfirmes(db, req.session.churchId, memberId, annee);
          if (dons.length === 0) continue;
          const numero = await prochainNumero(db, req.session.churchId, annee);
          const contenu: ContenuAttestation = {
            donateur_nom: memberRows[0].full_name,
            donateur_matricule: memberRows[0].matricule,
            eglise: { nom: church.name, code: church.code, logo_url: church.logo_url },
            dons,
            total_fcfa: total,
            nb_dons: dons.length,
          };
          const { rows: ins } = await db.query(
            `INSERT INTO attestations
               (church_id, member_id, annee, numero, total_fcfa, nb_dons, statut, contenu)
             VALUES ($1, $2, $3, $4, $5, $6, 'emise', $7)
             RETURNING id, numero, member_id, annee, total_fcfa, nb_dons, statut, date_emission`,
            [
              req.session.churchId,
              memberId,
              annee,
              numero,
              total,
              dons.length,
              JSON.stringify(contenu),
            ],
          );
          await auditLog(db, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "attestation.generee",
            details: {
              attestation_id: ins[0].id,
              numero,
              member_id: memberId,
              annee,
              total_fcfa: total,
              nb_dons: dons.length,
            },
          });
          creees.push({ ...ins[0], membre_nom: memberRows[0].full_name });
        }
        return reply.code(201).send({ annee, creees, ignorees });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Liste de mon église (trésorier / admin), filtre par année.
  app.get(
    "/attestations",
    { preHandler: [requireAuth(db), requireRole(...GESTION)] },
    async (req, reply) => {
      const parsed = listeQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Année invalide.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const values: unknown[] = [req.session.churchId];
        let where = `a.church_id = $1`;
        if (parsed.data.annee) {
          values.push(parsed.data.annee);
          where += ` AND a.annee = $${values.length}`;
        }
        const { rows } = await db.query(
          `SELECT a.id, a.numero, a.annee, a.member_id, a.total_fcfa, a.nb_dons,
                  a.statut, a.remplace_id, a.date_emission,
                  m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM attestations a
             JOIN members m ON m.id = a.member_id
            WHERE ${where}
            ORDER BY a.annee DESC, a.numero DESC`,
          values,
        );
        return reply.send({ attestations: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- PDF d'une attestation, depuis son contenu figé. Trésorier / admin
  // de l'église, ou le membre lui-même (403 sinon, autre église incluse).
  app.get(
    "/attestations/:id/pdf",
    { preHandler: [requireAuth(db)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, church_id, member_id, numero, annee, total_fcfa, nb_dons,
                  statut, date_emission, contenu
             FROM attestations WHERE id = $1`,
          [(req.params as { id: string }).id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Attestation introuvable." });
        }
        const att = rows[0];
        const role = req.session.role;
        if (role === "membre") {
          const memberId = await membreLie(db, req.session.userId);
          if (!memberId || memberId !== att.member_id || att.church_id !== req.session.churchId) {
            return reply.code(403).send({ error: "forbidden", message: "Cette attestation n'est pas la vôtre." });
          }
        } else if (GESTION.includes(role as "admin_eglise" | "tresorier")) {
          if (att.church_id !== req.session.churchId) {
            return reply.code(403).send({ error: "forbidden", message: "Attestation d'une autre église." });
          }
        } else {
          return reply.code(403).send({ error: "forbidden", message: "Rôle non autorisé." });
        }
        if (att.statut !== "emise") {
          return reply.code(409).send({ error: "conflict", message: "Cette attestation est annulée." });
        }
        const contenu = att.contenu as ContenuAttestation;
        const pdf = genererAttestationPdf({
          egliseNom: contenu.eglise.nom,
          egliseCode: contenu.eglise.code,
          numero: att.numero,
          annee: att.annee,
          dateEmission: formaterDateEmission(att.date_emission as string),
          donateurNom: contenu.donateur_nom,
          donateurMatricule: contenu.donateur_matricule,
          dons: contenu.dons.map((d) => ({
            date: d.date,
            type: d.type,
            montantFcfa: d.montant_fcfa,
          })),
          totalFcfa: att.total_fcfa,
        });
        return reply
          .header("Content-Type", "application/pdf")
          .header("Content-Disposition", `attachment; filename="${att.numero}.pdf"`)
          .send(pdf);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Correction : nouvelle attestation (nouveau numéro, dons recalculés
  // sur les contributions confirmées actuelles), ancienne annulée. Motif
  // obligatoire. Les deux sont tracées dans l'audit.
  app.post(
    "/attestations/:id/corriger",
    { preHandler: [requireAuth(db), requireRole(...GESTION)] },
    async (req, reply) => {
      const parsed = corrigerSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Motif de correction obligatoire (2 à 500 caractères).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows } = await client.query(
          `SELECT id, church_id, member_id, annee, numero FROM attestations
            WHERE id = $1 AND church_id = $2 AND statut = 'emise' FOR UPDATE`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "conflict",
            message: "Attestation introuvable, déjà annulée ou d'une autre église.",
          });
        }
        const ancienne = rows[0];
        const { rows: memberRows } = await client.query(
          `SELECT full_name, matricule FROM members WHERE id = $1`,
          [ancienne.member_id],
        );
        const { rows: churchRows } = await client.query(
          `SELECT name, code, logo_url FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const { dons, total } = await donsConfirmes(
          client,
          req.session.churchId,
          ancienne.member_id,
          ancienne.annee,
        );
        if (dons.length === 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "conflict",
            message: "Plus aucun don confirmé pour ce membre cette année : correction impossible.",
          });
        }
        // L'ancienne est annulée AVANT l'insertion : l'index partiel
        // n'autorise qu'une seule attestation émise par membre et année.
        await client.query(
          `UPDATE attestations SET statut = 'annulee' WHERE id = $1`,
          [ancienne.id],
        );
        const numero = await prochainNumero(client, req.session.churchId, ancienne.annee);
        const contenu: ContenuAttestation = {
          donateur_nom: memberRows[0].full_name,
          donateur_matricule: memberRows[0].matricule,
          eglise: {
            nom: churchRows[0].name,
            code: churchRows[0].code,
            logo_url: churchRows[0].logo_url,
          },
          dons,
          total_fcfa: total,
          nb_dons: dons.length,
        };
        const { rows: ins } = await client.query(
          `INSERT INTO attestations
             (church_id, member_id, annee, numero, total_fcfa, nb_dons, statut, remplace_id, contenu)
           VALUES ($1, $2, $3, $4, $5, $6, 'emise', $7, $8)
           RETURNING id, numero, member_id, annee, total_fcfa, nb_dons, statut, remplace_id, date_emission`,
          [
            req.session.churchId,
            ancienne.member_id,
            ancienne.annee,
            numero,
            total,
            dons.length,
            ancienne.id,
            JSON.stringify(contenu),
          ],
        );
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "attestation.generee",
          details: {
            attestation_id: ins[0].id,
            numero,
            member_id: ancienne.member_id,
            annee: ancienne.annee,
            total_fcfa: total,
            nb_dons: dons.length,
            remplace_id: ancienne.id,
            motif: parsed.data.motif,
          },
        });
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "attestation.corrige",
          details: {
            ancienne_id: ancienne.id,
            ancien_numero: ancienne.numero,
            nouvelle_id: ins[0].id,
            nouveau_numero: numero,
            motif: parsed.data.motif,
          },
        });
        await client.query("COMMIT");
        return reply.code(201).send(ins[0]);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  // -- Mes attestations (membre) : émises seulement, les siennes seulement.
  app.get(
    "/moi/attestations",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const memberId = await membreLie(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Aucun membre lié à ce compte." });
        }
        const { rows } = await db.query(
          `SELECT a.id, a.numero, a.annee, a.total_fcfa, a.nb_dons, a.statut,
                  a.date_emission, m.full_name AS membre_nom
             FROM attestations a
             JOIN members m ON m.id = a.member_id
            WHERE a.member_id = $1 AND a.church_id = $2 AND a.statut = 'emise'
            ORDER BY a.annee DESC, a.date_emission DESC`,
          [memberId, req.session.churchId],
        );
        return reply.send({ attestations: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
