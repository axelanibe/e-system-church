import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Suppression d'une église entière (suppression de l'église TEST,
 * 13 novembre 2026, élargie le même jour aux annexes).
 *
 * POST /admin/supprimer-eglise — admin_eglise et super_admin.
 *   Corps : { confirmer?: boolean, eglise_id?: string }.
 *   Sans `confirmer: true` : aperçu seulement, rien n'est supprimé.
 *   Avec `confirmer: true` : suppression, dans une seule transaction.
 *
 * Trois cas, une seule route :
 *   1. Auto-suppression (sans `eglise_id`, admin_eglise) : l'église de la
 *      session, seulement si elle est de premier niveau et que son nom
 *      commence par TEST. C'est le cas de l'église TEST (ESC-4240).
 *   2. Annexe par la mère (`eglise_id`, admin_eglise) : une annexe directe
 *      de l'église de la session. Pas de garde TEST : une vraie annexe
 *      peut contenir de vrais membres, l'aperçu montre ce qui part.
 *   3. Annexe par le super admin (`eglise_id`, super_admin) : n'importe
 *      quelle annexe (elle doit avoir un parent). Jamais une église de
 *      premier niveau.
 *
 * Périmètre : l'église cible et toutes ses descendantes (récursif). Une
 * donnée d'une autre église n'est jamais touchée.
 *
 * Tables : presque toutes les tables liées à une église portent
 * `church_id REFERENCES churches (id) ON DELETE CASCADE` et disparaissent
 * avec elle. Restent à supprimer explicitement, avant les églises :
 * `transferts_membre` (RESTRICT sur le membre et sur les églises), puis
 * les églises de la plus profonde à la cible (`parent_church_id` RESTRICT),
 * puis les comptes TEST qui n'ont plus aucune église (nom ou e-mail TEST).
 * `audit_logs` et `codes_tutelle.used_by` passent à NULL, ils survivent.
 * `eglise_paiement_secrets` disparaît en cascade via `eglise_paiements`.
 *
 * Garde-fou : avant toute suppression, les contraintes de clés vers
 * `churches`, `members` et `users` présentes en base sont comparées à la
 * liste des tables prises en charge ci-dessous. Une table inconnue, ou
 * une clé RESTRICT inconnue, refuse la suppression (409) : rien n'est
 * supprimé et la table est à ajouter ici d'abord.
 */

type EgliseCible = { id: string; name: string; code: string; parent_church_id: string | null };

type CasSuppression = "auto_test" | "annexe_mere" | "annexe_super_admin";

/** Tables avec `church_id` (ou équivalent) vers `churches`, en CASCADE. */
const TABLES_LIEES = [
  "abonnements",
  "accompagnements",
  "activites_jeunesse",
  "announcements",
  "attestations",
  "autorisations_sorties",
  "baptemes",
  "budgets",
  "budgets_departements",
  "budgets_mensuels",
  "caisse_mouvements",
  "campagnes",
  "cellules",
  "checkins_enfants",
  "church_users",
  "classes_enfants",
  "clotures_caisse",
  "codes_tutelle",
  "comptes_bancaires",
  "contributions",
  "cotisations_config",
  "culte_rsvp",
  "culte_types",
  "cultes",
  "demandes_priere",
  "departements",
  "depenses",
  "eglise_modules",
  "eglise_paiements",
  "eglise_parametres",
  "enseignants_classes",
  "evenements_paiement",
  "evenements_speciaux",
  "events",
  "familles",
  "fonctions",
  "imports_membres",
  "liens_parent_enfant",
  "livres",
  "maintenance_materiel",
  "materiel",
  "members",
  "membre_cellules",
  "membre_departements",
  "membre_statuts",
  "messages_fidele",
  "messages_internes",
  "ordre_culte_items",
  "parcours_nouveaux",
  "planning_serviteurs",
  "plans_lecture",
  "postes",
  "postes_budgetaires",
  "predications",
  "presences",
  "prets_livres",
  "rapports_annexe",
  "rattachements",
  "refresh_tokens",
  "rencontres_accompagnement",
  "rendez_vous",
  "reservations_salles",
  "salles",
  "serviteurs",
  "visites_pastorales",
] as const;

