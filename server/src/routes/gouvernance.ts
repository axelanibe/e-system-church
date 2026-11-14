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
 * Tranche T10 — Gouvernance, secrétariat, documents, action sociale.
 *
 * Mandats et nominations (un mandat garde sa décision de nomination
 * quand elle existe), réunions du conseil, décisions, procès-verbaux,
 * documents (statuts, règlements, modèles et courriers entrants /
 * sortants, avec recherche), bénéficiaires et suivi des aides.
 * Les signataires des nominations et des procès-verbaux sont
 * configurables par église (eglise_parametres, vides par défaut :
 * la règle de signature n'est pas tranchée, rien n'est inventé).
 * Le patrimoine (biens_patrimoine, maintenance_patrimoine) vit dans
 * biens.ts, à côté des salles et du matériel.
 */

const uuid = z.string().uuid();
const dateSeule = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.");

export function registerGouvernanceRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/reunions-conseil",
    table: "reunions_conseil",
    columns: ["titre", "date_reunion", "lieu", "ordre_du_jour", "statut"],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      date_reunion: z.string().min(10).max(40),
      lieu: z.string().max(200).optional(),
      ordre_du_jour: z.string().max(2000).optional(),
      statut: z.enum(["prevue", "tenue", "annulee"]).default("prevue"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "reunion_conseil",
    filters: { statut: "statut" },
    orderBy: "date_reunion DESC",
    searchColumn: "titre",
  });

  registerCrud(app, db, {
    base: "/decisions",
    table: "decisions",
    columns: ["reunion_id", "titre", "description", "date_decision", "statut"],
    createSchema: z.object({
      reunion_id: uuid.optional(),
      titre: z.string().min(2).max(200),
      description: z.string().max(2000).optional(),
      date_decision: dateSeule.optional(),
      statut: z.enum(["adoptee", "rejetee", "reportee"]).default("adoptee"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "decision",
    filters: { statut: "statut", reunion_id: "reunion_id" },
    orderBy: "date_decision DESC",
    searchColumn: "titre",
    validate: async (db2, churchId, data) => {
      if (
        data.reunion_id &&
        !(await existsInChurch(db2, "reunions_conseil", churchId, data.reunion_id as string))
      ) {
        return "Réunion introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/mandats",
    table: "mandats",
    columns: ["member_id", "fonction", "date_debut", "date_fin", "statut", "decision_id"],
    createSchema: z.object({
      member_id: uuid,
      fonction: z.string().min(2).max(120),
      date_debut: dateSeule,
      date_fin: dateSeule.optional(),
      statut: z.enum(["en_cours", "termine"]).default("en_cours"),
      decision_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "mandat",
    filters: { statut: "statut" },
    orderBy: "date_debut DESC",
    searchColumn: "fonction",
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Le membre n'appartient pas à votre église.";
      }
      if (
        data.decision_id &&
        !(await existsInChurch(db2, "decisions", churchId, data.decision_id as string))
      ) {
        return "Décision introuvable dans votre église.";
      }
      if (
        data.date_fin &&
        (data.date_fin as string) < (data.date_debut as string)
      ) {
        return "La fin du mandat doit être après son début.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/proces-verbaux",
    table: "proces_verbaux",
    columns: ["reunion_id", "numero", "contenu", "date_pv", "signataire", "statut"],
    createSchema: z.object({
      reunion_id: uuid.optional(),
      numero: z.string().max(60).optional(),
      contenu: z.string().min(2).max(20000),
      date_pv: dateSeule.optional(),
      signataire: z.string().max(200).optional(),
      statut: z.enum(["brouillon", "signe", "archive"]).default("brouillon"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "proces_verbal",
    filters: { statut: "statut", reunion_id: "reunion_id" },
    orderBy: "date_pv DESC",
    searchColumn: "numero",
    validate: async (db2, churchId, data) => {
      if (
        data.reunion_id &&
        !(await existsInChurch(db2, "reunions_conseil", churchId, data.reunion_id as string))
      ) {
        return "Réunion introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/documents",
    table: "documents",
    columns: [
      "titre",
      "categorie",
      "sens",
      "reference",
      "fichier_url",
      "description",
      "date_document",
    ],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      categorie: z
        .enum(["statuts", "reglement", "decision", "courrier", "modele", "autre"])
        .default("autre"),
      sens: z.enum(["entrant", "sortant", "interne"]).optional(),
      reference: z.string().max(120).optional(),
      fichier_url: z.string().url().max(500).optional(),
      description: z.string().max(2000).optional(),
      date_document: dateSeule.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "document",
    filters: { categorie: "categorie", sens: "sens" },
    orderBy: "date_document DESC NULLS LAST, created_at DESC",
    searchColumn: "titre",
  });

  registerCrud(app, db, {
    base: "/beneficiaires",
    table: "beneficiaires",
    columns: ["nom", "telephone", "adresse", "besoin", "statut", "member_id"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      telephone: z.string().max(30).optional(),
      adresse: z.string().max(300).optional(),
      besoin: z.string().max(2000).optional(),
      statut: z.enum(["actif", "clos"]).default("actif"),
      member_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "beneficiaire",
    filters: { statut: "statut" },
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (
        data.member_id &&
        !(await memberInChurch(db2, churchId, data.member_id as string))
      ) {
        return "Le membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/aides",
    table: "aides",
    columns: [
      "beneficiaire_id",
      "type_aide",
      "montant_fcfa",
      "date_aide",
      "description",
      "statut",
    ],
    createSchema: z.object({
      beneficiaire_id: uuid,
      type_aide: z.enum(["vivres", "financier", "medical", "autre"]),
      montant_fcfa: z.number().int().min(0).max(100_000_000).optional(),
      date_aide: dateSeule.optional(),
      description: z.string().max(2000).optional(),
      statut: z.enum(["prevue", "versee", "annulee"]).default("prevue"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "aide",
    filters: {
      statut: "statut",
      beneficiaire_id: "beneficiaire_id",
      type_aide: "type_aide",
    },
    orderBy: "date_aide DESC",
    validate: async (db2, churchId, data) => {
      if (
        !(await existsInChurch(db2, "beneficiaires", churchId, data.beneficiaire_id as string))
      ) {
        return "Bénéficiaire introuvable dans votre église.";
      }
      return null;
    },
  });
}
