import { createHash } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { READ_ALL } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  genererProcesVerbalPdf,
  type SignaturePdfData,
} from "../pdf.js";
import { chargerLogo } from "../logo_pdf.js";

/**
 * Signature électronique V1 (migration 036) : signature DESSINÉE dans
 * l'application, sans prestataire externe et sans coût. Une seule
 * signature par document en V1 (attestation ou procès-verbal).
 *
 * Le PNG est stocké tel quel (preuve) mais jamais décodé côté serveur :
 * le PDF redessine le tracé depuis les points normalisés 0..1. Seule
 * l'empreinte SHA-256 du PNG est journalisée dans l'audit.
 *
 * POST /attestations/:id/signer    — admin_eglise, tresorier.
 * POST /proces-verbaux/:id/signer  — admin_eglise, responsable_culte.
 * GET  /signatures/:type/:id       — rôles d'église (lecture).
 * GET  /proces-verbaux/:id/pdf     — rôles d'église, PDF avec signature.
 *
 * Un membre simple (rôle membre) ne signe jamais un document
 * d'administration : requireRole le refuse en 403 avant toute écriture.
 * Un procès-verbal ne se signe JAMAIS par le PATCH générique
 * (voir validateUpdate dans gouvernance.ts) : seule cette route passe
 * son statut à 'signe'.
 */

/** Poids maximal du PNG de signature : 200 Ko. */
const MAX_IMAGE_OCTETS = 200 * 1024;
/** Nombre maximal de points du tracé (garde anti-abus). */
const MAX_POINTS = 5000;
/** Signature PNG : 89 50 4E 47 0D 0A 1A 0A. */
const MAGIE_PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Fonction figée sur la signature, libellé du rôle du signataire. */
const FONCTIONS_ROLE: Record<string, string> = {
  admin_eglise: "Administrateur de l'église",
  tresorier: "Trésorier",
  responsable_culte: "Responsable de culte",
};

const pointSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
});

const signerSchema = z.object({
  /** Tracé normalisé 0..1, non vide. */
  points: z.array(pointSchema).min(1).max(MAX_POINTS),
  /** PNG de la signature, en base64, non vide, 200 Ko maximum. */
  image_png_base64: z.string().min(1).max(400_000),
  /** Nom affiché sur la signature ; par défaut le nom complet du compte. */
  nom_affiche: z.string().trim().min(2).max(200).optional(),
});

type TypeDocument = "attestation" | "proces_verbal";

/** JJ/MM/AAAA à HH:MM UTC, pour le bloc signature des PDF. */
export function formaterDateHeureSignature(date: string | Date): string {
  const d = new Date(date);
  const jj = String(d.getUTCDate()).padStart(2, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const min = String(d.getUTCMinutes()).padStart(2, "0");
  return `${jj}/${mm}/${d.getUTCFullYear()} à ${hh}:${min} UTC`;
}

/** AAAA-MM-JJ → JJ/MM/AAAA, sans passer par Date (pas de décalage). */
function formaterDateCourte(aaaaMmJj: string): string {
  const [a, m, j] = aaaaMmJj.split("-");
  return `${j}/${m}/${a}`;
}

/** Date (objet pg) ou AAAA-MM-JJ → JJ/MM/AAAA. */
function formaterDatePv(valeur: Date | string): string {
  if (valeur instanceof Date) {
    const jj = String(valeur.getUTCDate()).padStart(2, "0");
    const mm = String(valeur.getUTCMonth() + 1).padStart(2, "0");
    return `${jj}/${mm}/${valeur.getUTCFullYear()}`;
  }
  return formaterDateCourte(String(valeur).slice(0, 10));
}

/** Base64 strict → Buffer, ou null si la chaîne n'est pas du base64. */
function decoderBase64(valeur: string): Buffer | null {
  const compacte = valeur.replace(/\s/g, "");
  if (compacte.length === 0 || compacte.length % 4 !== 0) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(compacte)) return null;
  return Buffer.from(compacte, "base64");
}

interface LigneSignature {
  id: string;
  church_id: string;
  document_type: string;
  document_id: string;
  signataire_user_id: string | null;
  signataire_nom: string;
  signataire_fonction: string;
  points: { x: number; y: number }[];
  image_png: Buffer;
  empreinte_sha256: string;
  methode: string;
  date_signature: Date | string;
}

export async function chargerSignature(
  client: Pool | PoolClient,
  documentType: TypeDocument,
  documentId: string,
): Promise<LigneSignature | null> {
  const { rows } = await client.query<LigneSignature>(
    `SELECT id, church_id, document_type, document_id, signataire_user_id,
            signataire_nom, signataire_fonction, points, image_png,
            empreinte_sha256, methode, date_signature
       FROM signatures WHERE document_type = $1 AND document_id = $2`,
    [documentType, documentId],
  );
  return rows[0] ?? null;
}

