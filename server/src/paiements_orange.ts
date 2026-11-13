/**
 * Adaptateur Orange Money — notifications WebPayment (tranche T8).
 *
 * Rappel du flux (Orange Developer, om-webpay) : le marchand appelle
 * POST .../webpayment avec merchant_key, currency, order_id, amount,
 * return_url, cancel_url, notif_url et lang ; Orange répond un pay_token,
 * une payment_url et un **notif_token**. Le client paie sur payment_url ;
 * Orange POSTe ensuite une notification sur notif_url, qui porte le
 * notif_token, l'identifiant de transaction et le statut.
 *
 * L'exécution Orange (webpayment) n'existe pas encore dans l'application
 * (paiements.ts renvoie 501 pour orange_money) : le pay_token n'est donc
 * stocké nulle part aujourd'hui. Le webhook ne peut pas re-interroger
 * Orange (transactionstatus exige order_id + montant + pay_token) — il
 * résout la contribution par la référence (order_id / identifiant de
 * transaction, qui doit être la payment_ref enregistrée à la création)
 * et ne confirme que si le statut est SUCCESS et que le montant
 * correspond. Quand l'exécution Orange sera branchée, il faudra stocker
 * le pay_token à la création et ajouter ici la re-interrogation
 * transactionstatus avant toute confirmation.
 *
 * Statuts Orange : INITIATED, PENDING, EXPIRED, SUCCESS, FAILED.
 */

export interface NotificationOrange {
  /** Jeton de notification (à comparer à celui émis à la création). */
  notifToken: string | null;
  /** Identifiant de transaction Orange (id de la notification). */
  transactionId: string | null;
  /** order_id du marchand — c'est la référence de la contribution. */
  orderId: string | null;
  /** pay_token, si Orange le renvoie dans la notification. */
  payToken: string | null;
  statut: string;
  montant: number;
  devise: string;
}

function chaine(valeur: unknown): string | null {
  if (typeof valeur === "string" && valeur.length > 0) return valeur;
  if (typeof valeur === "number") return String(valeur);
  return null;
}

function nombre(valeur: unknown): number {
  if (typeof valeur === "number") return valeur;
  if (typeof valeur === "string") {
    const n = Number(valeur);
    return Number.isFinite(n) ? n : NaN;
  }
  return NaN;
}

/**
 * Extrait les champs utiles d'une notification Orange. Les noms de
 * champs varient selon les versions de l'API (notif_token / token,
 * transaction_id / id, order_id / ref_commande…) — on accepte les
 * variantes connues. Retourne null si le corps n'est pas un objet
 * JSON exploitable.
 */
export function analyserNotificationOrange(
  body: unknown,
): NotificationOrange | null {
  if (typeof body !== "object" || body === null) return null;
  const b = body as Record<string, unknown>;
  const statut = chaine(b.statut ?? b.status);
  if (!statut) return null;
  return {
    notifToken: chaine(b.notif_token ?? b.notifToken ?? b.token),
    transactionId: chaine(
      b.transaction_id ?? b.transactionId ?? b.id ?? b.txn_id,
    ),
    orderId: chaine(b.order_id ?? b.orderId ?? b.ref_commande ?? b.reference),
    payToken: chaine(b.pay_token ?? b.payToken),
    statut,
    montant: nombre(b.amount ?? b.montant),
    devise: chaine(b.currency ?? b.devise) ?? "",
  };
}

/** Vrai si le statut Orange signifie un paiement réussi. */
export function estSuccesOrange(statut: string): boolean {
  return statut.toUpperCase() === "SUCCESS";
}

/** Vrai si le statut Orange signifie un échec définitif. */
export function estEchecOrange(statut: string): boolean {
  const s = statut.toUpperCase();
  return s === "FAILED" || s === "EXPIRED";
}
