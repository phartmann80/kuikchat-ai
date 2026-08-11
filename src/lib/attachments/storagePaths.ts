/**
 * Storage verification helpers for chat attachments (read-only checks).
 * Does not create buckets or mutate production state by itself.
 */

export const ATTACHMENT_BUCKET = "chat-attachments";
export const ATTACHMENT_QUARANTINE_BUCKET = "chat-attachments-quarantine";

export function buildAttachmentObjectPath(chatId: string, attachmentId: string): string {
  return `chats/${chatId}/attachments/${attachmentId}/original`;
}

export function buildQuarantineObjectPath(chatId: string, attachmentId: string): string {
  return `chats/${chatId}/attachments/${attachmentId}/quarantine`;
}

export function assertReservedPathOwnership(args: {
  chatId: string;
  attachmentId: string;
  storagePath: string;
}): void {
  const expected = buildAttachmentObjectPath(args.chatId, args.attachmentId);
  if (args.storagePath !== expected) {
    throw new Error("STORAGE_PATH_MISMATCH");
  }
}

export type BucketPolicyExpectation = {
  bucket: string;
  public: false;
  denyAuthenticatedDirectAccess: true;
};

export const EXPECTED_ATTACHMENT_BUCKET_POLICIES: BucketPolicyExpectation[] = [
  {
    bucket: ATTACHMENT_BUCKET,
    public: false,
    denyAuthenticatedDirectAccess: true,
  },
  {
    bucket: ATTACHMENT_QUARANTINE_BUCKET,
    public: false,
    denyAuthenticatedDirectAccess: true,
  },
];
