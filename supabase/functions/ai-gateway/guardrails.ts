import type { ChatMessage, GatewayRequest } from "./types.ts";

export const AI_LIMITS = {
  maxMessages: 20,
  maxCharacters: 12_000,
  maxCharactersPerMessage: 4_000,
  maxDraftCharacters: 4_000,
  maxOutputTokens: 800,
  providerTimeoutMs: 30_000,
  requestsPerHour: 30,
  requestsPerDay: 100,
} as const;

export const DRAFT_SYSTEM_INSTRUCTION =
  "You help the user draft a message. Use only the description they provide. Do not claim to read their chat, contacts, or attachments. Return only the draft message text.";

export class RequestValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RequestValidationError";
  }
}

function isChatMessage(value: unknown): value is ChatMessage {
  if (!value || typeof value !== "object") return false;
  const message = value as Record<string, unknown>;
  return (
    (message.role === "user" || message.role === "assistant") &&
    typeof message.content === "string"
  );
}

function assertNoChatContextFields(body: Record<string, unknown>, operation: string): void {
  const forbidden = [
    "chat_id",
    "contact_id",
    "contact",
    "attachments",
    "selected_text",
    "system",
    "instructions",
  ];
  for (const key of forbidden) {
    if (key in body && body[key] != null) {
      throw new RequestValidationError(
        `Field "${key}" is not allowed for ${operation} requests.`,
      );
    }
  }
}

function parseChatRequest(body: Record<string, unknown>): GatewayRequest {
  assertNoChatContextFields(body, "chat");

  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    throw new RequestValidationError("At least one message is required.");
  }

  if (body.messages.length > AI_LIMITS.maxMessages) {
    throw new RequestValidationError(
      `A maximum of ${AI_LIMITS.maxMessages} messages is allowed.`,
    );
  }

  if (!body.messages.every(isChatMessage)) {
    throw new RequestValidationError(
      "Messages must contain a valid role and text content.",
    );
  }

  const messages = body.messages.map((message) => ({
    role: message.role,
    content: message.content.trim(),
  }));

  if (messages.some((message) => message.content.length === 0)) {
    throw new RequestValidationError("Message content cannot be empty.");
  }

  if (
    messages.some((message) =>
      message.content.length > AI_LIMITS.maxCharactersPerMessage
    )
  ) {
    throw new RequestValidationError(
      `Each message is limited to ${AI_LIMITS.maxCharactersPerMessage} characters.`,
    );
  }

  const totalCharacters = messages.reduce(
    (total, message) => total + message.content.length,
    0,
  );
  if (totalCharacters > AI_LIMITS.maxCharacters) {
    throw new RequestValidationError(
      `The request is limited to ${AI_LIMITS.maxCharacters} characters.`,
    );
  }

  const conversation_id = typeof body.conversation_id === "string"
    ? body.conversation_id
    : undefined;

  return { operation: "chat", conversation_id, messages };
}

function parseDraftRequest(body: Record<string, unknown>): GatewayRequest {
  assertNoChatContextFields(body, "draft");

  // Reject any attempt to turn draft into persisted chat.
  if ("conversation_id" in body && body.conversation_id != null) {
    throw new RequestValidationError(
      "conversation_id is not allowed for draft requests.",
    );
  }
  if ("messages" in body && body.messages != null) {
    throw new RequestValidationError(
      "messages is not allowed for draft requests. Use prompt.",
    );
  }

  if (typeof body.prompt !== "string") {
    throw new RequestValidationError("A draft prompt string is required.");
  }

  const prompt = body.prompt.trim();
  if (!prompt) {
    throw new RequestValidationError("Draft prompt cannot be empty.");
  }
  if (prompt.length > AI_LIMITS.maxDraftCharacters) {
    throw new RequestValidationError(
      `Draft prompt is limited to ${AI_LIMITS.maxDraftCharacters} characters.`,
    );
  }

  return { operation: "draft", prompt };
}

export function parseGatewayRequest(value: unknown): GatewayRequest {
  if (!value || typeof value !== "object") {
    throw new RequestValidationError("Request body must be an object.");
  }

  const body = value as Record<string, unknown>;
  if (body.operation === "chat") return parseChatRequest(body);
  if (body.operation === "draft") return parseDraftRequest(body);

  throw new RequestValidationError("Only chat and draft operations are available.");
}