async function verifierTablesPrisesEnCharge(client: PoolClient): Promise<string | null> {
  // Clés vers churches : toutes les tables porteuses doivent être connues
  // (TABLES_LIEES en CASCADE, churches elle-même en RESTRICT, audit_logs
  // en SET NULL, transferts_membre supprimé explicitement avant).
  // codes_tutelle.used_by est aussi en SET NULL.
  const versEglises = await client.query<{ table_name: string }>(
    `SELECT conrelid::regclass::text AS table_name FROM pg_constraint
      WHERE confrelid = 'churches'::regclass AND contype = 'f'`,
  );
  const attendues = new Set<string>([
    ...TABLES_LIEES,
    "churches",
    "audit_logs",
    "transferts_membre",
  ]);
  for (const r of versEglises.rows) {
    if (!attendues.has(r.table_name)) return r.table_name;
  }
  // Clés RESTRICT (ou sans action) vers members : seul transferts_membre
  // est pris en charge, il est supprimé explicitement avant les membres.
  const versMembres = await client.query<{ table_name: string }>(
    `SELECT conrelid::regclass::text AS table_name FROM pg_constraint
      WHERE confrelid = 'members'::regclass AND contype = 'f'
        AND confdeltype IN ('r', 'a')`,
  );
  for (const r of versMembres.rows) {
    if (r.table_name !== "transferts_membre") return r.table_name;
  }
  // Clés RESTRICT (ou sans action) vers users : aucune n'est prise en
  // charge, la suppression d'un compte TEST échouerait sinon.
  const versUsers = await client.query<{ table_name: string }>(
    `SELECT conrelid::regclass::text AS table_name FROM pg_constraint
      WHERE confrelid = 'users'::regclass AND contype = 'f'
        AND confdeltype IN ('r', 'a')`,
  );
  if (versUsers.rows.length > 0) return versUsers.rows[0].table_name;
  return null;
}

/** Église cible et toutes ses descendantes, de la plus profonde à la cible. */
async function collecterPerimetre(
  client: Pool | PoolClient,
  cibleId: string,
): Promise<EgliseCible[]> {
  const { rows } = await client.query<EgliseCible & { profondeur: number }>(
    `WITH RECURSIVE descendants AS (
       SELECT id, name, code, parent_church_id, 0 AS profondeur
         FROM churches WHERE id = $1
       UNION ALL
       SELECT c.id, c.name, c.code, c.parent_church_id, d.profondeur + 1
         FROM churches c JOIN descendants d ON c.parent_church_id = d.id
     )
     SELECT id, name, code, parent_church_id, profondeur
       FROM descendants ORDER BY profondeur DESC`,
    [cibleId],
  );
  return rows;
}

/** Comptes par table, pour les églises du périmètre (0 exclu). */
async function compterTables(
  client: PoolClient,
  egliseIds: string[],
): Promise<Record<string, number>> {
  const comptes: Record<string, number> = {};
  const existantes = await client.query<{ table_name: string }>(
    `SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = ANY($1)`,
    [[...TABLES_LIEES, "transferts_membre", "eglise_paiement_secrets"]],
  );
  const presentes = new Set(existantes.rows.map((r) => r.table_name));
  const compter = async (table: string, sql: string) => {
    if (!presentes.has(table)) return;
    const { rows } = await client.query<{ n: number }>(sql, [egliseIds]);
    if (rows[0].n > 0) comptes[table] = rows[0].n;
  };
  for (const table of TABLES_LIEES) {
    if (table === "rapports_annexe") {
      await compter(
        table,
        `SELECT count(*)::int AS n FROM rapports_annexe
          WHERE eglise_id = ANY($1) OR eglise_mere_id = ANY($1)`,
      );
    } else if (table === "rattachements") {
      await compter(
        table,
        `SELECT count(*)::int AS n FROM rattachements
          WHERE church_id = ANY($1) OR parent_church_id = ANY($1)`,
      );
    } else {
      await compter(
        table,
        `SELECT count(*)::int AS n FROM ${table} WHERE church_id = ANY($1)`,
      );
    }
  }
  await compter(
    "transferts_membre",
    `SELECT count(*)::int AS n FROM transferts_membre
      WHERE membre_id IN (SELECT id FROM members WHERE church_id = ANY($1))
         OR eglise_depart_id = ANY($1) OR eglise_arrivee_id = ANY($1)`,
  );
  await compter(
    "eglise_paiement_secrets",
    `SELECT count(*)::int AS n FROM eglise_paiement_secrets
      WHERE eglise_paiement_id IN
        (SELECT id FROM eglise_paiements WHERE church_id = ANY($1))`,
  );
  return comptes;
}

