import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { envoiCourrielDisponible, sendMail } from "../mailer.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { formaterMontant, genererRapportPdf } from "../pdf.js";

/**
 * Tranche P5 — Rapports à mon église mère : une annexe choisit le type
 * de rapport (migration 023), l'application le génère depuis ses
 * vraies données et l'envoie par e-mail à son église mère, en pièce
 * jointe PDF. La mère lit les rapports reçus dans « Rapports reçus ».
 *
 * Envoi (Lot B, tranche P5) : à la création (POST /moi/rapports-annexe),
 * le PDF du rapport est généré depuis les données figées en base et
 * envoyé en pièce jointe via mailer.ts à l'adresse de l'église mère
 * (churches.email de la racine du réseau). Si l'envoi réussit, le
 * statut passe à `envoye` ; sinon le rapport reste `en_attente_envoi`
 * (e-mail de la mère manquant, SMTP non configuré, ou échec d'envoi)
 * et peut être renvoyé par POST /moi/rapports-annexe/:id/envoyer.
 *
 * Aucune adresse e-mail inventée : celle de la mère se lit dans
 * churches.email, nulle tant qu'elle n'est pas renseignée en base.
 */

const TYPES = ["bilan_annuel", "bilan_activite", "rapport_financier"] as const;

const LIBELLES_TYPE: Record<(typeof TYPES)[number], string> = {
  bilan_annuel: "Bilan annuel",
  bilan_activite: "Bilan d'activité",
  rapport_financier: "Rapport financier",
};

const envoiSchema = z.object({
  type: z.enum(TYPES),
  message: z.string().max(2000).optional().nullable(),
  membres: z.number().int().min(0),
  recettes_fcfa: z.number().int().min(0),
  depenses_fcfa: z.number().int().min(0),
  solde_fcfa: z.number().int(),
});

// Racine du réseau de mon église : premier ancêtre sans mère. Une
// église mère est sa propre racine.
const RACINE_SQL = `
  WITH RECURSIVE ancetres AS (
     SELECT id, parent_church_id, name, email FROM churches WHERE id = $1
     UNION ALL
     SELECT c.id, c.parent_church_id, c.name, c.email
       FROM churches c
       JOIN ancetres a ON c.id = a.parent_church_id
   )
   SELECT id, name, email FROM ancetres
    WHERE parent_church_id IS NULL LIMIT 1`;

/** Ligne de rapports_annexe telle que lue en base. */
type RapportLigne = {
  id: string;
  type: (typeof TYPES)[number];
  message: string | null;
  membres: number;
  recettes_fcfa: number;
  depenses_fcfa: number;
  solde_fcfa: number;
  statut: string;
  cree_le: string | Date;
};

/** Résultat d'une tentative d'envoi, renvoyé dans `envoi_email`. */
type ResultatEnvoi =
  | "envoye"
  | "email_mere_manquant"
  | "smtp_non_configure"
  | "echec_envoi";

// Réponse publique d'un rapport (mêmes champs que la création, plus le
// résultat de l'envoi). L'application lit ces clés en snake_case.
function reponseRapport(ligne: RapportLigne, envoi_email: ResultatEnvoi) {
  return {
    id: ligne.id,
    type: ligne.type,
    message: ligne.message,
    membres: ligne.membres,
    recettes_fcfa: ligne.recettes_fcfa,
    depenses_fcfa: ligne.depenses_fcfa,
    solde_fcfa: ligne.solde_fcfa,
    statut: ligne.statut,
    cree_le: ligne.cree_le,
    envoi_email,
  };
}

/** Largeur maximale d'une ligne meta du générateur PDF (taille 10). */
const LIGNE_META_MAX = 94;

/**
 * Découpe un message libre en lignes de 94 caractères maximum, par
 * retour à la ligne sur les mots. La première ligne porte le préfixe
 * « Message : » ; les suivantes n'en ont pas. Un mot isolé plus long
 * qu'une ligne est coupé à la longueur maximale. Le générateur PDF
 * (pdf.ts) tronque chaque ligne meta à 94 caractères : sans cette
 * découpe, la fin du message serait perdue. Exporté pour les tests.
 */
export function decouperLignesMessage(message: string): string[] {
  const mots: string[] = [];
  for (const mot of message.split(/\s+/)) {
    if (!mot) continue;
    for (let i = 0; i < mot.length; i += LIGNE_META_MAX) {
      mots.push(mot.slice(i, i + LIGNE_META_MAX));
    }
  }
  if (mots.length === 0) return [];
  const prefixe = "Message : ";
  const lignes: string[] = [];
  let courante = prefixe;
  for (const mot of mots) {
    const separateur = courante.endsWith(" ") ? "" : " ";
    if (courante.length + separateur.length + mot.length > LIGNE_META_MAX) {
      lignes.push(courante);
      courante = mot;
    } else {
      courante += separateur + mot;
    }
  }
  if (courante) lignes.push(courante);
  return lignes;
}

