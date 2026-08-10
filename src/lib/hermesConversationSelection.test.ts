import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  selectHermesConversationId,
  shouldShowNewChatHero,
} from "./hermesConversationSelection.ts";

const convs = [
  { id: "c-new", title: "Newest", updated_at: "2026-08-10T12:00:00Z" },
  { id: "c-old", title: "Older", updated_at: "2026-08-09T12:00:00Z" },
];

describe("selectHermesConversationId", () => {
  it("returns null when user has no conversations", () => {
    assert.equal(selectHermesConversationId({ preferredId: "x", conversations: [] }), null);
  });

  it("loads preferred/selected conversation when present", () => {
    assert.equal(
      selectHermesConversationId({ preferredId: "c-old", conversations: convs }),
      "c-old",
    );
  });

  it("falls back to most recent when preferred id is missing or unauthorized", () => {
    assert.equal(
      selectHermesConversationId({ preferredId: "foreign-id", conversations: convs }),
      "c-new",
    );
    assert.equal(
      selectHermesConversationId({ preferredId: null, conversations: convs }),
      "c-new",
    );
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

  it("shows hero when user explicitly starts a new chat", () => {
    assert.equal(
      shouldShowNewChatHero({
        conversationsLoaded: true,
        conversationCount: 2,
        selectedId: null,
        forceNewChat: true,
      }),
      true,
    );
  });
});
