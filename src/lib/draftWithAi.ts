/**
 * Client helpers for the nonpersistent Draft with AI gateway operation.
 * Never sends chat IDs, contact identity, chat history, or attachments.
 */

export type DraftGatewayResponse = {
  request_id: string;
  operation: "draft";
  persistent: false;
  message: { role: "assistant"; content: string };
  provider: string;
};

export type DraftGatewayError = {
  code: string;
  message: string;
  request_id?: string;
};

export function buildDraftGatewayPayload(prompt: string): {
  operation: "draft";
  prompt: string;
} {
  const trimmed = prompt.trim();
  if (!trimmed) {
    throw new Error("DRAFT_PROMPT_EMPTY");
  }
  return {
    operation: "draft",
    prompt: trimmed,
  };
}

/** Ensures accidental chat context never enters the draft payload. */
export function assertDraftPayloadSafe(payload: Record<string, unknown>): void {
  const forbidden = [
    "conversation_id",
    "messages",
    "chat_id",
    "contact_id",
    "contact",
    "attachments",
    "selected_text",
  ];
  for (const key of forbidden) {
    if (key in payload && payload[key] != null) {
      throw new Error(`DRAFT_PAYLOAD_FORBIDDEN:${key}`);
    }
  }
  if (payload.operation !== "draft") {
    throw new Error("DRAFT_OPERATION_REQUIRED");
  }
  if (typeof payload.prompt !== "string") {
    throw new Error("DRAFT_PROMPT_REQUIRED");
  }
}

export async function requestDraftGeneration(args: {
  supabaseUrl: string;
  accessToken: string;
  prompt: string;
  signal?: AbortSignal;
}): Promise<DraftGatewayResponse> {
  const payload = buildDraftGatewayPayload(args.prompt);
  assertDraftPayloadSafe(payload);

  const response = await fetch(`${args.supabaseUrl}/functions/v1/ai-gateway`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${args.accessToken}`,
    },
    body: JSON.stringify(payload),
    signal: args.signal,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const err = (data as { error?: DraftGatewayError })?.error;
    const error = new Error(err?.message || "Failed to generate draft.");
    (error as Error & { code?: string }).code = err?.code || "PROVIDER_UNAVAILABLE";
    throw error;
  }

  if (
    (data as DraftGatewayResponse).operation !== "draft" ||
    (data as DraftGatewayResponse).persistent !== false
  ) {
    throw new Error("Unexpected draft response shape.");
  }

  return data as DraftGatewayResponse;
}