// Construit le PDF du rapport depuis les données figées en base (jamais
// recalculé) et le nom du fichier joint. Réutilise genererRapportPdf.
export function construirePdfRapport(
  rapport: RapportLigne,
  annexeNom: string,
  mereNom: string,
): { pdf: Buffer; nomFichier: string } {
  const dateEmission = new Date(rapport.cree_le).toISOString().slice(0, 10);
  const pdf = genererRapportPdf({
    titre: LIBELLES_TYPE[rapport.type],
    egliseNom: annexeNom,
    lignesMeta: [
      `À l'attention de : ${mereNom}`,
      `Émis le ${dateEmission}`,
      ...(rapport.message ? decouperLignesMessage(rapport.message) : []),
    ],
    sections: [
      {
        titre: "Chiffres du rapport",
        colonnes: [
          { titre: "Indicateur", largeur: 335 },
          { titre: "Valeur", largeur: 160, alignerDroite: true },
        ],
        lignes: [
          ["Membres", String(rapport.membres)],
          ["Recettes", formaterMontant(rapport.recettes_fcfa)],
          ["Dépenses", formaterMontant(rapport.depenses_fcfa)],
        ],
        total: ["Solde", formaterMontant(rapport.solde_fcfa)],
        messageVide: "Aucun chiffre.",
      },
    ],
    pied: "Rapport généré automatiquement par e-System Church.",
  });
  return { pdf, nomFichier: `rapport-annexe-${rapport.type}-${dateEmission}.pdf` };
}

// Tente l'envoi du rapport par e-mail à l'église mère (PDF en pièce
// jointe). Ne lève jamais : le résultat dit ce qui s'est passé.
async function tenterEnvoiRapport(
  rapport: RapportLigne,
  annexeNom: string,
  mere: { nom: string; email: string | null },
): Promise<ResultatEnvoi> {
  if (!mere.email) return "email_mere_manquant";
  if (!envoiCourrielDisponible()) return "smtp_non_configure";
  const { pdf, nomFichier } = construirePdfRapport(
    rapport,
    annexeNom,
    mere.nom,
  );
  const libelle = LIBELLES_TYPE[rapport.type];
  const dateEmission = new Date(rapport.cree_le).toISOString().slice(0, 10);
  const texte = [
    "Bonjour,",
    "",
    `Veuillez trouver en pièce jointe le ${libelle.toLowerCase()} de ${annexeNom}, émis le ${dateEmission}.`,
    "",
    `Membres : ${rapport.membres}`,
    `Recettes : ${formaterMontant(rapport.recettes_fcfa)}`,
    `Dépenses : ${formaterMontant(rapport.depenses_fcfa)}`,
    `Solde : ${formaterMontant(rapport.solde_fcfa)}`,
    "",
    "— e-System Church",
  ].join("\n");
  const ok = await sendMail(mere.email, `Rapport ${libelle} — ${annexeNom}`, texte, [
    { filename: nomFichier, content: pdf, contentType: "application/pdf" },
  ]);
  return ok ? "envoye" : "echec_envoi";
}

// Journalise l'envoi réussi. L'audit ne doit jamais faire échouer
// l'envoi : toute erreur est avalée.
async function journaliserEnvoi(
  db: Pool,
  churchId: string,
  userId: string | null,
  rapport: RapportLigne,
): Promise<void> {
  try {
    await auditLog(db, {
      churchId,
      userId,
      action: "rapport_annexe.envoye",
      details: { rapport_id: rapport.id, type: rapport.type },
    });
  } catch {
    // L'audit ne bloque pas l'envoi.
  }
}

