import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  acceptOwnedConversation,
  appendUniqueHermesMessage,
  historyStatusAfterListFailure,
  historyStatusAfterRetryStart,
  isStaleHermesRequest,
  selectHermesConversationId,
  shouldShowNewChatHero,
} from "./hermesConversationSelection.ts";

const convs = [
  { id: "c-new", title: "Newest", updated_at: "2026-08-10T12:00:00Z" },
  { id: "c-old", title: "Older", updated_at: "2026-08-09T12:00:00Z" },
];

describe("selectHermesConversationId — reload existing", () => {
  it("reloads the preferred conversation when it exists", () => {
    assert.equal(
      selectHermesConversationId({ preferredId: "c-old", conversations: convs }),
      "c-old",
    );
  });
});

describe("selectHermesConversationId — multiple conversations", () => {
  it("selects preferred among multiple, else most recent", () => {
    assert.equal(
      selectHermesConversationId({ preferredId: "c-old", conversations: convs }),
      "c-old",
    );
    assert.equal(
      selectHermesConversationId({ preferredId: null, conversations: convs }),
      "c-new",
    );
  });
});

describe("selectHermesConversationId — new user", () => {
  it("returns null when user has no history", () => {
    assert.equal(selectHermesConversationId({ preferredId: "x", conversations: [] }), null);
  });
});

describe("shouldShowNewChatHero", () => {
  it("shows hero for new user with no history after load", () => {
    assert.equal(
      shouldShowNewChatHero({
        conversationsLoaded: true,
        conversationCount: 0,
        selectedId: null,
        forceNewChat: false,
      }),
      true,
    );
  });

  it("does not show hero while still loading", () => {
    assert.equal(
      shouldShowNewChatHero({
        conversationsLoaded: false,
        conversationCount: 0,
        selectedId: null,
        forceNewChat: false,
      }),
      false,
    );
  });
});

describe("invalid or unauthorized conversation IDs", () => {
  it("rejects foreign or missing ownership rows", () => {
    const denied = acceptOwnedConversation({
      requestedId: "foreign",
      row: { id: "foreign", user_id: "other-user" },
      authUserId: "self",
    });
    assert.equal(denied.ok, false);

    const missing = acceptOwnedConversation({
      requestedId: "missing",
      row: null,
      authUserId: "self",
    });
    assert.equal(missing.ok, false);
  });

  it("does not select unauthorized preferred IDs from the owned list", () => {
    assert.equal(
      selectHermesConversationId({ preferredId: "foreign-id", conversations: convs }),
      "c-new",
    );
  });

  it("accepts an owned conversation", () => {
    const ok = acceptOwnedConversation({
      requestedId: "c-new",
      row: { id: "c-new", user_id: "self" },
      authUserId: "self",
    });
    assert.deepEqual(ok, { ok: true, id: "c-new" });
  });
});

describe("rapid conversation switching", () => {
  it("ignores stale load responses when a newer request is in flight", () => {
    assert.equal(isStaleHermesRequest(1, 2), true);
    assert.equal(isStaleHermesRequest(3, 3), false);
  });
});

describe("duplicate-message prevention", () => {
  it("does not append a message whose id already exists", () => {
    const existing = [{ id: "a1", role: "assistant", content: "hi" }];
    const next = appendUniqueHermesMessage(existing, {
      id: "a1",
      role: "assistant",
      content: "hi",
    });
    assert.equal(next.length, 1);
    assert.equal(next[0].id, "a1");
  });

  it("appends when the id is new", () => {
    const existing = [{ id: "u1", role: "user", content: "q" }];
    const next = appendUniqueHermesMessage(existing, {
      id: "a2",
      role: "assistant",
      content: "ans",
    });
    assert.equal(next.length, 2);
  });
});

describe("history-load failure with retry action", () => {
  it("maps list failure to error (retryable), not permanent loading", () => {
    assert.equal(historyStatusAfterListFailure(), "error");
    assert.equal(historyStatusAfterRetryStart(), "loading");
  });
});
