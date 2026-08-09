import {
  ProviderRequestError,
  emitFailoverWarning,
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
  openrouter: {
    name: "openrouter" as const,
    endpoint: "https://openrouter.test/chat",
    apiKey: "test-openrouter-key",
    model: "openrouter/free",
  },
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
  assert(calls.length === 1, "OpenRouter must not be invoked on Langdock success");
  assert(warnings.length === 0, "no failover warning on primary success");
});

Deno.test("falls back to OpenRouter when Langdock is unavailable", async () => {
  const warnings: Array<{ code: string }> = [];
  const calls: string[] = [];
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    warn: (payload) => warnings.push(payload),
    fetcher: (input) => {
      const url = String(input);
      calls.push(url);
      return Promise.resolve(
        url.includes("langdock.test")
          ? new Response("unavailable", { status: 503 })
          : completion("Fallback", "free-model"),
      );
    },
  });
  assert(calls.length === 2, "both providers should be called");
  assert(result.provider === "openrouter", "expected OpenRouter fallback");
  assert(result.fallbackUsed === true, "fallback should be marked as used");
  assert(
    result.fallbackReason === "PROVIDER_UNAVAILABLE",
    "fallback reason should be normalized code",
  );
  assert(warnings[0]?.code === "PROVIDER_UNAVAILABLE", "warning should carry code");
});

Deno.test("Langdock 401 triggers OpenRouter fallback", async () => {
  const warnings: Array<{
    event: string;
    provider: string;
    code: string;
    fallback_provider: string;
    correlation_id: string | null;
  }> = [];
  const calls: string[] = [];
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    warn: (payload) => warnings.push(payload),
    fetcher: (input) => {
      const url = String(input);
      calls.push(url);
      return Promise.resolve(
        url.includes("langdock.test")
          ? new Response("unauthorized", { status: 401 })
          : completion("Fallback after auth", "free-model"),
      );
    },
  });
  assert(calls.length === 2, "both providers should be called");
  assert(result.provider === "openrouter", "expected OpenRouter after Langdock 401");
  assert(result.fallbackReason === "PROVIDER_AUTH_ERROR", "expected auth fallback reason");
  assert(warnings.length === 1, "one structured warning expected");
  assert(warnings[0].event === "AI_PROVIDER_FAILOVER", "expected failover event");
  assert(warnings[0].provider === "langdock", "warning provider must be langdock");
  assert(warnings[0].fallback_provider === "openrouter", "warning fallback must be openrouter");
  assert(warnings[0].code === "PROVIDER_AUTH_ERROR", "warning code must be auth error");
  assert(warnings[0].correlation_id === "corr-test-1", "correlation id must be present");
});

Deno.test("Langdock 403 triggers OpenRouter fallback", async () => {
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    warn: () => {},
    fetcher: (input) => {
      const url = String(input);
      return Promise.resolve(
        url.includes("langdock.test")
          ? new Response("forbidden", { status: 403 })
          : completion("Fallback after 403", "free-model"),
      );
    },
  });
  assert(result.provider === "openrouter", "expected OpenRouter after Langdock 403");
  assert(result.fallbackReason === "PROVIDER_AUTH_ERROR", "expected auth fallback reason");
});

Deno.test("EMPTY_RESPONSE from Langdock does not invoke OpenRouter", async () => {
  const calls: string[] = [];
  let thrown: unknown;
  try {
    await runWithFailover([{ role: "user", content: "Hello" }], {
      ...baseConfig,
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
  assert(calls.length === 1, "OpenRouter must not be called for EMPTY_RESPONSE");
  assert(thrown instanceof ProviderRequestError, "expected ProviderRequestError");
  assert(
    (thrown as ProviderRequestError).code === "EMPTY_RESPONSE",
    "expected EMPTY_RESPONSE code",
  );
});

Deno.test("double-provider failure surfaces OpenRouter error code", async () => {
  let thrown: unknown;
  try {
    await runWithFailover([{ role: "user", content: "Hello" }], {
      ...baseConfig,
      warn: () => {},
      fetcher: (input) => {
        const url = String(input);
        return Promise.resolve(
          url.includes("langdock.test")
            ? new Response("unauthorized", { status: 401 })
            : new Response("unauthorized", { status: 401 }),
        );
      },
    });
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof ProviderRequestError, "expected ProviderRequestError");
  assert((thrown as ProviderRequestError).provider === "openrouter", "final error from OpenRouter");
  assert(
    (thrown as ProviderRequestError).code === "PROVIDER_AUTH_ERROR",
    "expected auth error after both fail",
  );
});

Deno.test("operational circuit breaker skips Langdock", async () => {
  let calls = 0;
  const warnings: Array<{ code: string }> = [];
  const result = await runWithFailover([{ role: "user", content: "Hello" }], {
    ...baseConfig,
    langdockDisabled: true,
    warn: (payload) => warnings.push(payload),
    fetcher: () => {
      calls += 1;
      return Promise.resolve(completion("Fallback", "free-model"));
    },
  });
  assert(calls === 1, "only OpenRouter should be called");
  assert(result.provider === "openrouter", "expected OpenRouter");
  assert(
    result.fallbackReason === "LANGDOCK_DISABLED",
    "expected circuit-breaker reason",
  );
  assert(warnings[0]?.code === "LANGDOCK_DISABLED", "warning for disabled primary");
});

Deno.test("failover warning payload never includes secrets or prompts", () => {
  const warnings: Record<string, unknown>[] = [];
  emitFailoverWarning("PROVIDER_AUTH_ERROR", "cid-9", (payload) => {
    warnings.push(payload as unknown as Record<string, unknown>);
  });
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
