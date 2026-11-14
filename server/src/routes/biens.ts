import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  READ_ALL,
  WRITE_STD,
  existsInChurch,
  memberInChurch,
  registerCrud,
} from "../crud.js";

/**
 * Module 10 — Biens et inventaire : salles et réservations (avec contrôle
 * de chevauchement), matériel et sa maintenance.
 */

const uuid = z.string().uuid();

export function registerBiensRoutes(app: FastifyInstance, db: Pool) {
  // Tranche T10 — Patrimoine : bâtiments et biens avec valeur,
  // assurance, photo et code d'inventaire ; maintenance reliée aux
  // dépenses (depense_id facultatif, dépense de la même église).
  registerCrud(app, db, {
    base: "/biens-patrimoine",
    table: "biens_patrimoine",
    columns: ["nom", "categorie", "valeur_fcfa", "assurance", "photo_url", "code_inventaire"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      categorie: z.enum(["batiment", "terrain", "vehicule", "equipement", "autre"]),
      valeur_fcfa: z.number().int().min(0).max(10_000_000_000).optional(),
      assurance: z.string().max(300).optional(),
      photo_url: z.string().url().max(500).optional(),
      code_inventaire: z.string().max(60).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "bien_patrimoine",
    filters: { categorie: "categorie" },
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/maintenance-patrimoine",
    table: "maintenance_patrimoine",
    columns: ["bien_id", "date_maintenance", "description", "cout_fcfa", "realise_par", "depense_id"],
    createSchema: z.object({
      bien_id: uuid,
      date_maintenance: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
      description: z.string().min(2).max(1000),
      cout_fcfa: z.number().int().min(0).max(100_000_000).optional(),
      realise_par: z.string().max(200).optional(),
      depense_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "maintenance_patrimoine",
    filters: { bien_id: "bien_id" },
    orderBy: "date_maintenance DESC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "biens_patrimoine", churchId, data.bien_id as string))) {
        return "Bien introuvable dans votre église.";
      }
      if (
        data.depense_id &&
        !(await existsInChurch(db2, "depenses", churchId, data.depense_id as string))
      ) {
        return "Dépense introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/salles",
    table: "salles",
    columns: ["nom", "capacite", "description"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      capacite: z.number().int().min(0).max(100000).optional(),
      description: z.string().max(500).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "salle",
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/reservations-salles",
    table: "reservations_salles",
    columns: ["salle_id", "titre", "debut", "fin", "reserve_par", "statut"],
    createSchema: z.object({
      salle_id: uuid,
      titre: z.string().min(2).max(200),
      debut: z.string().min(10).max(40),
      fin: z.string().min(10).max(40),
      reserve_par: z.string().max(200).optional(),
      statut: z.enum(["confirmee", "annulee"]).default("confirmee"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "reservation_salle",
    filters: { salle_id: "salle_id", statut: "statut" },
    orderBy: "debut ASC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "salles", churchId, data.salle_id as string))) {
        return "Salle introuvable dans votre église.";
      }
      if (data.statut === "confirmee") {
        const { rowCount } = await db2.query(
          `SELECT 1 FROM reservations_salles
            WHERE salle_id = $1 AND church_id = $2 AND statut = 'confirmee'
              AND debut < $4::timestamptz AND fin > $3::timestamptz`,
          [data.salle_id, churchId, data.debut, data.fin],
        );
        if ((rowCount ?? 0) > 0) return "Cette salle est déjà réservée sur ce créneau.";
      }
      return null;
    },
    // Lot B, tranche 1 : le contrôle de chevauchement n'existait qu'à la
    // création ; le PATCH générique pouvait créer un chevauchement. On
    // revalide la réservation résultante (valeurs modifiées + valeurs
    // actuelles) avant toute modification.
    validateUpdate: async (db2, churchId, id, data) => {
      const { rows } = await db2.query(
        `SELECT salle_id, debut, fin, statut FROM reservations_salles
          WHERE id = $1 AND church_id = $2`,
        [id, churchId],
      );
      if (rows.length === 0) return null; // le PATCH répondra 404 lui-même.
      const actuelle = rows[0] as { salle_id: string; debut: string; fin: string; statut: string };
      const salleId = (data.salle_id as string) ?? actuelle.salle_id;
      const debut = (data.debut as string) ?? actuelle.debut;
      const fin = (data.fin as string) ?? actuelle.fin;
      const statut = (data.statut as string) ?? actuelle.statut;
      if (!(await existsInChurch(db2, "salles", churchId, salleId))) {
        return "Salle introuvable dans votre église.";
      }
      if (new Date(fin).getTime() <= new Date(debut).getTime()) {
        return "La fin de la réservation doit être après son début.";
      }
      if (statut === "confirmee") {
        const { rowCount } = await db2.query(
          `SELECT 1 FROM reservations_salles
            WHERE salle_id = $1 AND church_id = $2 AND statut = 'confirmee' AND id <> $5
              AND debut < $4::timestamptz AND fin > $3::timestamptz`,
          [salleId, churchId, debut, fin, id],
        );
        if ((rowCount ?? 0) > 0) return "Cette salle est déjà réservée sur ce créneau.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/materiel",
    table: "materiel",
    columns: ["nom", "categorie", "quantite", "etat", "responsable_member_id"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      categorie: z.string().max(120).optional(),
      quantite: z.number().int().min(0).max(100000).default(1),
      etat: z.enum(["bon", "a_reparer", "hors_service"]).default("bon"),
      responsable_member_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "materiel",
    filters: { categorie: "categorie", etat: "etat" },
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (data.responsable_member_id && !(await memberInChurch(db2, churchId, data.responsable_member_id as string))) {
        return "Le responsable n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/maintenance-materiel",
    table: "maintenance_materiel",
    columns: ["materiel_id", "date_maintenance", "description", "cout_fcfa", "realise_par"],
    createSchema: z.object({
      materiel_id: uuid,
      date_maintenance: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
      description: z.string().min(2).max(1000),
      cout_fcfa: z.number().int().min(0).max(100_000_000).optional(),
      realise_par: z.string().max(200).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "maintenance_materiel",
    filters: { materiel_id: "materiel_id" },
    orderBy: "date_maintenance DESC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "materiel", churchId, data.materiel_id as string))) {
        return "Matériel introuvable dans votre église.";
      }
      return null;
    },
  });
}
