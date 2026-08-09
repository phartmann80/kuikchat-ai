/**
 * Resolve the chat UUID used for message load/send.
 * Never falls back to a profile/contact identity UUID.
 */
export function resolveChatIdForMessaging(
  chatId?: string | null,
  contactChatId?: string | null,
): string | null {
  const fromProp = typeof chatId === "string" ? chatId.trim() : "";
  if (fromProp) return fromProp;

  const fromContact = typeof contactChatId === "string" ? contactChatId.trim() : "";
  if (fromContact) return fromContact;

  return null;
}

export function assertResolvedChatId(
  chatId?: string | null,
  contactChatId?: string | null,
): string {
  const resolved = resolveChatIdForMessaging(chatId, contactChatId);
  if (!resolved) {
    throw new Error("CHAT_ID_UNRESOLVED");
  }
  return resolved;
}
