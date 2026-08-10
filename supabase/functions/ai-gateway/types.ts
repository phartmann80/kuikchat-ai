export type ChatRole = "user" | "assistant" | "system";

export interface ChatMessage {
  role: ChatRole;
  content: string;
}

export type GatewayChatRequest = {
  operation: "chat";
  conversation_id?: string;
  messages: ChatMessage[];
  metadata?: {
    language?: string;
  };
};

export type GatewayDraftRequest = {
  operation: "draft";
  /** Single user-entered draft brief. No chat context. */
  prompt: string;
};

export type GatewayRequest = GatewayChatRequest | GatewayDraftRequest;

export interface TokenUsage {
  input: number | null;
  output: number | null;
}

export interface ProviderResult {
  provider: "langdock" | "logicc";
  model: string;
  content: string;
  usage: TokenUsage;
  latencyMs: number;
  fallbackUsed: boolean;
  fallbackReason: string | null;
}

export interface RateLimitReservation {
  allowed: boolean;
  hour_remaining: number;
  day_remaining: number;
}