/** Ligne de signature → données du bloc signature d'un PDF. */
export function signatureVersPdf(ligne: LigneSignature): SignaturePdfData {
  return {
    nom: ligne.signataire_nom,
    fonction: ligne.signataire_fonction,
    dateHeure: formaterDateHeureSignature(ligne.date_signature),
    empreinteSha256: ligne.empreinte_sha256,
    points: Array.isArray(ligne.points) ? ligne.points : [],
  };
}

/** Réponse publique d'une signature (sans le PNG, disponible par GET). */
function signaturePublique(ligne: LigneSignature) {
  return {
    id: ligne.id,
    document_type: ligne.document_type,
    document_id: ligne.document_id,
    signataire_user_id: ligne.signataire_user_id,
    signataire_nom: ligne.signataire_nom,
    signataire_fonction: ligne.signataire_fonction,
    empreinte_sha256: ligne.empreinte_sha256,
    methode: ligne.methode,
    date_signature: ligne.date_signature,
  };
}

interface ConfigSignature {
  table: "attestations" | "proces_verbaux";
  type: TypeDocument;
  /** Statut exigé pour signer : 'emise' (attestation), 'brouillon' (PV). */
  statutAttendu: string;
  actionAudit: "attestation.signee" | "proces_verbal.signe";
  /** Statut après signature (PV seulement : 'signe'). */
  statutApres: string | null;
}

async function signerDocument(
  req: FastifyRequest,
  reply: FastifyReply,
  db: Pool,
  config: ConfigSignature,
) {
  const parsed = signerSchema.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({
      error: "invalid_input",
      message: "Signature invalide : tracé non vide et image PNG en base64 attendus.",
      details: parsed.error.issues.map((i) => i.message),
    });
  }
  const png = decoderBase64(parsed.data.image_png_base64);
  if (!png || png.length === 0) {
    return reply.code(400).send({
      error: "invalid_input",
      message: "Image de signature vide ou base64 invalide.",
    });
  }
  if (png.length > MAX_IMAGE_OCTETS) {
    return reply.code(400).send({
      error: "invalid_input",
      message: `Image de signature trop lourde : ${png.length} octets, 200 Ko maximum.`,
    });
  }
  if (!png.subarray(0, 8).equals(MAGIE_PNG)) {
    return reply.code(400).send({
      error: "invalid_input",
      message: "Image de signature invalide : PNG attendu.",
    });
  }
  const documentId = (req.params as { id: string }).id;
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const { rows } = await client.query(
      `SELECT id, church_id, statut FROM ${config.table} WHERE id = $1 FOR UPDATE`,
      [documentId],
    );
    if (rows.length === 0) {
      await client.query("ROLLBACK");
      return reply.code(404).send({ error: "not_found", message: "Document introuvable." });
    }
    const doc = rows[0];
    if (doc.church_id !== req.session.churchId) {
      await client.query("ROLLBACK");
      return reply.code(403).send({ error: "forbidden", message: "Document d'une autre église." });
    }
    if (doc.statut !== config.statutAttendu) {
      await client.query("ROLLBACK");
      return reply.code(409).send({
        error: "conflict",
        message:
          config.type === "attestation"
            ? "Attestation annulée : elle ne peut plus être signée."
            : doc.statut === "signe"
              ? "Procès-verbal déjà signé."
              : "Procès-verbal archivé : il ne peut plus être signé.",
      });
    }
    const existante = await chargerSignature(client, config.type, documentId);
    if (existante) {
      await client.query("ROLLBACK");
      return reply.code(409).send({
        error: "conflict",
        message: "Ce document est déjà signé.",
      });
    }
    const { rows: userRows } = await client.query<{ full_name: string }>(
      `SELECT full_name FROM users WHERE id = $1`,
      [req.session.userId],
    );
    const signataireNom =
      parsed.data.nom_affiche ?? userRows[0]?.full_name ?? "Signataire";
    const signataireFonction =
      FONCTIONS_ROLE[req.session.role] ?? req.session.role;
    const empreinte = createHash("sha256").update(png).digest("hex");
    const { rows: ins } = await client.query<LigneSignature>(
      `INSERT INTO signatures
         (church_id, document_type, document_id, signataire_user_id,
          signataire_nom, signataire_fonction, points, image_png,
          empreinte_sha256, methode)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'dessin')
       RETURNING id, church_id, document_type, document_id,
         signataire_user_id, signataire_nom, signataire_fonction, points,
         image_png, empreinte_sha256, methode, date_signature`,
      [
        req.session.churchId,
        config.type,
        documentId,
        req.session.userId,
        signataireNom,
        signataireFonction,
        JSON.stringify(parsed.data.points),
        png,
        empreinte,
      ],
    );
    if (config.statutApres) {
      await client.query(
        `UPDATE proces_verbaux SET statut = $2, signataire = $3 WHERE id = $1`,
        [documentId, config.statutApres, signataireNom],
      );
    }
    await auditLog(client, {
      churchId: req.session.churchId,
      userId: req.session.userId,
      action: config.actionAudit,
      details: {
        document_id: documentId,
        empreinte_sha256: empreinte,
        signataire_user_id: req.session.userId,
        signataire_nom: signataireNom,
      },
    });
    await client.query("COMMIT");
    return reply.code(201).send(signaturePublique(ins[0]));
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    if ((e as { code?: string }).code === "23505") {
      return reply.code(409).send({
        error: "conflict",
        message: "Ce document est déjà signé.",
      });
    }
    return dbError(reply, e);
  } finally {
    client.release();
  }
}

