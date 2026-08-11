import { useEffect, useRef, useState } from "react";
import { AlertCircle, Check, Loader2, Paperclip, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  cancelAttachmentUpload,
  fetchAttachmentRuntimeConfig,
  finalizeAttachmentUpload,
  initiateAttachmentUpload,
  statusLabel,
  uploadFileToSignedTarget,
  type AttachmentRuntimeConfig,
  type AttachmentStatus,
} from "@/lib/attachments/client";

type LocalItem = {
  localId: string;
  file: File;
  attachmentId?: string;
  status: AttachmentStatus | "queued";
  progress: number;
  error?: string;
};

type Props = {
  chatId: string;
  disabled?: boolean;
  onAvailableChange?: (attachmentIds: string[]) => void;
};

export function AttachmentComposerControls({ chatId, disabled, onAvailableChange }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [cfg, setCfg] = useState<AttachmentRuntimeConfig | null>(null);
  const [items, setItems] = useState<LocalItem[]>([]);

  useEffect(() => {
    void fetchAttachmentRuntimeConfig().then(setCfg);
  }, []);

  useEffect(() => {
    const available = items
      .filter((i) => i.status === "available" && i.attachmentId)
      .map((i) => i.attachmentId!) ;
    onAvailableChange?.(available);
  }, [items, onAvailableChange]);

  if (!cfg?.uploads_enabled) {
    return null;
  }

  const update = (localId: string, patch: Partial<LocalItem>) => {
    setItems((prev) => prev.map((i) => (i.localId === localId ? { ...i, ...patch } : i)));
  };

  const startUpload = async (file: File) => {
    const localId = crypto.randomUUID();
    const idempotencyKey = crypto.randomUUID();
    setItems((prev) => [
      ...prev,
      { localId, file, status: "queued", progress: 0 },
    ]);
    try {
      update(localId, { status: "initiated", progress: 1 });
      const init = await initiateAttachmentUpload({ chatId, file, idempotencyKey });
      update(localId, {
        attachmentId: init.attachment_id,
        status: "uploading",
        progress: 5,
      });
      await uploadFileToSignedTarget(file, init.signed_upload, (pct) => {
        update(localId, { progress: Math.max(5, Math.min(90, pct)) });
      });
      update(localId, { status: "scanning", progress: 95 });
      const fin = await finalizeAttachmentUpload(init.attachment_id);
      update(localId, {
        status: fin.status,
        progress: fin.status === "available" ? 100 : 100,
        error: fin.status === "failed" || fin.status === "quarantined" ? statusLabel(fin.status) : undefined,
      });
    } catch (e) {
      update(localId, {
        status: "failed",
        error: e instanceof Error ? e.message : "UPLOAD_FAILED",
      });
    }
  };

  const onPick = async (list: FileList | null) => {
    if (!list?.length) return;
    const remaining = Math.max(0, (cfg.max_per_message || 5) - items.filter((i) => i.status === "available").length);
    const files = [...list].slice(0, remaining);
    for (const file of files) {
      await startUpload(file);
    }
  };

  return (
    <div className="space-y-2">
      <input
        ref={inputRef}
        type="file"
        className="hidden"
        multiple
        accept="image/*,application/pdf,text/plain,audio/*,video/mp4,video/webm"
        onChange={(e) => void onPick(e.target.files)}
      />
      <Button
        type="button"
        variant="ghost"
        size="sm"
        disabled={disabled}
        className="text-slate-300"
        onClick={() => inputRef.current?.click()}
        aria-label="Upload attachment"
      >
        <Paperclip className="w-4 h-4 mr-1" aria-hidden />
        Attach file
      </Button>

      {items.length > 0 && (
        <ul className="space-y-1">
          {items.map((item) => (
            <li
              key={item.localId}
              className="flex items-center gap-2 rounded-md border border-slate-800 bg-slate-950/40 px-2 py-1 text-xs text-slate-200"
            >
              {(item.status === "uploading" || item.status === "scanning" || item.status === "initiated") && (
                <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden />
              )}
              {item.status === "available" && <Check className="w-3.5 h-3.5 text-emerald-400" aria-hidden />}
              {(item.status === "failed" || item.status === "quarantined") && (
                <AlertCircle className="w-3.5 h-3.5 text-destructive" aria-hidden />
              )}
              <span className="truncate flex-1">{item.file.name}</span>
              <span className="text-slate-400">{statusLabel(item.status)}</span>
              {item.status === "uploading" && <span>{item.progress}%</span>}
              {(item.status === "initiated" || item.status === "uploading") && item.attachmentId && (
                <button
                  type="button"
                  aria-label="Cancel upload"
                  onClick={() => void cancelAttachmentUpload(item.attachmentId!).then(() => update(item.localId, { status: "failed", error: "CANCELLED" }))}
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              )}
              {item.status === "failed" && (
                <button
                  type="button"
                  className="underline"
                  onClick={() => void startUpload(item.file)}
                >
                  Retry
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
