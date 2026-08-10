export type HermesConversationSummary = {
  id: string;
  title: string | null;
  updated_at: string;
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
