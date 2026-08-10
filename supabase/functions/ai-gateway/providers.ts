import type { ChatMessage, ProviderResult, TokenUsage } from "./types.ts";

export type ProviderName = "langdock" | "logicc";

export interface ProviderConfig {
  name: ProviderName;
  endpoint: string;
  apiKey: string;
  model: string;
}

export interface ProviderRunConfig {
  langdock: ProviderConfig;
  /** Optional secondary text provider. Not used until explicitly enabled. */
  logicc?: ProviderConfig | null;
  /** When true, skip Langdock. Requires an enabled Logicc config. */
  langdockDisabled?: boolean;
  /** When true and Logicc is configured, use Logicc after Langdock failure (except EMPTY_RESPONSE). */
  enableLogiccFallback?: boolean;
  /** Server-defined system instruction only — never taken from the client body. */
  systemInstruction?: string;
  maxOutputTokens: number;
  timeoutMs: number;
  fetcher?: typeof fetch;
  correlationId?: string;
  warn?: (payload: ProviderWarning) => void;
}

export interface ProviderWarning {
  event: "AI_PROVIDER_FAILURE" | "AI_PROVIDER_FAILOVER";
  provider: ProviderName;
  code: string;
  fallback_provider: ProviderName | null;
  timestamp: string;
  correlation_id: string | null;
}

interface ProviderResponse {
  model?: string;
  choices?: Array<{
    message?: { content?: string };
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
}

export class ProviderRequestError extends Error {
  readonly provider: ProviderName;
  readonly code: string;

  constructor(provider: ProviderName, code: string) {
    super(`${provider} request failed`);
    this.name = "ProviderRequestError";
    this.provider = provider;
    this.code = code;
  }
}

/** Errors that must not trigger secondary-provider failover. */
const NON_FAILOVER_CODES = new Set(["EMPTY_RESPONSE"]);

function normalizeUsage(response: ProviderResponse): TokenUsage {
  return {
    input: typeof response.usage?.prompt_tokens === "number"
      ? response.usage.prompt_tokens
      : null,
    output: typeof response.usage?.completion_tokens === "number"
      ? response.usage.completion_tokens
      : null,
  };
}

export function emitProviderWarning(
  args: {
    event: ProviderWarning["event"];
    provider: ProviderName;
    code: string;
    fallback_provider: ProviderName | null;
    correlationId?: string | null;
  },
  warn: (payload: ProviderWarning) => void = console.warn,
): void {
  warn({
    event: args.event,
    provider: args.provider,
    code: args.code,
    fallback_provider: args.fallback_provider,
    timestamp: new Date().toISOString(),
    correlation_id: args.correlationId ?? null,
  });
}

/** @deprecated Use emitProviderWarning. Kept for test migration clarity. */
export function emitFailoverWarning(
  code: string,
  correlationId: string | null | undefined,
  warn: (payload: ProviderWarning) => void = console.warn,
): void {
  emitProviderWarning(
    {
      event: "AI_PROVIDER_FAILOVER",
      provider: "langdock",
      code,
      fallback_provider: "logicc",
      correlationId,
    },
    warn,
  );
}

const DEFAULT_SYSTEM_INSTRUCTION =
  "You are KuikChat AI. Give a helpful, accurate, concise answer. Do not claim to perform actions you did not perform.";

export async function requestProvider(
  provider: ProviderConfig,
  messages: ChatMessage[],
  maxOutputTokens: number,
  timeoutMs: number,
  fetcher: typeof fetch,
  systemInstruction: string = DEFAULT_SYSTEM_INSTRUCTION,
): Promise<Omit<ProviderResult, "fallbackUsed" | "fallbackReason">> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const startedAt = Date.now();

