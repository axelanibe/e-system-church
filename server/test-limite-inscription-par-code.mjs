/* Test tranche 2 — code fidèle énumérable : limitation de débit sur
 * POST /auth/inscription-par-code (audit sécurité, moyenne).
 * Sans PostgreSQL : le crochet onRequest s'exécute avant tout accès
 * base, le serveur démarre avec une DATABASE_URL injoignable (le Pool
 * pg est paresseux) et les 20 premières tentatives échouent en 500
 * côté gestionnaire — ce qui est attendu ici — puis la 21e est bloquée
 * en 429 par le limiteur.
 * Usage : node test-limite-inscription-par-code.mjs
 */
import { spawn } from "node:child_process";

const BASE = "http://127.0.0.1:3115";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const server = spawn("npx", ["tsx", "src/index.ts"], {
  cwd: process.cwd(),
  env: { ...process.env, PORT: "3115", DATABASE_URL: "postgres://127.0.0.1:1/inexistant", JWT_SECRET: "test-secret-limite-32-caracteres" },
  stdio: "ignore",
  detached: true,
});
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const post = async (code, xff) => {
    const r = await fetch(`${BASE}/auth/inscription-par-code`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(xff ? { "X-Forwarded-For": xff } : {}) },
      body: JSON.stringify({ nom_prenom: "Sonde Test", email: "sonde@example.ci", telephone: "+225747123499", mot_de_passe: "Sonde123!", code_eglise: code }),
    });
    return { status: r.status, retryAfter: r.headers.get("retry-after"), d: await r.text().then((t) => { try { return JSON.parse(t); } catch { return t; } }) };
  };

  console.log("Balayage de 25 codes depuis la même IP :");
  const statuts = [];
  for (let i = 0; i < 25; i++) {
    const r = await post(`ESC-F-${String(i).padStart(4, "0")}`);
    statuts.push(r.status);
  }
  check("20 premières tentatives non bloquées par le limiteur", statuts.slice(0, 20).every((s) => s !== 429), `statuts=${statuts.join(",")}`);
  check("21e à 25e tentatives bloquées en 429", statuts.slice(20).every((s) => s === 429), `statuts=${statuts.join(",")}`);
  const r429 = await post("ESC-F-9999");
  check("429 avec error=trop_de_tentatives", r429.status === 429 && r429.d.error === "trop_de_tentatives", JSON.stringify(r429.d).slice(0, 200));
  check("429 avec en-tête Retry-After", r429.status === 429 && Number(r429.retryAfter) > 0 && Number(r429.retryAfter) <= 900, `retry-after=${r429.retryAfter}`);

  console.log("Autre IP, même route :");
  const rAutreIp = await post("ESC-F-0000", "203.0.113.9");
  check("autre IP non bloquée (compteur par IP)", rAutreIp.status !== 429, `status=${rAutreIp.status}`);

  console.log("Autres routes non limitées :");
  const rSante = await fetch(`${BASE}/sante`);
  check("GET /sante toujours 200", rSante.status === 200, `status=${rSante.status}`);
} finally {
  try { process.kill(-server.pid); } catch {}
}
console.log(`\nLimite inscription par code : ${ok} OK, ${ko} KO.`);
process.exit(ko > 0 ? 1 : 0);
