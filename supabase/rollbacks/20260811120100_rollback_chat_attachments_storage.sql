-- Rollback for 20260811120100_chat_attachments_storage.sql

DROP POLICY IF EXISTS chat_attachments_storage_deny_insert ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_select ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_update ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_delete ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_insert ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_select ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_update ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_delete ON storage.objects;

DELETE FROM storage.objects
WHERE bucket_id IN ('chat-attachments', 'chat-attachments-quarantine');

DELETE FROM storage.buckets
WHERE id IN ('chat-attachments', 'chat-attachments-quarantine');