  try {
    const response = await fetcher(provider.endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${provider.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        messages: [
          {
            role: "system",
            content: systemInstruction,
          },
          ...messages,
        ],
        ...(provider.name === "langdock"
          ? { max_completion_tokens: maxOutputTokens }
          : { max_tokens: maxOutputTokens }),
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      let code = "PROVIDER_ERROR";
      if (response.status === 401 || response.status === 403) code = "PROVIDER_AUTH_ERROR";
      else if (response.status === 429) code = "PROVIDER_RATE_LIMITED";
      else if (response.status >= 500) code = "PROVIDER_UNAVAILABLE";

      throw new ProviderRequestError(provider.name, code);
    }

    const payload = (await response.json()) as ProviderResponse;
    const content = payload.choices?.[0]?.message?.content?.trim();
    if (!content) {
      throw new ProviderRequestError(provider.name, "EMPTY_RESPONSE");
    }

    return {
      provider: provider.name,
      model: payload.model ?? provider.model,
      content,
      usage: normalizeUsage(payload),
      latencyMs: Date.now() - startedAt,
    };
  } catch (error) {
    if (error instanceof ProviderRequestError) throw error;
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ProviderRequestError(provider.name, "TIMEOUT");
    }
    throw new ProviderRequestError(provider.name, "NETWORK_ERROR");
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Langdock is the production Hermes text provider.
 * Logicc failover is code-ready but disabled unless enableLogiccFallback + logicc config are set.
 */
export async function runWithFailover(
  messages: ChatMessage[],
  config: ProviderRunConfig,
): Promise<ProviderResult> {
  const fetcher = config.fetcher ?? fetch;
  const logiccEnabled = Boolean(
    config.enableLogiccFallback && config.logicc?.apiKey && config.logicc?.endpoint && config.logicc?.model,
  );
  let fallbackReason: string | null = null;

  const systemInstruction = config.systemInstruction ?? DEFAULT_SYSTEM_INSTRUCTION;

  if (!config.langdockDisabled) {
    try {
      const result = await requestProvider(
        config.langdock,
        messages,
        config.maxOutputTokens,
        config.timeoutMs,
        fetcher,
        systemInstruction,
      );
      return { ...result, fallbackUsed: false, fallbackReason: null };
    } catch (error) {
      if (error instanceof ProviderRequestError) {
        if (NON_FAILOVER_CODES.has(error.code) || !logiccEnabled) {
          emitProviderWarning(
            {
              event: "AI_PROVIDER_FAILURE",
              provider: "langdock",
              code: error.code,
              fallback_provider: null,
              correlationId: config.correlationId,
            },
            config.warn,
          );
          throw error;
        }
        fallbackReason = error.code;
        emitProviderWarning(
          {
            event: "AI_PROVIDER_FAILOVER",
            provider: "langdock",
            code: error.code,
            fallback_provider: "logicc",
            correlationId: config.correlationId,
          },
          config.warn,
        );
      } else if (!logiccEnabled) {
        throw error;
      } else {
        fallbackReason = "LANGDOCK_UNKNOWN_ERROR";
        emitProviderWarning(
          {
            event: "AI_PROVIDER_FAILOVER",
            provider: "langdock",
            code: fallbackReason,
            fallback_provider: "logicc",
            correlationId: config.correlationId,
          },
          config.warn,
        );
      }
    }
  } else if (!logiccEnabled) {
    throw new ProviderRequestError("langdock", "LANGDOCK_DISABLED");
  } else {
    fallbackReason = "LANGDOCK_DISABLED";
    emitProviderWarning(
      {
        event: "AI_PROVIDER_FAILOVER",
        provider: "langdock",
        code: fallbackReason,
        fallback_provider: "logicc",
        correlationId: config.correlationId,
      },
      config.warn,
    );
  }

  // Logicc path — only reached when explicitly enabled.
  const logicc = config.logicc!;
  const result = await requestProvider(
    logicc,
    messages,
    config.maxOutputTokens,
    config.timeoutMs,
    fetcher,
    systemInstruction,
  );
  return { ...result, fallbackUsed: true, fallbackReason };
}
