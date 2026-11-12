import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { genererAttestationEvenementPdf, genererAttestationPdf } from "../pdf.js";

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
 * Tranche B (migration 016) — attestations d'événement, PDF exclusivement :
 * mariage, naissance, baptême. Même principe (contenu figé, correction
 * par nouvelle attestation, motif obligatoire), émission individuelle
 * par membre, numéro unique par église, année et type (MAR, NAI, BAP),
 * PDF généré depuis le contenu figé. Aucun autre format, jamais.
 *
 * POST  /attestations/generer   — admin_eglise, tresorier.
 * POST  /attestations/emette    — admin_eglise, tresorier (un événement).
 * GET   /attestations           — admin_eglise, tresorier (filtres annee, type).
 * GET   /attestations/:id/pdf   — admin_eglise, tresorier, ou le membre lui-même.
 * POST  /attestations/:id/corriger — admin_eglise, tresorier (motif obligatoire).
 * GET   /moi/attestations       — membre, ses attestations émises seulement.
 */

const TYPES_DONS = ["dime", "offrande", "don"] as const;
const LIBELLES: Record<string, string> = { dime: "Dîme", offrande: "Offrande", don: "Don" };

/** Types d'attestation (colonne `type`, migration 016). */
const TYPES_ATTESTATION = ["don", "mariage", "naissance", "bapteme"] as const;
type TypeAttestation = (typeof TYPES_ATTESTATION)[number];
const PREFIXES: Record<TypeAttestation, string> = {
  don: "ATT",
  mariage: "MAR",
  naissance: "NAI",
  bapteme: "BAP",
};
const LIBELLES_TYPES: Record<TypeAttestation, string> = {
  don: "Attestation annuelle de dons",
  mariage: "Attestation de mariage",
  naissance: "Attestation de naissance",
  bapteme: "Attestation de baptême",
};

const genererSchema = z.object({
  annee: z.number().int().min(2000).max(2100),
});

/** Date AAAA-MM-JJ réelle (le 30 février est refusé, pas reporté en mars). */
function estDateValide(s: string): boolean {
  const [a, m, j] = s.split("-").map(Number);
  if (m < 1 || m > 12 || j < 1 || j > 31) return false;
  const d = new Date(Date.UTC(a, m - 1, j));
  return d.getUTCFullYear() === a && d.getUTCMonth() === m - 1 && d.getUTCDate() === j;
}

const dateEvenementSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Date attendue au format AAAA-MM-JJ.")
  .refine(estDateValide, "Date inexistante.")
  .refine(
    (s) => Number(s.slice(0, 4)) >= 2000 && Number(s.slice(0, 4)) <= 2100,
    "Année entre 2000 et 2100.",
  );

/** Champs propres à chaque type d'événement : tous facultatifs, sauf la
 *  date de l'événement. Point de décision pour Axel : la liste exacte
 *  des champs peut être élargie ou réduite ensuite. */
const champsEvenement = {
  lieu: z.string().trim().min(1).max(200).optional(),
  officiant: z.string().trim().min(1).max(200).optional(),
  conjoint_nom: z.string().trim().min(1).max(200).optional(),
  pere_nom: z.string().trim().min(1).max(200).optional(),
  mere_nom: z.string().trim().min(1).max(200).optional(),
  parrain_nom: z.string().trim().min(1).max(200).optional(),
  marraine_nom: z.string().trim().min(1).max(200).optional(),
};

const emettreSchema = z.object({
  type: z.enum(["mariage", "naissance", "bapteme"]),
  member_id: z.string().uuid(),
  date_evenement: dateEvenementSchema,
  ...champsEvenement,
});

const corrigerSchema = z.object({
  motif: z.string().min(2).max(500),
  // Correction d'une attestation d'événement : seuls les champs fournis
  // changent, les autres gardent leur valeur figée. Ignorés pour un don.
  date_evenement: dateEvenementSchema.optional(),
  ...champsEvenement,
});

