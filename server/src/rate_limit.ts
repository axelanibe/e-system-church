// Limitation de débit en mémoire, par IP, pour les routes publiques
// d'inscription (correctif « code fidèle énumérable », tranche 2) :
// le code fidèle ESC-F-XXXX ne compte que 10 000 valeurs et
// POST /auth/inscription-par-code distingue le code invalide (404
// invalid_code) du code valide (409 email_taken) sans créer de compte —
// sans limite, un balayage anonyme énumère tous les codes en ~20 s.
// 20 tentatives par IP et par fenêtre de 15 minutes : un usage légitime
// (1 à 2 essais) passe toujours, un balayage exigerait ~5 jours par IP.
// Sans nouvelle dépendance, sans base de données : le compteur vit en
// mémoire du processus (un redémarrage le remet à zéro, ce qui est
// acceptable pour un garde-fou, pas pour un quota contractuel).
// Sur Render (une seule instance), la fenêtre est partagée par tout le
// trafic de l'instance.
import type { FastifyReply, FastifyRequest } from "fastify";

const FENETRE_MS = 15 * 60 * 1000;
const MAX_TENTATIVES = 20;

const compteurs = new Map<string, { debut: number; nombre: number }>();

function nettoyer(): void {
  const maintenant = Date.now();
  for (const [ip, c] of compteurs) {
    if (maintenant - c.debut >= FENETRE_MS) compteurs.delete(ip);
  }
}

/**
 * IP cliente : derrière Render, `X-Forwarded-For` porte la chaîne des
 * relais et Render y ajoute l'IP réelle du client en dernière position —
 * on prend donc la DERNIÈRE entrée (un attaquant peut forger les
 * premières, pas celle qu'ajoute le relais). Sans en-tête (local, tests),
 * on retombe sur `req.ip`. L'IP ne sert qu'à clé de compteur, jamais à
 * une décision d'authentification.
 */
function ipCliente(req: FastifyRequest): string {
  const xff = req.headers["x-forwarded-for"];
  const chaine = Array.isArray(xff) ? xff.join(",") : (xff ?? "");
  const dernier = chaine
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
    .at(-1);
  return dernier ?? req.ip;
}

/**
 * Crochet `onRequest` (Fastify) : ne limite que
 * POST /auth/inscription-par-code, laisse passer tout le reste.
 * Au-delà du quota : 429 `trop_de_tentatives` + en-tête `Retry-After`
 * (secondes restantes dans la fenêtre). Le compteur s'incrémente AVANT
 * le gestionnaire, donc les sondes par code invalide comptent aussi.
 */
export function limiterInscriptionParCode(
  req: FastifyRequest,
  reply: FastifyReply,
  done: (err?: Error) => void,
): void {
  if (req.method !== "POST") return done();
  const chemin = req.url.split("?")[0];
  if (chemin !== "/auth/inscription-par-code") return done();
  nettoyer();
  const ip = ipCliente(req);
  const maintenant = Date.now();
  const compteur = compteurs.get(ip);
  if (!compteur || maintenant - compteur.debut >= FENETRE_MS) {
    compteurs.set(ip, { debut: maintenant, nombre: 1 });
    return done();
  }
  compteur.nombre += 1;
  if (compteur.nombre > MAX_TENTATIVES) {
    const restantes = Math.ceil(
      (FENETRE_MS - (maintenant - compteur.debut)) / 1000,
    );
    reply.header("Retry-After", String(restantes));
    reply.code(429).send({
      error: "trop_de_tentatives",
      message:
        "Trop de tentatives d'inscription. Réessayez dans quelques minutes.",
    });
    return;
  }
  return done();
}
