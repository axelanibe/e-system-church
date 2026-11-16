import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import type { Pool } from "pg";

/**
 * Notifications push FCM (tranche Notifications push FCM).
 *
 * Provenance de la configuration Firebase : le compte de service est lu
 * depuis la variable d'environnement FIREBASE_SERVICE_ACCOUNT_JSON (JSON
 * complet, jamais dans le dépôt, jamais en clair dans le code). Il vient
 * du projet Firebase séparé « e-system-church », dans le même compte
 * Google que CONNEXION PROPHÉTIQUE, et non du projet
 * « connexion-prophetique » lui-même, pour ne pas mélanger les
 * notifications des deux applications. Le projet est créé par Axel ;
 * ce module ne crée aucun projet Firebase.
 *
 * Comportement sans configuration : si le compte de service est absent
 * ou invalide, l'envoi est désactivé proprement et journalisé, sans
 * casser l'envoi du message ni renvoyer d'erreur au client. La
 * notification ne fait jamais échouer la création du message :
 * `notifierNouveauMessage` ne relance jamais d'exception.
 */

const APERCU_MAX = 100;

/** Codes FCM qui signifient que le jeton ne servira plus jamais. */
const CODES_JETON_INVALIDE = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export interface ResultatNotification {
  /** Nombre de jetons auxquels la notification a été remise. */
  envoye: number;
  /** Nombre de jetons actifs trouvés pour les destinataires. */
  jetons: number;
  /** Vrai quand FCM est désactivé (compte de service absent ou invalide). */
  desactive: boolean;
}

type TransportFcm = (
  jetons: string[],
  charge: { titre: string; corps: string; conversationId: string },
) => Promise<{ livres: string[]; invalides: string[] }>;

/** Transport réel : un appel multicast, jeton par jeton. */
async function transportReel(
  jetons: string[],
  charge: { titre: string; corps: string; conversationId: string },
): Promise<{ livres: string[]; invalides: string[] }> {
  const reponse = await getMessaging().sendEachForMulticast({
    tokens: jetons,
    notification: { title: charge.titre, body: charge.corps },
    data: { conversation_id: charge.conversationId, type: "nouveau_message" },
  });
  const livres: string[] = [];
  const invalides: string[] = [];
  reponse.responses.forEach((r, i) => {
    if (r.success) {
      livres.push(jetons[i]);
    } else if (r.error && CODES_JETON_INVALIDE.has(r.error.code)) {
      invalides.push(jetons[i]);
    }
    // Autre échec (jeton temporairement indisponible, quota) : le jeton
    // reste actif, la prochaine notification réessaiera.
  });
  return { livres, invalides };
}

let transportPourTest: TransportFcm | null = null;
/** Remplace le transport réel par une simulation (tests en processus). */
export function definirTransportFcmPourTest(transport: TransportFcm | null): void {
  transportPourTest = transport;
}

/** État de l'initialisation Firebase, calculé une seule fois. */
let etatFcm: "inconnu" | "actif" | "desactive" = "inconnu";
/** Remet à zéro l'état (tests : changement de variable d'environnement). */
export function reinitialiserFcmPourTest(): void {
  etatFcm = "inconnu";
  transportPourTest = null;
}

/** Initialise Firebase Admin une fois, ou null si désactivé. */
function obtenirMessaging(): boolean {
  if (etatFcm === "actif") return true;
  if (etatFcm === "desactive") return false;
  const brut = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!brut) {
    console.warn(
      "FCM désactivé : variable FIREBASE_SERVICE_ACCOUNT_JSON absente, aucune notification push ne sera envoyée.",
    );
    etatFcm = "desactive";
    return false;
  }
  try {
    const compte = JSON.parse(brut) as {
      project_id?: unknown;
      private_key?: unknown;
      client_email?: unknown;
    };
    if (
      typeof compte.project_id !== "string" ||
      typeof compte.private_key !== "string" ||
      typeof compte.client_email !== "string"
    ) {
      throw new Error("compte de service incomplet (project_id, private_key, client_email attendus)");
    }
    if (getApps().length === 0) {
      initializeApp({
        credential: cert({
          projectId: compte.project_id,
          // La clé privée arrive avec des « \n » littéraux dans le JSON :
          // ils deviennent de vrais retours à la ligne ici.
          privateKey: compte.private_key.replace(/\\n/g, "\n"),
          clientEmail: compte.client_email,
        }),
      });
    }
    etatFcm = "actif";
    return true;
  } catch (e) {
    console.warn(
      "FCM désactivé : compte de service FIREBASE_SERVICE_ACCOUNT_JSON invalide, aucune notification push ne sera envoyée.",
      e instanceof Error ? e.message : e,
    );
    etatFcm = "desactive";
    return false;
  }
}

/**
 * Aperçu du message pour le corps de la notification : texte nettoyé,
 * tronqué à 100 caractères. Le titre ne porte jamais de contenu de
 * message, seulement le titre de la conversation.
 */
export function apercuMessage(contenu: string): string {
  const propre = contenu.replace(/\s+/g, " ").trim();
  if (propre.length <= APERCU_MAX) return propre;
  return `${propre.slice(0, APERCU_MAX)}…`;
}

/**
 * Notifie les participants actifs d'une conversation (sauf l'expéditeur)
 * qu'un message vient d'être créé. Ne relance jamais d'exception : en
 * cas de panne FCM, l'envoi est journalisé et le message reste créé.
 * Un jeton qui répond invalid-registration ou not-registered est marqué
 * inactif ; un jeton livré voit son dernier usage mis à jour.
 */
export async function notifierNouveauMessage(
  db: Pool,
  args: {
    churchId: string;
    conversationId: string;
    expediteurMemberId: string;
    titre: string;
    contenu: string;
  },
): Promise<ResultatNotification> {
  const vide: ResultatNotification = { envoye: 0, jetons: 0, desactive: false };
  try {
    const { rows } = await db.query<{ token: string }>(
      `SELECT DISTINCT dt.token
         FROM device_tokens dt
         JOIN conversation_participants cp
           ON cp.member_id = dt.member_id
          AND cp.conversation_id = $2
        WHERE dt.church_id = $1 AND cp.church_id = $1
          AND cp.is_active = true
          AND dt.member_id <> $3 AND dt.is_active = true
          AND (cp.muted_until IS NULL OR cp.muted_until <= NOW())`,
      [args.churchId, args.conversationId, args.expediteurMemberId],
    );
    const jetons = rows.map((r) => r.token);
    if (jetons.length === 0) return vide;
    const charge = {
      titre: args.titre,
      corps: apercuMessage(args.contenu),
      conversationId: args.conversationId,
    };
    let livres: string[];
    let invalides: string[];
    if (transportPourTest) {
      ({ livres, invalides } = await transportPourTest(jetons, charge));
    } else {
      if (!obtenirMessaging()) return { envoye: 0, jetons: jetons.length, desactive: true };
      ({ livres, invalides } = await transportReel(jetons, charge));
    }
    if (invalides.length > 0) {
      await db.query(
        `UPDATE device_tokens SET is_active = false WHERE church_id = $1 AND token = ANY($2)`,
        [args.churchId, invalides],
      );
    }
    if (livres.length > 0) {
      await db.query(
        `UPDATE device_tokens SET last_used_at = NOW() WHERE church_id = $1 AND token = ANY($2)`,
        [args.churchId, livres],
      );
    }
    return { envoye: livres.length, jetons: jetons.length, desactive: false };
  } catch (e) {
    console.error("FCM : échec de l'envoi de la notification, message conservé.", e);
    return { envoye: 0, jetons: 0, desactive: false };
  }
}
