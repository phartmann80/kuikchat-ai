import {
  ProviderRequestError,
  emitProviderWarning,
  runWithFailover,
} from "./providers.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const baseConfig = {
  langdock: {
    name: "langdock" as const,
    endpoint: "https://langdock.test/chat",
    apiKey: "test-langdock-key",
    model: "gpt-test",
  },
  logicc: {
    name: "logicc" as const,
    endpoint: "https://logicc.test/chat",
    apiKey: "test-logicc-key",
    model: "logicc-test",
  },
  enableLogiccFallback: false,
  maxOutputTokens: 100,
  timeoutMs: 1_000,
  correlationId: "corr-test-1",
};

function completion(content: string, model: string) {
  return new Response(
    JSON.stringify({
      model,
      choices: [{ message: { content } }],
      usage: { prompt_tokens: 4, completion_tokens: 2 },
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

Deno.test("uses Langdock when the primary provider succeeds", async () => {
  const warnings: unknown[] = [];
  const calls: string[] = [];
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    warn: (payload) => warnings.push(payload),
    fetcher: (input) => {
      calls.push(String(input));
      return Promise.resolve(completion("Primary", "gpt-test"));
    },
  });
  assert(result.provider === "langdock", "expected Langdock");
  assert(result.fallbackUsed === false, "fallback should not be marked as used");
  assert(calls.length === 1, "only Langdock should be invoked");
  assert(warnings.length === 0, "no warning on primary success");
});

Deno.test("Langdock failure does not call Logicc when fallback is disabled", async () => {
  const calls: string[] = [];
  let thrown: unknown;
  try {
    await runWithFailover([{ role: "user", content: "Hello" }], {
      ...baseConfig,
      enableLogiccFallback: false,
      warn: () => {},
      fetcher: (input) => {
        calls.push(String(input));
        return Promise.resolve(new Response("unauthorized", { status: 401 }));
      },
    });
  } catch (error) {
    thrown = error;
  }
  assert(calls.length === 1, "Logicc must not be called when disabled");
  assert(thrown instanceof ProviderRequestError, "expected ProviderRequestError");
  assert((thrown as ProviderRequestError).provider === "langdock", "error from Langdock");
  assert((thrown as ProviderRequestError).code === "PROVIDER_AUTH_ERROR", "auth error");
});

Deno.test("Langdock 401 triggers Logicc when fallback is explicitly enabled", async () => {
  const warnings: Array<{ fallback_provider: string | null; code: string }> = [];
  const calls: string[] = [];
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    enableLogiccFallback: true,
    warn: (payload) => warnings.push(payload),
    fetcher: (input) => {
      const url = String(input);
      calls.push(url);
      return Promise.resolve(
        url.includes("langdock.test")
          ? new Response("unauthorized", { status: 401 })
          : completion("Fallback after auth", "logicc-test"),
      );
    },
  });
  assert(calls.length === 2, "both providers should be called");
  assert(result.provider === "logicc", "expected Logicc after Langdock 401");
  assert(result.fallbackUsed === true, "fallback should be marked");
  assert(warnings[0]?.fallback_provider === "logicc", "warning fallback must be logicc");
  assert(warnings[0]?.code === "PROVIDER_AUTH_ERROR", "warning code must be auth error");
});

Deno.test("EMPTY_RESPONSE from Langdock does not invoke Logicc even when enabled", async () => {
  const calls: string[] = [];
  let thrown: unknown;
  try {
    await runWithFailover([{ role: "user", content: "Hello" }], {
      ...baseConfig,
      enableLogiccFallback: true,
      warn: () => {},
      fetcher: (input) => {
        calls.push(String(input));
        return Promise.resolve(
          new Response(
            JSON.stringify({
              model: "gpt-test",
              choices: [{ message: { content: "   " } }],
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          ),
        );
      },
    });
  } catch (error) {
    thrown = error;
  }
  assert(calls.length === 1, "Logicc must not be called for EMPTY_RESPONSE");
  assert(thrown instanceof ProviderRequestError, "expected ProviderRequestError");
  assert(
    (thrown as ProviderRequestError).code === "EMPTY_RESPONSE",
    "expected EMPTY_RESPONSE code",
  );
});

Deno.test("provider warning payload never includes secrets or prompts", () => {
  const warnings: Record<string, unknown>[] = [];
  emitProviderWarning(
    {
      event: "AI_PROVIDER_FAILURE",
      provider: "langdock",
      code: "PROVIDER_AUTH_ERROR",
      fallback_provider: null,
      correlationId: "cid-9",
    },
    (payload) => {
      warnings.push(payload as unknown as Record<string, unknown>);
    },
  );
  const payload = warnings[0];
  assert(payload, "warning expected");
  const keys = Object.keys(payload).sort();
  assert(
    JSON.stringify(keys) ===
      JSON.stringify([
        "code",
        "correlation_id",
        "event",
        "fallback_provider",
        "provider",
        "timestamp",
      ]),
    "unexpected warning keys",
  );
  const serialized = JSON.stringify(payload);
  assert(!serialized.includes("sk-"), "must not contain key material");
  assert(!serialized.includes("Bearer"), "must not contain auth headers");
  assert(!serialized.includes("prompt"), "must not contain prompt text");
});
