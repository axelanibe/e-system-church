import type { Pool, PoolClient } from "pg";

/**
 * Aides partagées par les routes HTTP de la messagerie (T-Msg-0) et par
 * le WebSocket (T-Msg-1) : fiche membre de l'appelant et vérification
 * de participation active à une conversation, dans son église.
 */

/** Fiche membre liée au compte de l'appelant, ou null. */
export async function ficheMembre(
  db: Pool | PoolClient,
  userId: string,
): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [userId],
  );
  return rows[0]?.member_id ?? null;
}

/** Vrai si la fiche membre est participante active de la conversation. */
export async function estParticipantActif(
  db: Pool | PoolClient,
  churchId: string,
  conversationId: string,
  memberId: string,
): Promise<boolean> {
  const { rows } = await db.query(
    `SELECT 1 FROM conversation_participants cp
      JOIN conversations c ON c.id = cp.conversation_id
     WHERE cp.conversation_id = $1 AND c.church_id = $2
       AND cp.member_id = $3 AND cp.is_active = true`,
    [conversationId, churchId, memberId],
  );
  return rows.length > 0;
}