export function registerSignaturesRoutes(app: FastifyInstance, db: Pool) {
  // -- Signer une attestation émise (admin, trésorier).
  app.post(
    "/attestations/:id/signer",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "tresorier")] },
    async (req, reply) =>
      signerDocument(req, reply, db, {
        table: "attestations",
        type: "attestation",
        statutAttendu: "emise",
        actionAudit: "attestation.signee",
        statutApres: null,
      }),
  );

  // -- Signer un procès-verbal en brouillon (admin, responsable de culte).
  // Seule cette route passe le PV à 'signe' : jamais par PATCH.
  app.post(
    "/proces-verbaux/:id/signer",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "responsable_culte")] },
    async (req, reply) =>
      signerDocument(req, reply, db, {
        table: "proces_verbaux",
        type: "proces_verbal",
        statutAttendu: "brouillon",
        actionAudit: "proces_verbal.signe",
        statutApres: "signe",
      }),
  );

  // -- Lecture d'une signature (rôles d'église). Un membre ne lit que la
  // signature de ses propres attestations ; les PV sont lisibles par
  // tous les rôles de l'église, comme en GET /proces-verbaux/:id.
  app.get(
    "/signatures/:document_type/:document_id",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const { document_type, document_id } = req.params as {
        document_type: string;
        document_id: string;
      };
      if (document_type !== "attestation" && document_type !== "proces_verbal") {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Type de document invalide : attestation ou proces_verbal.",
        });
      }
      try {
        const sig = await chargerSignature(
          db,
          document_type as TypeDocument,
          document_id,
        );
        if (!sig) {
          return reply.code(404).send({ error: "not_found", message: "Signature introuvable." });
        }
        if (sig.church_id !== req.session.churchId) {
          return reply.code(403).send({ error: "forbidden", message: "Signature d'une autre église." });
        }
        if (req.session.role === "membre" && document_type === "attestation") {
          const { rows } = await db.query<{ member_id: string }>(
            `SELECT member_id FROM attestations WHERE id = $1`,
            [document_id],
          );
          const { rows: userRows } = await db.query<{ member_id: string | null }>(
            `SELECT member_id FROM users WHERE id = $1`,
            [req.session.userId],
          );
          if (
            rows.length === 0 ||
            !userRows[0]?.member_id ||
            userRows[0].member_id !== rows[0].member_id
          ) {
            return reply.code(403).send({
              error: "forbidden",
              message: "Cette signature n'est pas celle de votre attestation.",
            });
          }
        }
        return reply.send({
          ...signaturePublique(sig),
          image_png_base64: (sig.image_png as Buffer).toString("base64"),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- PDF d'un procès-verbal : contenu, date, réunion liée, bloc
  // signature quand il est signé (ligne vierge sinon). Rôles d'église.
  app.get(
    "/proces-verbaux/:id/pdf",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT pv.id, pv.church_id, pv.numero, pv.contenu, pv.date_pv,
                  pv.statut, r.titre AS reunion_titre
             FROM proces_verbaux pv
             LEFT JOIN reunions_conseil r ON r.id = pv.reunion_id
            WHERE pv.id = $1`,
          [(req.params as { id: string }).id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Procès-verbal introuvable." });
        }
        const pv = rows[0];
        if (pv.church_id !== req.session.churchId) {
          return reply.code(403).send({ error: "forbidden", message: "Procès-verbal d'une autre église." });
        }
        const { rows: churchRows } = await db.query(
          `SELECT name, code, logo_url FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const logo = await chargerLogo(churchRows[0]?.logo_url ?? null);
        const sig = await chargerSignature(db, "proces_verbal", pv.id as string);
        const pdf = genererProcesVerbalPdf({
          egliseNom: churchRows[0]?.name ?? "",
          egliseCode: churchRows[0]?.code ?? "",
          logo,
          numero: pv.numero as string | null,
          datePv: formaterDatePv(pv.date_pv as Date | string),
          reunionTitre: pv.reunion_titre as string | null,
          contenu: pv.contenu as string,
          statut: pv.statut as "brouillon" | "signe" | "archive",
          signature: sig ? signatureVersPdf(sig) : null,
        });
        const nomFichier = `PV-${String(pv.numero ?? pv.id).replace(/[^A-Za-z0-9._-]/g, "_")}.pdf`;
        return reply
          .header("Content-Type", "application/pdf")
          .header("Content-Disposition", `attachment; filename="${nomFichier}"`)
          .send(pdf);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