const listeQuerySchema = z.object({
  annee: z.coerce.number().int().min(2000).max(2100).optional(),
  type: z.enum(TYPES_ATTESTATION).optional(),
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

/** Contenu figé d'une attestation d'événement : personne concernée,
 *  événement, champs propres au type (null quand non renseigné). */
interface ContenuEvenement {
  personne_nom: string;
  personne_matricule: string | null;
  eglise: { nom: string; code: string; logo_url: string | null };
  type: "mariage" | "naissance" | "bapteme";
  date_evenement: string; // AAAA-MM-JJ
  lieu: string | null;
  officiant: string | null;
  conjoint_nom: string | null;
  pere_nom: string | null;
  mere_nom: string | null;
  parrain_nom: string | null;
  marraine_nom: string | null;
}

/** Détails affichés sur le PDF d'un événement, selon son type. */
function detailsEvenement(c: ContenuEvenement): { label: string; valeur: string }[] {
  const details: { label: string; valeur: string }[] = [];
  if (c.type === "mariage" && c.conjoint_nom) {
    details.push({ label: "Conjoint(e)", valeur: c.conjoint_nom });
  }
  if (c.type === "naissance") {
    if (c.pere_nom) details.push({ label: "Père", valeur: c.pere_nom });
    if (c.mere_nom) details.push({ label: "Mère", valeur: c.mere_nom });
  }
  if (c.type === "bapteme") {
    if (c.parrain_nom) details.push({ label: "Parrain", valeur: c.parrain_nom });
    if (c.marraine_nom) details.push({ label: "Marraine", valeur: c.marraine_nom });
  }
  return details;
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

/** Prochain numéro pour un type : séquence propre au type, même
 *  structure XXX-AAAA-NNNN (ATT-2026-0001, MAR-2026-0001…). */
async function prochainNumero(
  client: Pool | PoolClient,
  churchId: string,
  annee: number,
  type: TypeAttestation = "don",
): Promise<string> {
  const { rows } = await client.query(
    `SELECT coalesce(max(CAST(substr(numero, 10) AS int)), 0)::int AS n
       FROM attestations WHERE church_id = $1 AND annee = $2 AND type = $3`,
    [churchId, annee, type],
  );
  return `${PREFIXES[type]}-${annee}-${String(rows[0].n + 1).padStart(4, "0")}`;
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

/** AAAA-MM-JJ → JJ/MM/AAAA, sans passer par Date (pas de décalage). */
function formaterDateCourte(aaaaMmJj: string): string {
  const [a, m, j] = aaaaMmJj.split("-");
  return `${j}/${m}/${a}`;
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
              WHERE church_id = $1 AND member_id = $2 AND type = 'don' AND annee = $3 AND statut = 'emise'`,
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
               (church_id, member_id, type, annee, numero, total_fcfa, nb_dons, statut, contenu)
             VALUES ($1, $2, 'don', $3, $4, $5, $6, 'emise', $7)
             RETURNING id, numero, member_id, type, annee, total_fcfa, nb_dons, statut, date_emission`,
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

  // -- Émission individuelle d'une attestation d'événement (mariage,
  // naissance, baptême) : un membre, une date d'événement, contenu figé
  // en JSONB, numéro unique par église, année et type. Une seule
  // attestation émise par membre, type et année (409 sinon, voir
  // /corriger). PDF seulement, jamais d'autre format.
  app.post(
    "/attestations/emette",
    { preHandler: [requireAuth(db), requireRole(...GESTION)] },
    async (req, reply) => {
      const parsed = emettreSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données d'émission invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const d = parsed.data;
      const annee = Number(d.date_evenement.slice(0, 4));
      try {
        const { rows: churchRows } = await db.query(
          `SELECT name, code, logo_url FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const church = churchRows[0];
        if (!church) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        const { rows: memberRows } = await db.query(
          `SELECT full_name, matricule FROM members WHERE id = $1 AND church_id = $2`,
          [d.member_id, req.session.churchId],
        );
        if (memberRows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable dans cette église." });
        }
        const existante = await db.query(
          `SELECT id FROM attestations
            WHERE church_id = $1 AND member_id = $2 AND type = $3 AND annee = $4 AND statut = 'emise'`,
          [req.session.churchId, d.member_id, d.type, annee],
        );
        if ((existante.rowCount ?? 0) > 0) {
          return reply.code(409).send({
            error: "conflict",
            message: `Une ${LIBELLES_TYPES[d.type].toLowerCase()} émise existe déjà pour ce membre en ${annee} : corrigez-la.`,
          });
        }
        const numero = await prochainNumero(db, req.session.churchId, annee, d.type);
        const contenu: ContenuEvenement = {
          personne_nom: memberRows[0].full_name,
          personne_matricule: memberRows[0].matricule,
          eglise: { nom: church.name, code: church.code, logo_url: church.logo_url },
          type: d.type,
          date_evenement: d.date_evenement,
          lieu: d.lieu ?? null,
          officiant: d.officiant ?? null,
          conjoint_nom: d.conjoint_nom ?? null,
          pere_nom: d.pere_nom ?? null,
          mere_nom: d.mere_nom ?? null,
          parrain_nom: d.parrain_nom ?? null,
          marraine_nom: d.marraine_nom ?? null,
        };
        const { rows: ins } = await db.query(
          `INSERT INTO attestations
             (church_id, member_id, type, annee, numero, total_fcfa, nb_dons, statut, contenu)
           VALUES ($1, $2, $3, $4, $5, NULL, NULL, 'emise', $6)
           RETURNING id, numero, member_id, type, annee, total_fcfa, nb_dons, statut, date_emission`,
          [
            req.session.churchId,
            d.member_id,
            d.type,
            annee,
            numero,
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
            type: d.type,
            member_id: d.member_id,
            annee,
            date_evenement: d.date_evenement,
          },
        });
        return reply.code(201).send(ins[0]);
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
        if (parsed.data.type) {
          values.push(parsed.data.type);
          where += ` AND a.type = $${values.length}`;
        }
        const { rows } = await db.query(
          `SELECT a.id, a.numero, a.type, a.annee, a.member_id, a.total_fcfa, a.nb_dons,
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
          `SELECT id, church_id, member_id, numero, type, annee, total_fcfa, nb_dons,
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
        const dateEmission = formaterDateEmission(att.date_emission as string);
        // Dons : générateur US3. Événement : générateur tranche B, depuis
        // le même contenu figé, jamais recalculé.
        const pdf =
          att.type === "don"
            ? genererAttestationPdf({
                egliseNom: (att.contenu as ContenuAttestation).eglise.nom,
                egliseCode: (att.contenu as ContenuAttestation).eglise.code,
                numero: att.numero,
                annee: att.annee,
                dateEmission,
                donateurNom: (att.contenu as ContenuAttestation).donateur_nom,
                donateurMatricule: (att.contenu as ContenuAttestation).donateur_matricule,
                dons: (att.contenu as ContenuAttestation).dons.map((d) => ({
                  date: d.date,
                  type: d.type,
                  montantFcfa: d.montant_fcfa,
                })),
                totalFcfa: att.total_fcfa,
              })
            : (() => {
                const c = att.contenu as ContenuEvenement;
                return genererAttestationEvenementPdf({
                  egliseNom: c.eglise.nom,
                  egliseCode: c.eglise.code,
                  numero: att.numero,
                  libelleType: LIBELLES_TYPES[c.type],
                  dateEmission,
                  personneNom: c.personne_nom,
                  personneMatricule: c.personne_matricule,
                  dateEvenement: formaterDateCourte(c.date_evenement),
                  lieu: c.lieu,
                  officiant: c.officiant,
                  details: detailsEvenement(c),
                });
              })();
        return reply
          .header("Content-Type", "application/pdf")
          .header("Content-Disposition", `attachment; filename="${att.numero}.pdf"`)
          .send(pdf);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Correction : nouvelle attestation (nouveau numéro), ancienne
  // annulée. Motif obligatoire. Don : dons recalculés sur les
  // contributions confirmées actuelles. Événement : contenu figé repris,
  // seuls les champs fournis changent. Les deux sont tracées dans l'audit.
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
          `SELECT id, church_id, member_id, type, annee, numero, contenu FROM attestations
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
        // L'ancienne est annulée AVANT l'insertion : l'index partiel
        // n'autorise qu'une seule attestation émise par membre, type et année.
        await client.query(
          `UPDATE attestations SET statut = 'annulee' WHERE id = $1`,
          [ancienne.id],
        );
        const numero = await prochainNumero(
          client,
          req.session.churchId,
          ancienne.annee,
          ancienne.type as TypeAttestation,
        );
        let ins: { rows: Record<string, unknown>[] };
        let detailsGeneree: Record<string, unknown>;
        if (ancienne.type === "don") {
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
          ins = await client.query(
            `INSERT INTO attestations
               (church_id, member_id, type, annee, numero, total_fcfa, nb_dons, statut, remplace_id, contenu)
             VALUES ($1, $2, 'don', $3, $4, $5, $6, 'emise', $7, $8)
             RETURNING id, numero, member_id, type, annee, total_fcfa, nb_dons, statut, remplace_id, date_emission`,
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
          detailsGeneree = {
            total_fcfa: total,
            nb_dons: dons.length,
          };
        } else {
          const precedent = ancienne.contenu as ContenuEvenement;
          const corrigee: ContenuEvenement = {
            personne_nom: memberRows[0].full_name,
            personne_matricule: memberRows[0].matricule,
            eglise: {
              nom: churchRows[0].name,
              code: churchRows[0].code,
              logo_url: churchRows[0].logo_url,
            },
            type: precedent.type,
            date_evenement: parsed.data.date_evenement ?? precedent.date_evenement,
            lieu: parsed.data.lieu ?? precedent.lieu,
            officiant: parsed.data.officiant ?? precedent.officiant,
            conjoint_nom: parsed.data.conjoint_nom ?? precedent.conjoint_nom,
            pere_nom: parsed.data.pere_nom ?? precedent.pere_nom,
            mere_nom: parsed.data.mere_nom ?? precedent.mere_nom,
            parrain_nom: parsed.data.parrain_nom ?? precedent.parrain_nom,
            marraine_nom: parsed.data.marraine_nom ?? precedent.marraine_nom,
          };
          ins = await client.query(
            `INSERT INTO attestations
               (church_id, member_id, type, annee, numero, total_fcfa, nb_dons, statut, remplace_id, contenu)
             VALUES ($1, $2, $3, $4, $5, NULL, NULL, 'emise', $6, $7)
             RETURNING id, numero, member_id, type, annee, total_fcfa, nb_dons, statut, remplace_id, date_emission`,
            [
              req.session.churchId,
              ancienne.member_id,
              precedent.type,
              ancienne.annee,
              numero,
              ancienne.id,
              JSON.stringify(corrigee),
            ],
          );
          detailsGeneree = {
            type: precedent.type,
            date_evenement: corrigee.date_evenement,
          };
        }
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "attestation.generee",
          details: {
            attestation_id: ins.rows[0].id,
            numero,
            member_id: ancienne.member_id,
            annee: ancienne.annee,
            ...detailsGeneree,
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
            nouvelle_id: ins.rows[0].id,
            nouveau_numero: numero,
            motif: parsed.data.motif,
          },
        });
        await client.query("COMMIT");
        return reply.code(201).send(ins.rows[0]);
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
          `SELECT a.id, a.numero, a.type, a.annee, a.total_fcfa, a.nb_dons, a.statut,
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
