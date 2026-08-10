import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  assertDraftPayloadSafe,
  buildDraftGatewayPayload,
} from "./draftWithAi.ts";

describe("Draft with AI payload", () => {
  it("sends only dialog-entered prompt text under operation draft", () => {
    const payload = buildDraftGatewayPayload("  Please draft a thank-you note  ");
    assert.deepEqual(payload, {
      operation: "draft",
      prompt: "Please draft a thank-you note",
    });
    assertDraftPayloadSafe(payload);
  });

  it("rejects empty prompts", () => {
    assert.throws(() => buildDraftGatewayPayload("   "), /DRAFT_PROMPT_EMPTY/);
  });

  it("rejects chat id, contact, messages, and attachment metadata", () => {
    assert.throws(
      () =>
        assertDraftPayloadSafe({
          operation: "draft",
          prompt: "hi",
          chat_id: "abc",
        }),
      /DRAFT_PAYLOAD_FORBIDDEN:chat_id/,
    );
    assert.throws(
      () =>
        assertDraftPayloadSafe({
          operation: "draft",
          prompt: "hi",
          conversation_id: "abc",
        }),
      /DRAFT_PAYLOAD_FORBIDDEN:conversation_id/,
    );
    assert.throws(
      () =>
        assertDraftPayloadSafe({
          operation: "draft",
          prompt: "hi",
          messages: [{ role: "user", content: "chat" }],
        }),
      /DRAFT_PAYLOAD_FORBIDDEN:messages/,
    );
    assert.throws(
      () =>
        assertDraftPayloadSafe({
          operation: "draft",
          prompt: "hi",
          attachments: [],
        }),
      /DRAFT_PAYLOAD_FORBIDDEN:attachments/,
    );
  });

  it("does not allow elevating draft into chat operation", () => {
    assert.throws(
      () =>
        assertDraftPayloadSafe({
          operation: "chat",
          prompt: "hi",
        }),
      /DRAFT_OPERATION_REQUIRED/,
    );
  });
});

describe("Draft with AI attachment-menu exclusion", () => {
  it("documents that Ask AI must not appear in attachment actions", async () => {
    const fs = await import("node:fs");
    const src = fs.readFileSync(
      new URL("../components/chat/ChatWindow.tsx", import.meta.url),
      "utf8",
    );
    const attachmentBlock = src.slice(
      src.indexOf("const attachmentOptions"),
      src.indexOf("export const ChatWindow"),
    );
    assert.equal(/ask-ai|Ask AI|Draft with AI/.test(attachmentBlock), false);
  });
});
