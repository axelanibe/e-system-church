import nodemailer from "nodemailer";

// ---------------------------------------------------------------------------
// Envoi d'e-mails (modules 15-16) : SMTP optionnel.
// Sans configuration SMTP complète, l'envoi est désactivé (false) et
// l'admin transmet les liens lui-même (invitation, lien de réinitialisation).
// Variables : SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM, APP_URL.
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

/**
 * Envoie un e-mail. Renvoie faux si le SMTP n'est pas configuré ou si
 * l'envoi échoue (l'appelant répond alors `email_envoye: false` sans
 * jamais révéler si le compte existe).
 */
export async function sendMail(
  to: string,
  subject: string,
  text: string,
): Promise<boolean> {
  const cfg = getMailConfig();
  if (!cfg) return false;
  try {
    const transporter = nodemailer.createTransport({
      host: cfg.host,
      port: cfg.port,
      secure: cfg.port === 465,
      auth: { user: cfg.user, pass: cfg.pass },
    });
    await transporter.sendMail({ from: cfg.from, to, subject, text });
    return true;
  } catch (e) {
    console.error("[mailer] échec d'envoi vers", to, e);
    return false;
  }
}
