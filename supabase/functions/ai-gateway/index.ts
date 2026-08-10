import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.89.0";
import {
  AI_LIMITS,
  DRAFT_SYSTEM_INSTRUCTION,
  parseGatewayRequest,
  RequestValidationError,
} from "./guardrails.ts";
import { ProviderRequestError, runWithFailover } from "./providers.ts";
import type { RateLimitReservation } from "./types.ts";

const ALLOWED_ORIGINS = new Set([
  "https://kuikchat.io",
  "https://www.kuikchat.io",
  "http://localhost:5173",
]);

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allowed = ALLOWED_ORIGINS.has(origin) || origin.endsWith(".vercel.app");
  return {
    "Access-Control-Allow-Origin": allowed ? origin : "https://kuikchat.io",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function jsonResponse(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`MISSING_CONFIG: ${name}`);
  return value;
}

async function reserveAiRequest(
  supabaseUrl: string,
  serviceRoleKey: string,
  args: { p_user_id: string; p_request_id: string; p_operation: string; p_hour_limit: number; p_day_limit: number },
): Promise<RateLimitReservation> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/reserve_ai_request`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error("QUOTA_RPC_FAILURE");
  return (await response.json()) as RateLimitReservation;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return jsonResponse(req, { error: { code: "METHOD_NOT_ALLOWED" } }, 405);

  const requestId = crypto.randomUUID();

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse(req, { error: { code: "UNAUTHORIZED", message: "Auth required." } }, 401);
    }

    const token = authHeader.substring(7);
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) {
      console.error("[AUTH-FAILURE]", authError?.name || "invalid_session");
      return jsonResponse(req, { error: { code: "UNAUTHORIZED", message: "Invalid session." } }, 401);
    }

    const langdockKey = requiredEnv("LANGDOCK_API_KEY");
    const langdockModel = requiredEnv("LANGDOCK_MODEL");
    const langdockDisabled = Deno.env.get("AI_LANGDOCK_DISABLED") === "true";
    const logiccKey = Deno.env.get("LOGICC_API_KEY")?.trim() || "";
    const logiccEndpoint = Deno.env.get("LOGICC_ENDPOINT_URL")?.trim() || "";
    const logiccModel = Deno.env.get("LOGICC_MODEL")?.trim() || "";
    const enableLogiccFallback = Deno.env.get("AI_LOGICC_FALLBACK_ENABLED") === "true";

    const body = await req.json().catch(() => {
      throw new RequestValidationError("Invalid JSON");
    });
    const gatewayRequest = parseGatewayRequest(body);

    // Usage ledger currently accepts only operation 'chat'. Draft shares that quota pool
    // without creating ai_conversations / ai_messages rows.
    const reservation = await reserveAiRequest(supabaseUrl, serviceRoleKey, {
      p_user_id: user.id,
      p_request_id: requestId,
      p_operation: "chat",
      p_hour_limit: AI_LIMITS.requestsPerHour,
      p_day_limit: AI_LIMITS.requestsPerDay,
    });

    if (!reservation.allowed) {
      return jsonResponse(req, { error: { code: "RATE_LIMITED", message: "Quota exceeded." } }, 429);
    }

    const providerConfig = {
      langdock: {
        name: "langdock" as const,
        endpoint: "https://api.langdock.com/openai/eu/v1/chat/completions",
        apiKey: langdockKey,
        model: langdockModel,
      },
      logicc: logiccKey && logiccEndpoint && logiccModel
        ? {
          name: "logicc" as const,
          endpoint: `${logiccEndpoint.replace(/\/$/, "")}/chat/completions`,
          apiKey: logiccKey,
          model: logiccModel,
        }
        : null,
      enableLogiccFallback,
      langdockDisabled,
      maxOutputTokens: AI_LIMITS.maxOutputTokens,
      timeoutMs: AI_LIMITS.providerTimeoutMs,
      correlationId: requestId,
      warn: (payload: unknown) => {
        console.warn("[AI-PROVIDER]", JSON.stringify(payload));
      },
    };

    if (gatewayRequest.operation === "draft") {
      const result = await runWithFailover(
        [{ role: "user", content: gatewayRequest.prompt }],
        {
          ...providerConfig,
          systemInstruction: DRAFT_SYSTEM_INSTRUCTION,
        },
      );

      // Nonpersistent by design: no ai_conversations / ai_messages writes.
      return jsonResponse(req, {
        request_id: requestId,
        operation: "draft",
        persistent: false,
        message: { role: "assistant", content: result.content },
        provider: result.provider,
        usage: result.usage,
      });
    }

    let conversationId = gatewayRequest.conversation_id;

    if (conversationId) {
      const { data: convExists, error: convCheckError } = await authClient
        .from("ai_conversations")
        .select("id")
        .eq("id", conversationId)
        .single();

      if (convCheckError || !convExists) {
        return jsonResponse(req, {
          error: { code: "UNAUTHORIZED", message: "Conversation not found or access denied." },
        }, 404);
      }
    } else {
      const firstMsg = gatewayRequest.messages[0]?.content || "";
      const title = firstMsg.slice(0, 100) || "New Conversation";
      const { data: newConv, error: createError } = await authClient
        .from("ai_conversations")
        .insert({ user_id: user.id, title })
        .select("id")
        .single();

      if (createError || !newConv) {
        console.error("[CONVERSATION-CREATE-ERROR]", createError?.code || "create_failed");
        return jsonResponse(req, {
          error: { code: "SERVER_ERROR", message: "Failed to create conversation." },
        }, 500);
      }
      conversationId = newConv.id;
    }

    const lastMessage = gatewayRequest.messages[gatewayRequest.messages.length - 1];
    if (lastMessage && lastMessage.role === "user") {
      const { error: msgInsertError } = await authClient
        .from("ai_messages")
        .insert({
          conversation_id: conversationId,
          role: lastMessage.role,
          content: lastMessage.content,
        });

      if (msgInsertError) {
        console.error("[MESSAGE-INSERT-ERROR]", msgInsertError.code || "insert_failed");
        return jsonResponse(req, {
          error: { code: "SERVER_ERROR", message: "Failed to save message." },
        }, 500);
      }
    }

    const result = await runWithFailover(gatewayRequest.messages, providerConfig);

    const { error: assistantInsertError } = await authClient
      .from("ai_messages")
      .insert({
        conversation_id: conversationId,
        role: "assistant",
        content: result.content,
      });

    if (assistantInsertError) {
      console.error("[ASSISTANT-INSERT-ERROR]", assistantInsertError.code || "insert_failed");
    }

    return jsonResponse(req, {
      request_id: requestId,
      conversation_id: conversationId,
      operation: "chat",
      persistent: true,
      message: { role: "assistant", content: result.content },
      provider: result.provider,
      usage: result.usage,
    });
  } catch (error: unknown) {
    if (error instanceof ProviderRequestError) {
      console.error(
        `[AI-GATEWAY-ERROR] ID: ${requestId} | provider=${error.provider} code=${error.code}`,
      );
    } else {
      const name = error instanceof Error ? error.name : "Error";
      console.error(`[AI-GATEWAY-ERROR] ID: ${requestId} | ${name}`);
    }

    if (error instanceof Error && error.message.includes("MISSING_CONFIG")) {
      return jsonResponse(req, {
        error: {
          code: "SERVER_CONFIG_ERROR",
          message: "Internal configuration error.",
          request_id: requestId,
        },
      }, 500);
    }
    if (error instanceof RequestValidationError) {
      return jsonResponse(req, {
        error: { code: "INVALID_REQUEST", message: error.message, request_id: requestId },
      }, 400);
    }
    if (error instanceof ProviderRequestError) {
      const mapping: Record<string, string> = {
        PROVIDER_AUTH_ERROR: "SERVER_CONFIG_ERROR",
        PROVIDER_RATE_LIMITED: "RATE_LIMITED",
        PROVIDER_UNAVAILABLE: "PROVIDER_UNAVAILABLE",
      };
      return jsonResponse(req, {
        error: {
          code: mapping[error.code] || "PROVIDER_UNAVAILABLE",
          message: "AI service error.",
          request_id: requestId,
        },
      }, 503);
    }

    return jsonResponse(req, {
      error: {
        code: "SERVER_ERROR",
        message: "An unexpected error occurred.",
        request_id: requestId,
      },
    }, 500);
  }
});
