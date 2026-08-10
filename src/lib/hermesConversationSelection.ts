export type HermesConversationSummary = {
  id: string;
  title: string | null;
  updated_at: string;
};

export type HermesMessageLike = {
  id: string;
  role: string;
  content: string;
};

/**
 * Deterministic conversation selection for Hermes bootstrap.
 * Never accepts foreign IDs: caller must pass only ownership-verified candidates.
 */
export function selectHermesConversationId(args: {
  preferredId: string | null | undefined;
  conversations: HermesConversationSummary[];
}): string | null {
  const { preferredId, conversations } = args;
  if (!conversations.length) return null;

  if (preferredId) {
    const match = conversations.find((c) => c.id === preferredId);
    if (match) return match.id;
  }

  // conversations are expected newest-first
  return conversations[0]?.id ?? null;
}

export function shouldShowNewChatHero(args: {
  conversationsLoaded: boolean;
  conversationCount: number;
  selectedId: string | null;
  forceNewChat: boolean;
}): boolean {
  if (args.forceNewChat) return true;
  if (!args.conversationsLoaded) return false;
  if (args.conversationCount === 0) return true;
  return args.selectedId === null;
}

/** True when a newer load/bootstrap has superseded this request. */
export function isStaleHermesRequest(requestSeq: number, latestSeq: number): boolean {
  return requestSeq !== latestSeq;
}

/**
 * Ownership gate: only accept conversation rows owned by the authenticated user.
 * Invalid/unauthorized IDs must not be rendered.
 */
export function acceptOwnedConversation(args: {
  requestedId: string;
  row: { id: string; user_id: string } | null | undefined;
  authUserId: string;
}): { ok: true; id: string } | { ok: false; reason: "not_found_or_unauthorized" } {
  if (!args.row || args.row.id !== args.requestedId || args.row.user_id !== args.authUserId) {
    return { ok: false, reason: "not_found_or_unauthorized" };
  }
  return { ok: true, id: args.row.id };
}

/** Append a message only when its id is not already present. */
export function appendUniqueHermesMessage<T extends HermesMessageLike>(
  messages: T[],
  next: T,
): T[] {
  if (messages.some((m) => m.id === next.id)) return messages;
  return [...messages, next];
}

/** History UI must never remain a permanent loading stub after a list failure. */
export function historyStatusAfterListFailure(): "error" {
  return "error";
}

export function historyStatusAfterRetryStart(): "loading" {
  return "loading";
}