/** Comptes TEST qui n'ont plus aucune église après la suppression. */
async function collecterUtilisateursTestASupprimer(
  client: PoolClient,
  egliseIds: string[],
): Promise<string[]> {
  const { rows } = await client.query<{ id: string }>(
    `SELECT u.id FROM users u
       JOIN church_users cu ON cu.user_id = u.id
      WHERE cu.church_id = ANY($1)
        AND (u.full_name ILIKE 'TEST%' OR u.email ILIKE 'TEST%')
        AND NOT EXISTS (
          SELECT 1 FROM church_users cu2
           WHERE cu2.user_id = u.id AND NOT (cu2.church_id = ANY($1))
        )`,
    [egliseIds],
  );
  return rows.map((r) => r.id);
}

function totalSuppression(
  annexes: number,
  comptes: Record<string, number>,
  utilisateurs: number,
): number {
  return (
    1 +
    annexes +
    Object.values(comptes).reduce((a, b) => a + b, 0) +
    utilisateurs
  );
}

export function registerSuppressionEgliseRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/admin/supprimer-eglise",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "super_admin")] },
    async (req, reply) => {
      const body = (req.body ?? {}) as { confirmer?: boolean; eglise_id?: string };
      const confirmer = body.confirmer === true;
      const role = req.session.role;
      const client = await db.connect();
      try {
        // -- Résolution de la cible et gardes de parenté. -----------------
        let cible: EgliseCible;
        let cas: CasSuppression;
        if (body.eglise_id !== undefined && body.eglise_id !== null) {
          if (!/^[0-9a-fA-F-]{36}$/.test(body.eglise_id)) {
            return reply.code(400).send({
              error: "invalid_input",
              message: "Identifiant d'église invalide.",
            });
          }
          const { rows } = await client.query<EgliseCible>(
            `SELECT id, name, code, parent_church_id FROM churches WHERE id = $1`,
            [body.eglise_id],
          );
          if (rows.length === 0) {
            return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
          }
          cible = rows[0];
          if (role === "super_admin") {
            if (cible.parent_church_id === null) {
              return reply.code(409).send({
                error: "pas_une_annexe",
                message: "Le super administrateur ne supprime que des églises locales (annexes), jamais une église de premier niveau.",
              });
            }
            cas = "annexe_super_admin";
          } else if (cible.id === req.session.churchId) {
            if (cible.parent_church_id !== null) {
              return reply.code(409).send({
                error: "annexe_par_la_mere",
                message: "Une église locale ne se supprime pas elle-même : seule son église mère ou le super administrateur peut la supprimer.",
              });
            }
            if (!cible.name.startsWith("TEST")) {
              return reply.code(409).send({
                error: "pas_test",
                message: "Seule une église dont le nom commence par TEST peut être supprimée par elle-même.",
              });
            }
            cas = "auto_test";
          } else {
            if (cible.parent_church_id !== req.session.churchId) {
              return reply.code(403).send({
                error: "forbidden",
                message: "Cette église n'est pas une de vos annexes directes.",
              });
            }
            cas = "annexe_mere";
          }
        } else {
          if (role !== "admin_eglise") {
            return reply.code(400).send({
              error: "invalid_input",
              message: "Le super administrateur doit indiquer l'église à supprimer (eglise_id).",
            });
          }
          const { rows } = await client.query<EgliseCible>(
            `SELECT id, name, code, parent_church_id FROM churches WHERE id = $1`,
            [req.session.churchId],
          );
          if (rows.length === 0) {
            return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
          }
          cible = rows[0];
          if (cible.parent_church_id !== null) {
            return reply.code(409).send({
              error: "annexe_par_la_mere",
              message: "Une église locale ne se supprime pas elle-même : seule son église mère ou le super administrateur peut la supprimer.",
            });
          }
          if (!cible.name.startsWith("TEST")) {
            return reply.code(409).send({
              error: "pas_test",
              message: "Seule une église dont le nom commence par TEST peut être supprimée par elle-même.",
            });
          }
          cas = "auto_test";
        }

        const perimetre = await collecterPerimetre(client, cible.id);
        if (cas === "auto_test") {
          const nonTest = perimetre.find((e) => !e.name.startsWith("TEST"));
          if (nonTest) {
            return reply.code(409).send({
              error: "pas_test",
              message: `L'annexe « ${nonTest.name} » ne commence pas par TEST : la suppression est refusée.`,
            });
          }
        }
        const annexes = perimetre.filter((e) => e.id !== cible.id);
        const egliseIds = perimetre.map((e) => e.id);

        if (!confirmer) {
          const comptes = await compterTables(client, egliseIds);
          const utilisateurs = await collecterUtilisateursTestASupprimer(client, egliseIds);
          return reply.send({
            eglise: { id: cible.id, nom: cible.name, code: cible.code },
            annexes: annexes.map((e) => ({ id: e.id, nom: e.name, code: e.code })),
            comptes,
            utilisateurs_supprimes: utilisateurs.length,
            total: totalSuppression(annexes.length, comptes, utilisateurs.length),
          });
        }

        await client.query("BEGIN");
        try {
          const tableInconnue = await verifierTablesPrisesEnCharge(client);
          if (tableInconnue !== null) {
            throw new Error(`table_non_prise_en_charge:${tableInconnue}`);
          }
          // Relecture dans la transaction : l'aperçu peut dater.
          const perimetreTx = await collecterPerimetre(client, cible.id);
          if (perimetreTx.length !== perimetre.length) {
            throw new Error("perimetre_change");
          }
          const comptes = await compterTables(client, egliseIds);
          const utilisateurs = await collecterUtilisateursTestASupprimer(client, egliseIds);

          // Journal avant les suppressions : les lignes pointent vers
          // l'église de la session, qui peut disparaître ensuite (le
          // journal survit, church_id passe à NULL, les détails gardent
          // le nom et le code de l'église supprimée).
          for (const e of [...perimetre].reverse()) {
            await auditLog(client, {
              churchId: req.session.churchId,
              userId: req.session.userId,
              action: "suppression_eglise.supprime",
              details: { cas, id: e.id, nom: e.name, code: e.code },
            });
          }
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "suppression_eglise.execute",
            details: {
              cas,
              eglise: { nom: cible.name, code: cible.code },
              annexes: annexes.map((e) => ({ nom: e.name, code: e.code })),
              comptes,
              utilisateurs_supprimes: utilisateurs.length,
              total: totalSuppression(annexes.length, comptes, utilisateurs.length),
            },
          });

          // 1. Transferts (RESTRICT sur le membre et sur les églises).
          await client.query(
            `DELETE FROM transferts_membre
              WHERE membre_id IN (SELECT id FROM members WHERE church_id = ANY($1))
                 OR eglise_depart_id = ANY($1) OR eglise_arrivee_id = ANY($1)`,
            [egliseIds],
          );
          // 2. Églises, de la plus profonde à la cible : le reste part en
          // cascade (membres, contributions, campagnes, attestations…).
          for (const e of perimetre) {
            const r = await client.query(`DELETE FROM churches WHERE id = $1`, [e.id]);
            if ((r.rowCount ?? 0) !== 1) throw new Error("eglise_introuvable");
          }
          // 3. Comptes TEST qui n'ont plus aucune église.
          if (utilisateurs.length > 0) {
            await client.query(`DELETE FROM users WHERE id = ANY($1)`, [utilisateurs]);
          }
          // 4. Vérification : plus aucune église du périmètre.
          const { rows: restes } = await client.query<{ n: number }>(
            `SELECT count(*)::int AS n FROM churches WHERE id = ANY($1)`,
            [egliseIds],
          );
          if (restes[0].n !== 0) throw new Error("eglise_restante");

          await client.query("COMMIT");
          return reply.send({
            ok: true,
            eglise: { id: cible.id, nom: cible.name, code: cible.code },
            annexes: annexes.map((e) => ({ id: e.id, nom: e.name, code: e.code })),
            comptes,
            utilisateurs_supprimes: utilisateurs.length,
            total: totalSuppression(annexes.length, comptes, utilisateurs.length),
          });
        } catch (e) {
          await client.query("ROLLBACK");
          throw e;
        }
      } catch (e) {
        const err = e as { code?: string; message?: string };
        if (err?.message?.startsWith("table_non_prise_en_charge:")) {
          const table = err.message.split(":")[1];
          return reply.code(409).send({
            error: "table_non_prise_en_charge",
            message: `Suppression impossible : la table « ${table} » référence les églises et n'est pas prise en charge. Rien n'a été supprimé.`,
          });
        }
        if (err?.message === "perimetre_change" || err?.message === "eglise_introuvable" || err?.message === "eglise_restante") {
          return reply.code(409).send({
            error: "perimetre_change",
            message: "L'église a changé entre l'aperçu et la confirmation : recommencez l'aperçu. Rien n'a été supprimé.",
          });
        }
        if (err?.code === "23503") {
          return reply.code(409).send({
            error: "lien_restant",
            message: "Suppression impossible : un élément est encore lié à une autre donnée. Rien n'a été supprimé.",
          });
        }
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );
}