export function registerRapportsAnnexeRoutes(app: FastifyInstance, db: Pool) {
  // -- Mon église mère (admin de l'église) : racine du réseau, nom et
  //    adresse e-mail, nulle tant qu'elle n'est pas renseignée.
  app.get(
    "/moi/eglise-mere",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(RACINE_SQL, [req.session.churchId]);
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = rows[0] as {
          id: string;
          name: string;
          email: string | null;
        };
        return reply.send({
          id: mere.id,
          nom: mere.name,
          email: mere.email,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Envoyer un rapport à mon église mère (admin d'une annexe) : le
  //    rapport est enregistré avec ses chiffres réels, puis envoyé
  //    par e-mail à l'église mère (PDF en pièce jointe). Si l'envoi
  //    réussit, le statut passe à `envoye` ; sinon le rapport reste
  //    `en_attente_envoi` (renvoi possible). Une église mère n'envoie
  //    pas de rapport à elle-même.
  app.post(
    "/moi/rapports-annexe",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = envoiSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Rapport invalide.",
        });
      }
      const { type, message, membres, recettes_fcfa, depenses_fcfa, solde_fcfa } =
        parsed.data;
      try {
        const { rows: racines } = await db.query(RACINE_SQL, [
          req.session.churchId,
        ]);
        if (racines.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = racines[0] as {
          id: string;
          name: string;
          email: string | null;
        };
        if (mere.id === req.session.churchId) {
          return reply.code(403).send({
            error: "mere_sans_mere",
            message:
              "Une église mère n’envoie pas de rapport à elle-même.",
          });
        }
        const { rows } = await db.query(
          `INSERT INTO rapports_annexe
             (eglise_id, eglise_mere_id, type, message, membres,
              recettes_fcfa, depenses_fcfa, solde_fcfa, statut)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'en_attente_envoi')
           RETURNING id, type, message, membres, recettes_fcfa,
             depenses_fcfa, solde_fcfa, statut, cree_le`,
          [
            req.session.churchId,
            mere.id,
            type,
            message ?? null,
            membres,
            recettes_fcfa,
            depenses_fcfa,
            solde_fcfa,
          ],
        );
        const ligne = rows[0] as RapportLigne;
        const { rows: annexes } = await db.query(
          `SELECT name FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const annexeNom =
          (annexes[0] as { name: string } | undefined)?.name ?? "Église annexe";
        const resultat = await tenterEnvoiRapport(ligne, annexeNom, {
          nom: mere.name,
          email: mere.email,
        });
        if (resultat === "envoye") {
          await db.query(
            `UPDATE rapports_annexe SET statut = 'envoye' WHERE id = $1`,
            [ligne.id],
          );
          ligne.statut = "envoye";
          await journaliserEnvoi(
            db,
            req.session.churchId,
            req.session.userId,
            ligne,
          );
        }
        return reply.send(reponseRapport(ligne, resultat));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Renvoyer un rapport en attente (admin d'une annexe) : régénère
  //    le PDF depuis les données figées en base et le renvoie à
  //    l'église mère. Un rapport déjà envoyé ne se renvoie pas (409) ;
  //    un rapport d'une autre église est introuvable (404).
  app.post(
    "/moi/rapports-annexe/:id/envoyer",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      try {
        const { rows } = await db.query(
          `SELECT id, eglise_id, eglise_mere_id, type, message, membres,
                  recettes_fcfa, depenses_fcfa, solde_fcfa, statut, cree_le
             FROM rapports_annexe WHERE id = $1 AND eglise_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Rapport introuvable.",
          });
        }
        const ligne = rows[0] as RapportLigne & { eglise_mere_id: string };
        if (ligne.statut === "envoye") {
          return reply.code(409).send({
            error: "rapport_deja_envoye",
            message: "Ce rapport a déjà été envoyé.",
          });
        }
        const { rows: meres } = await db.query(
          `SELECT name, email FROM churches WHERE id = $1`,
          [ligne.eglise_mere_id],
        );
        const mere = meres[0] as
          | { name: string; email: string | null }
          | undefined;
        if (!mere) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église mère introuvable.",
          });
        }
        const { rows: annexes } = await db.query(
          `SELECT name FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const annexeNom =
          (annexes[0] as { name: string } | undefined)?.name ?? "Église annexe";
        const resultat = await tenterEnvoiRapport(ligne, annexeNom, {
          nom: mere.name,
          email: mere.email,
        });
        if (resultat === "envoye") {
          await db.query(
            `UPDATE rapports_annexe SET statut = 'envoye' WHERE id = $1`,
            [id],
          );
          ligne.statut = "envoye";
          await journaliserEnvoi(
            db,
            req.session.churchId,
            req.session.userId,
            ligne,
          );
        }
        return reply.send(reponseRapport(ligne, resultat));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapports reçus par mon église mère (admin de la mère) : ceux
  //    envoyés par ses églises annexes, le plus récent d'abord, avec
  //    le nom de l'église expéditrice. Une annexe ne lit pas les
  //    rapports des autres annexes.
  app.get(
    "/moi/rapports-annexe/recus",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows: racines } = await db.query(RACINE_SQL, [
          req.session.churchId,
        ]);
        if (racines.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = racines[0] as { id: string };
        if (mere.id !== req.session.churchId) {
          return reply.code(403).send({
            error: "annexe_sans_recus",
            message:
              "Une église annexe ne lit pas les rapports reçus.",
          });
        }
        const { rows } = await db.query(
          `SELECT r.id, r.type, r.message, r.membres, r.recettes_fcfa,
                  r.depenses_fcfa, r.solde_fcfa, r.statut, r.cree_le,
                  c.name AS eglise_nom
             FROM rapports_annexe r
             JOIN churches c ON c.id = r.eglise_id
            WHERE r.eglise_mere_id = $1
            ORDER BY r.cree_le DESC`,
          [req.session.churchId],
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
