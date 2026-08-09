import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { resolveChatIdForMessaging } from "./resolveChatId.ts";

describe("resolveChatIdForMessaging", () => {
  it("returns an explicit chatId prop", () => {
    assert.equal(
      resolveChatIdForMessaging("11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"),
      "11111111-1111-1111-1111-111111111111",
    );
  });

  it("uses contact.chat_id when prop is missing", () => {
    assert.equal(
      resolveChatIdForMessaging(null, "22222222-2222-2222-2222-222222222222"),
      "22222222-2222-2222-2222-222222222222",
    );
  });

  it("never accepts a profile/contact id fallback argument", () => {
    // Callers must not pass contact.id; absence of chat ids fails closed.
    const profileId = "33333333-3333-3333-3333-333333333333";
    assert.equal(resolveChatIdForMessaging(undefined, undefined), null);
    assert.equal(resolveChatIdForMessaging("", ""), null);
    assert.equal(resolveChatIdForMessaging(null, null), null);
    // Documented contract: profile UUID is not a parameter of this helper.
    assert.notEqual(
      resolveChatIdForMessaging(undefined, undefined),
      profileId,
    );
  });

  it("fails closed when chat resolution is missing so no message insert path can use a profile UUID", () => {
    const chatId = resolveChatIdForMessaging(null, undefined);
    assert.equal(chatId, null);
    // Simulates composer guard: no insert when unresolved.
    const wouldInsert = Boolean(chatId);
    assert.equal(wouldInsert, false);
  });
});
