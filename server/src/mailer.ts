import nodemailer from "nodemailer";
import type { Transporter } from "nodemailer";

// ---------------------------------------------------------------------------
// Envoi d'e-mails (modules 15-16) : SMTP optionnel.
// Sans configuration SMTP complète, l'envoi est désactivé (false) et
// l'admin transmet les liens lui-même (invitation, lien de réinitialisation).
// Variables : SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM, APP_URL.
//
// Tranche P5 (Lot B) : sendMail accepte des pièces jointes (le PDF du
// rapport d'annexe). Pour les tests, un transport simulé en mémoire
// (streamTransport nodemailer) est disponible : NODE_ENV=test +
// MAIL_TRANSPORT=stream, ou injection directe via
// setTransportCourrielPourTests. Aucun vrai courriel ne part par ces
// chemins.
// ---------------------------------------------------------------------------

export interface MailConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
  /** URL publique de l'application web (liens ?token=...). */
  appUrl: string;
}

export function getMailConfig(): MailConfig | null {
  const host = process.env.SMTP_HOST;
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const from = process.env.SMTP_FROM;
  if (!host || !user || !pass || !from) return null;
  return {
    host,
    port: Number(process.env.SMTP_PORT ?? 587),
    user,
    pass,
    from,
    appUrl: (process.env.APP_URL ?? "http://localhost:8080").replace(/\/+$/, ""),
  };
}

/** L'application est-elle configurée pour envoyer des e-mails ? */
export function mailEnabled(): boolean {
  return getMailConfig() !== null;
}

/** Lien de réinitialisation (le jeton brut ne transite que par ce lien). */
export function resetLink(token: string): string {
  const cfg = getMailConfig();
  const base = cfg?.appUrl ?? "http://localhost:8080";
  return `${base}/reinitialiser?token=${token}`;
}

/** Lien d'initialisation (invitation). */
export function inviteLink(token: string): string {
  const cfg = getMailConfig();
  const base = cfg?.appUrl ?? "http://localhost:8080";
  return `${base}/initialiser?token=${token}`;
}

/** Pièce jointe d'un courriel (PDF, CSV, etc.). */
export interface PieceJointe {
  filename: string;
  content: Buffer;
  contentType: string;
}

// Transport injecté par les tests (en processus) ; nul en production.
let transportInjecte: Transporter | null = null;

/**
 * Tests uniquement : remplace le transport d'envoi par un transport
 * simulé (par exemple un streamTransport nodemailer). Repasser null
 * pour revenir au SMTP configuré.
 */
export function setTransportCourrielPourTests(
  transport: Transporter | null,
): void {
  transportInjecte = transport;
}

function getTransporter(): Transporter | null {
  if (transportInjecte) return transportInjecte;
  // Tests uniquement : transport en mémoire, aucun courriel ne quitte
  // la machine. La double condition évite une activation accidentelle
  // en production (MAIL_TRANSPORT seul ne suffit pas).
  if (
    process.env.NODE_ENV === "test" &&
    process.env.MAIL_TRANSPORT === "stream"
  ) {
    return nodemailer.createTransport({ streamTransport: true, buffer: true });
  }
  const cfg = getMailConfig();
  if (!cfg) return null;
  return nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.port === 465,
    auth: { user: cfg.user, pass: cfg.pass },
  });
}

/**
 * Un transport d'envoi est-il disponible (SMTP configuré ou transport
 * de test) ? Permet à l'appelant de distinguer « SMTP non configuré »
 * d'un échec d'envoi.
 */
export function envoiCourrielDisponible(): boolean {
  return getTransporter() !== null;
}

/**
 * Envoie un e-mail, avec pièces jointes facultatives. Renvoie faux si
 * le SMTP n'est pas configuré ou si l'envoi échoue (l'appelant répond
 * alors `email_envoye: false` sans jamais révéler si le compte existe).
 */
export async function sendMail(
  to: string,
  subject: string,
  text: string,
  piecesJointes: PieceJointe[] = [],
): Promise<boolean> {
  const transporter = getTransporter();
  if (!transporter) return false;
  try {
    const cfg = getMailConfig();
    await transporter.sendMail({
      from: cfg?.from ?? "e-System Church <noreply@e-system-church.local>",
      to,
      subject,
      text,
      attachments: piecesJointes.map((p) => ({
        filename: p.filename,
        content: p.content,
        contentType: p.contentType,
      })),
    });
    return true;
  } catch (e) {
    console.error("[mailer] échec d'envoi vers", to, e);
    return false;
  }
}
