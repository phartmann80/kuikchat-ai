import {
  AI_LIMITS,
  parseGatewayRequest,
  RequestValidationError,
} from "./guardrails.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts and trims a valid chat request", () => {
  const request = parseGatewayRequest({
    operation: "chat",
    messages: [{ role: "user", content: "  Hello  " }],
  });
  assert(request.operation === "chat", "expected chat");
  if (request.operation === "chat") {
    assert(request.messages[0].content === "Hello", "message was not trimmed");
  }
});

Deno.test("rejects requests above the total character limit", () => {
  let rejected = false;
  try {
    parseGatewayRequest({
      operation: "chat",
      messages: Array.from({ length: 4 }, () => ({
        role: "user",
        content: "x".repeat(AI_LIMITS.maxCharactersPerMessage),
      })),
    });
  } catch (error) {
    rejected = error instanceof RequestValidationError;
  }
  assert(rejected, "oversized request should be rejected");
});

Deno.test("accepts a draft request with prompt only", () => {
  const request = parseGatewayRequest({
    operation: "draft",
    prompt: "  Write a polite follow-up  ",
  });
  assert(request.operation === "draft", "expected draft");
  if (request.operation === "draft") {
    assert(request.prompt === "Write a polite follow-up", "prompt trimmed");
  }
});

Deno.test("rejects draft requests that include conversation_id or messages", () => {
  let rejectedConv = false;
  try {
    parseGatewayRequest({
      operation: "draft",
      prompt: "Hello",
      conversation_id: "00000000-0000-0000-0000-000000000001",
    });
  } catch (error) {
    rejectedConv = error instanceof RequestValidationError;
  }
  assert(rejectedConv, "conversation_id must be rejected");

  let rejectedMessages = false;
  try {
    parseGatewayRequest({
      operation: "draft",
      prompt: "Hello",
      messages: [{ role: "user", content: "secret chat" }],
    });
  } catch (error) {
    rejectedMessages = error instanceof RequestValidationError;
  }
  assert(rejectedMessages, "messages must be rejected");
});

Deno.test("rejects draft requests with chat context fields", () => {
  let rejected = false;
  try {
    parseGatewayRequest({
      operation: "draft",
      prompt: "Hello",
      chat_id: "00000000-0000-0000-0000-000000000002",
    });
  } catch (error) {
    rejected = error instanceof RequestValidationError;
  }
  assert(rejected, "chat_id must be rejected");
});
