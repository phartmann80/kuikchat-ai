-- Rollback for 20260811120100_chat_attachments_storage.sql
-- Ordered after foundation rollback (or when no metadata rows remain).
--
-- SAFETY: refuses if storage objects exist unless force GUC is set:
--   SELECT set_config('kuikchat.attachment_rollback_force', '1', true);

DO $$
DECLARE
  v_count bigint := 0;
  v_force text := current_setting('kuikchat.attachment_rollback_force', true);
BEGIN
  SELECT count(*) INTO v_count
  FROM storage.objects
  WHERE bucket_id IN ('chat-attachments', 'chat-attachments-quarantine');
  IF v_count > 0 AND coalesce(v_force, '') <> '1' THEN
    RAISE EXCEPTION
      'ROLLBACK_REFUSED: % attachment storage object(s) exist. Export/preserve first, then set kuikchat.attachment_rollback_force=1',
      v_count;
  END IF;
END $$;

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
