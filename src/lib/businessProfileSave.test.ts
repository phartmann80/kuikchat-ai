import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildBusinessProfileUpsert,
  personalProfilePatchFromBusinessSave,
} from "./businessProfileSave.ts";

describe("business profile save isolation", () => {
  it("builds a business_profiles payload without personal profile fields", () => {
    const payload = buildBusinessProfileUpsert({
      userId: "user-1",
      companyName: "Acme GmbH",
      categories: ["Tech"],
      hours: { mode: "custom" },
      description: "We build things",
      website: "https://acme.example",
      email: "hi@acme.example",
      phone: "+491234",
      address: "Berlin",
      logoUrl: "https://cdn.example/logo.png",
    });

    assert.equal(payload.company_name, "Acme GmbH");
    assert.equal(payload.user_id, "user-1");
    assert.equal("display_name" in payload, false);
    assert.equal("bio" in payload, false);
    assert.equal("avatar_url" in payload, false);
  });

  it("does not produce a personal profiles update after business create/edit", () => {
    assert.equal(personalProfilePatchFromBusinessSave(), null);
  });
});
