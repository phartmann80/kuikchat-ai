import { supabase } from "@/integrations/supabase/client";

// New tables/RPCs land via migration; generated Database types catch up later.
const db = supabase as any;

export type AttachmentStatus =
  | "initiated"
  | "uploading"
  | "uploaded"
  | "scanning"
  | "available"
  | "quarantined"
  | "failed"
  | "deleted";

export type AttachmentRuntimeConfig = {
  uploads_enabled: boolean;
  downloads_enabled: boolean;
  max_image_bytes: number;
  max_document_bytes: number;
  max_audio_bytes: number;
  max_video_bytes: number;
  max_per_message: number;
};

const FUNCTIONS_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/attachments`;

async function authHeader(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("UNAUTHORIZED");
  return `Bearer ${token}`;
}

export async function fetchAttachmentRuntimeConfig(): Promise<AttachmentRuntimeConfig | null> {
  const { data, error } = await db
    .from("attachment_runtime_config")
    .select(
      "uploads_enabled,downloads_enabled,max_image_bytes,max_document_bytes,max_audio_bytes,max_video_bytes,max_per_message",
    )
    .eq("id", 1)
    .maybeSingle();
  if (error) return null;
  return data as AttachmentRuntimeConfig;
}

export async function initiateAttachmentUpload(input: {
  chatId: string;
  file: File;
  idempotencyKey: string;
  clientChecksumSha256?: string;
}) {
  const res = await fetch(`${FUNCTIONS_URL}?action=initiate`, {
    method: "POST",
    headers: {
      Authorization: await authHeader(),
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      action: "initiate",
      chat_id: input.chatId,
      original_filename: input.file.name,
      declared_content_type: input.file.type || "application/octet-stream",
      declared_byte_size: input.file.size,
      idempotency_key: input.idempotencyKey,
      client_checksum_sha256: input.clientChecksumSha256 ?? null,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.code || "INITIATE_FAILED");
  return json;
}

export async function uploadFileToSignedTarget(
  file: File,
  signedUpload: { signedUrl?: string; token?: string; path?: string },
  onProgress?: (pct: number) => void,
) {
  // Prefer XHR for progress events against signed upload URL.
  const url = signedUpload.signedUrl;
  if (!url) throw new Error("MISSING_SIGNED_URL");

  await new Promise<void>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", url);
    xhr.setRequestHeader("Content-Type", file.type || "application/octet-stream");
    xhr.upload.onprogress = (evt) => {
      if (evt.lengthComputable && onProgress) {
        onProgress(Math.round((evt.loaded / evt.total) * 100));
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`UPLOAD_HTTP_${xhr.status}`));
    };
    xhr.onerror = () => reject(new Error("UPLOAD_NETWORK"));
    xhr.send(file);
  });
}

export async function finalizeAttachmentUpload(attachmentId: string, clientChecksumSha256?: string) {
  const res = await fetch(`${FUNCTIONS_URL}?action=finalize`, {
    method: "POST",
    headers: {
      Authorization: await authHeader(),
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      action: "finalize",
      attachment_id: attachmentId,
      client_checksum_sha256: clientChecksumSha256 ?? null,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.code || "FINALIZE_FAILED");
  return json as { attachment_id: string; status: AttachmentStatus };
}

export async function cancelAttachmentUpload(attachmentId: string) {
  const res = await fetch(`${FUNCTIONS_URL}?action=cancel`, {
    method: "POST",
    headers: {
      Authorization: await authHeader(),
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ action: "cancel", attachment_id: attachmentId }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.code || "CANCEL_FAILED");
  return json;
}

export async function createAttachmentDownloadUrl(attachmentId: string) {
  const res = await fetch(`${FUNCTIONS_URL}?action=download`, {
    method: "POST",
    headers: {
      Authorization: await authHeader(),
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ action: "download", attachment_id: attachmentId }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.code || "DOWNLOAD_FAILED");
  return json as { signed_url: string; expires_in: number; filename: string };
}

export async function softDeleteAttachment(attachmentId: string) {
  const { data, error } = await db.rpc("soft_delete_chat_attachment", {
    p_attachment_id: attachmentId,
  });
  if (error) throw error;
  return data;
}

export async function bindAttachmentsToMessage(messageId: string, attachmentIds: string[]) {
  const { data, error } = await db.rpc("bind_attachments_to_message", {
    p_message_id: messageId,
    p_attachment_ids: attachmentIds,
  });
  if (error) throw error;
  return data;
}

export function statusLabel(status: AttachmentStatus | string): string {
  switch (status) {
    case "uploading":
    case "initiated":
      return "Uploading…";
    case "scanning":
    case "uploaded":
      return "Scanning…";
    case "available":
      return "Ready";
    case "quarantined":
      return "Blocked";
    case "failed":
      return "Failed";
    case "deleted":
      return "Deleted";
    default:
      return status;
  }
}
