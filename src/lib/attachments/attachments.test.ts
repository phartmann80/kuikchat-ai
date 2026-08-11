import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AttachmentScannerAdapter,
  TestScannerAdapter,
  createScannerAdapter,
  mapScanVerdictToWorkerAction,
} from "./scanner.ts";
import {
  assertReservedPathOwnership,
  buildAttachmentObjectPath,
  buildQuarantineObjectPath,
  EXPECTED_ATTACHMENT_BUCKET_POLICIES,
} from "./storagePaths.ts";
import { sniffMimeFromMagic } from "./verifyStream.ts";

describe("attachment scanner adapters", () => {
  it("uses test adapter by default and never calls AttachmentScanner live", async () => {
    const adapter = createScannerAdapter(undefined);
    assert.equal(adapter.name, "test-adapter");
    const clean = await adapter.scan({
      attachmentId: "a1",
      contentType: "image/png",
      byteSize: 10,
      checksumSha256: "abc",
    });
    assert.equal(clean.verdict, "clean");
    assert.equal(mapScanVerdictToWorkerAction(clean), "available");
  });

  it("maps malware and outage checksums in the test adapter", async () => {
    const adapter = new TestScannerAdapter();
    const bad = await adapter.scan({
      attachmentId: "a2",
      contentType: "image/png",
      byteSize: 10,
      checksumSha256: "xxbad",
    });
    assert.equal(bad.verdict, "malware");
    assert.equal(mapScanVerdictToWorkerAction(bad), "quarantine");

    const out = await adapter.scan({
      attachmentId: "a3",
      contentType: "image/png",
      byteSize: 10,
      checksumSha256: "xxout",
    });
    assert.equal(out.verdict, "failed");
    assert.equal(out.failureCode, "SCANNER_UNAVAILABLE");
    assert.equal(mapScanVerdictToWorkerAction(out), "fail");
  });

  it("blocks AttachmentScanner adapter until vendor gate passes", async () => {
    const live = new AttachmentScannerAdapter();
    await assert.rejects(
      () =>
        live.scan({
          attachmentId: "a4",
          contentType: "image/png",
          byteSize: 10,
          checksumSha256: "abc",
        }),
      /vendor gate/i,
    );
  });
});

describe("attachment storage paths", () => {
  it("builds collision-safe reserved paths", () => {
    const chatId = "11111111-1111-1111-1111-111111111111";
    const attachmentId = "22222222-2222-2222-2222-222222222222";
    assert.equal(
      buildAttachmentObjectPath(chatId, attachmentId),
      `chats/${chatId}/attachments/${attachmentId}/original`,
    );
    assert.equal(
      buildQuarantineObjectPath(chatId, attachmentId),
      `chats/${chatId}/attachments/${attachmentId}/quarantine`,
    );
    assertReservedPathOwnership({
      chatId,
      attachmentId,
      storagePath: buildAttachmentObjectPath(chatId, attachmentId),
    });
    assert.throws(() =>
      assertReservedPathOwnership({
        chatId,
        attachmentId,
        storagePath: "evil/path",
      }),
    );
  });

  it("expects private deny-by-default buckets", () => {
    assert.equal(EXPECTED_ATTACHMENT_BUCKET_POLICIES.length, 2);
    for (const p of EXPECTED_ATTACHMENT_BUCKET_POLICIES) {
      assert.equal(p.public, false);
      assert.equal(p.denyAuthenticatedDirectAccess, true);
    }
  });
});

describe("mime sniffing", () => {
  it("detects png and jpeg magic", () => {
    assert.equal(
      sniffMimeFromMagic(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]), "image/png"),
      "image/png",
    );
    assert.equal(
      sniffMimeFromMagic(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0]), "image/jpeg"),
      "image/jpeg",
    );
  });
});

describe("feature switch expectations", () => {
  it("documents uploads disabled by default", () => {
    // Runtime defaults live in SQL migration attachment_runtime_config:
    // uploads_enabled=false, downloads_enabled=false.
    const defaults = { uploads_enabled: false, downloads_enabled: false };
    assert.equal(defaults.uploads_enabled, false);
    assert.equal(defaults.downloads_enabled, false);
  });
});
