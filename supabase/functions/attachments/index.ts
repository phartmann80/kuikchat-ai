import { createClient } from "https://esm.sh/@supabase/supabase-js@2.89.0";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

/**
 * Attachments Edge Function:
 * - mints signed upload/download URLs after RPC authorization
 * - streaming verify + optional test scanner (test env only)
 * - janitor endpoints for expiry/purge
 *
 * Never enables uploads itself; RPCs enforce attachment_runtime_config defaults.
 * Production must not invoke TestScannerAdapter.
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function userClient(authHeader: string) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  return createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function testScannerAllowed(): boolean {
  return (
    Deno.env.get("ATTACHMENT_ENV") === "test" &&
    Deno.env.get("ATTACHMENT_ALLOW_TEST_SCANNER") === "true"
  );
}

async function runTestScan(checksum: string, attachmentId: string) {
  if (!testScannerAllowed()) {
    throw new Error("TEST_SCANNER_FORBIDDEN");
  }
  if (checksum.endsWith("bad")) {
    return { verdict: "malware" as const, engine: "test-adapter", signals: ["TEST_MALWARE"] };
  }
  if (checksum.endsWith("out")) {
    return { verdict: "failed" as const, engine: "test-adapter", failureCode: "SCANNER_UNAVAILABLE" };
  }
  return { verdict: "clean" as const, engine: "test-adapter", externalId: `test-${attachmentId}` };
}

function bearerEqualsServiceRole(authHeader: string): boolean {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  return Boolean(key) && token === key;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || (await req.clone().json().catch(() => ({}))).action;

    if (action === "janitor") {
      if (!bearerEqualsServiceRole(authHeader)) {
        return json(401, { error: { code: "UNAUTHORIZED" } });
      }
      const svc = serviceClient();
      const nowIso = new Date().toISOString();
      const { data: expired } = await svc
        .from("chat_attachments")
        .select("id, storage_bucket, storage_path")
        .in("status", ["initiated", "uploading"])
        .lt("upload_expires_at", nowIso);

      for (const row of expired || []) {
        await svc.storage.from(row.storage_bucket).remove([row.storage_path]);
        await svc.rpc("attachment_worker_set_failed", {
          p_attachment_id: row.id,
          p_failure_code: "UPLOAD_EXPIRED",
        });
      }

      const { data: scanning } = await svc
        .from("chat_attachments")
        .select("id, scan_started_at")
        .eq("status", "scanning");

      const failAfterMs = 15 * 60 * 1000;
      let scannerTimeouts = 0;
      for (const row of scanning || []) {
        const started = row.scan_started_at ? new Date(row.scan_started_at).getTime() : 0;
        if (started && Date.now() - started > failAfterMs) {
          await svc.rpc("attachment_worker_set_failed", {
            p_attachment_id: row.id,
            p_failure_code: "SCANNER_UNAVAILABLE",
          });
          scannerTimeouts += 1;
        }
      }

      const { data: purgable } = await svc
        .from("chat_attachments")
        .select("id, storage_bucket, storage_path")
        .eq("status", "deleted")
        .lt("purge_after", nowIso);

      for (const row of purgable || []) {
        await svc.storage.from(row.storage_bucket).remove([row.storage_path]);
        await svc.from("chat_attachments").delete().eq("id", row.id);
      }

      return json(200, {
        expired: expired?.length || 0,
        scanner_timeouts: scannerTimeouts,
        purged: purgable?.length || 0,
      });
    }

    if (!authHeader) return json(401, { error: { code: "UNAUTHORIZED" } });
    const userSb = userClient(authHeader);
    const {
      data: { user },
    } = await userSb.auth.getUser();
    if (!user) return json(401, { error: { code: "UNAUTHORIZED" } });

    const body = await req.json().catch(() => ({}));

    if (action === "initiate") {
      const { data, error } = await userSb.rpc("initiate_chat_attachment", {
        p_chat_id: body.chat_id,
        p_original_filename: body.original_filename,
        p_declared_content_type: body.declared_content_type,
        p_declared_byte_size: body.declared_byte_size,
        p_idempotency_key: body.idempotency_key,
        p_client_checksum_sha256: body.client_checksum_sha256 ?? null,
      });
      if (error) {
        return json(400, { error: { code: error.message || "INITIATE_FAILED" } });
      }

      // Idempotent replay of a completed object must never mint a new upload URL.
      if (data?.status && !["initiated", "uploading"].includes(String(data.status))) {
        return json(409, {
          error: { code: "UPLOAD_NOT_MUTABLE", status: data.status },
          attachment_id: data.attachment_id,
        });
      }

      const svc = serviceClient();
      const path = data.storage_path as string;

      // Refuse signed upload if an object already exists at the reserved path.
      const { data: listed } = await svc.storage.from("chat-attachments").list(
        path.replace(/\/[^/]+$/, ""),
        { search: "original" },
      );
      if ((listed || []).some((o) => o.name === "original" || path.endsWith(`/${o.name}`))) {
        return json(409, { error: { code: "OBJECT_EXISTS" } });
      }

      const { data: signed, error: signErr } = await svc.storage
        .from("chat-attachments")
        .createSignedUploadUrl(path, { upsert: false });
      if (signErr || !signed) {
        return json(500, { error: { code: "SIGN_UPLOAD_FAILED" } });
      }

      return json(200, {
        ...data,
        signed_upload: signed,
      });
    }

    if (action === "finalize") {
      const attachmentId = body.attachment_id as string;
      const { data: row, error: loadErr } = await userSb
        .from("chat_attachments")
        .select("*")
        .eq("id", attachmentId)
        .single();
      if (loadErr || !row) return json(404, { error: { code: "NOT_FOUND" } });

      const svc = serviceClient();
      const { data: file, error: dlErr } = await svc.storage
        .from(row.storage_bucket)
        .download(row.storage_path);
      if (dlErr || !file) {
        return json(400, { error: { code: "OBJECT_MISSING" } });
      }

      const buf = new Uint8Array(await file.arrayBuffer());
      const digest = await crypto.subtle.digest("SHA-256", buf);
      const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
      const first = buf.slice(0, 64);
      let sniffed = row.declared_content_type as string;
      if (first[0] === 0xff && first[1] === 0xd8) sniffed = "image/jpeg";
      if (first[0] === 0x89 && first[1] === 0x50) sniffed = "image/png";
      if (first[0] === 0x25 && first[1] === 0x50) sniffed = "application/pdf";

      const { data: fin, error: finErr } = await userSb.rpc("finalize_chat_attachment", {
        p_attachment_id: attachmentId,
        p_byte_size: buf.byteLength,
        p_content_type: sniffed,
        p_checksum_sha256: hex,
        p_client_checksum_sha256: body.client_checksum_sha256 ?? null,
      });
      if (finErr) return json(400, { error: { code: finErr.message || "FINALIZE_FAILED" } });

      if (fin?.status === "scanning") {
        if (!testScannerAllowed()) {
          // No production scanner approved/deployed — fail closed.
          await svc.rpc("attachment_worker_set_failed", {
            p_attachment_id: attachmentId,
            p_failure_code: "SCANNER_UNAVAILABLE",
          });
          return json(503, {
            error: { code: "SCANNER_UNAVAILABLE" },
            attachment_id: attachmentId,
            status: "failed",
          });
        }

        const scan = await runTestScan(hex, attachmentId);
        if (scan.verdict === "clean") {
          await svc.rpc("attachment_worker_set_available", {
            p_attachment_id: attachmentId,
            p_scan_engine: scan.engine,
          });
          return json(200, { attachment_id: attachmentId, status: "available", scan });
        }
        if (scan.verdict === "malware") {
          const qPath = String(row.storage_path).replace(/\/original$/, "/quarantine");
          await svc.storage.from("chat-attachments").move(row.storage_path, qPath);
          const { data: qObj } = await svc.storage.from("chat-attachments").download(qPath);
          if (qObj) {
            await svc.storage.from("chat-attachments-quarantine").upload(qPath, qObj, {
              contentType: sniffed,
              upsert: true,
            });
            await svc.storage.from("chat-attachments").remove([qPath]);
          }
          await svc.rpc("attachment_worker_set_quarantined", {
            p_attachment_id: attachmentId,
            p_scan_engine: scan.engine,
            p_failure_code: "MALWARE",
          });
          return json(200, { attachment_id: attachmentId, status: "quarantined", scan });
        }
        await svc.rpc("attachment_worker_set_failed", {
          p_attachment_id: attachmentId,
          p_failure_code: scan.failureCode || "SCANNER_UNAVAILABLE",
        });
        return json(200, { attachment_id: attachmentId, status: "failed", scan });
      }

      return json(200, fin);
    }

    if (action === "download") {
      const { data, error } = await userSb.rpc("create_chat_attachment_download_grant", {
        p_attachment_id: body.attachment_id,
      });
      if (error) return json(400, { error: { code: error.message || "DOWNLOAD_DENIED" } });
      const svc = serviceClient();
      const { data: signed, error: sErr } = await svc.storage
        .from(data.storage_bucket)
        .createSignedUrl(data.storage_path, data.expires_in);
      if (sErr || !signed) return json(500, { error: { code: "SIGN_DOWNLOAD_FAILED" } });
      return json(200, {
        attachment_id: data.attachment_id,
        signed_url: signed.signedUrl,
        expires_in: data.expires_in,
        content_type: data.content_type,
        byte_size: data.byte_size,
        filename: data.original_filename,
      });
    }

    if (action === "cancel") {
      const { data, error } = await userSb.rpc("cancel_chat_attachment", {
        p_attachment_id: body.attachment_id,
      });
      if (error) return json(400, { error: { code: error.message || "CANCEL_FAILED" } });
      return json(200, data);
    }

    return json(400, { error: { code: "UNKNOWN_ACTION" } });
  } catch (e) {
    console.error("attachments_error", String((e as Error)?.message || e));
    return json(500, { error: { code: "INTERNAL" } });
  }
});
