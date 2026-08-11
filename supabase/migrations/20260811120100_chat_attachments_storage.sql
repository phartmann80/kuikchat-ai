-- Private attachment buckets + deny-by-default storage policies.
-- Uses RESTRICTIVE policies so existing bucket policies (e.g. avatars) stay intact.
-- Rollback: supabase/rollbacks/20260811120100_rollback_chat_attachments_storage.sql

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments',
  'chat-attachments',
  false,
  104857600,
  ARRAY[
    'image/jpeg','image/png','image/webp','image/gif',
    'application/pdf','text/plain',
    'audio/mpeg','audio/mp4','audio/ogg','audio/webm',
    'video/mp4','video/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments-quarantine',
  'chat-attachments-quarantine',
  false,
  104857600,
  NULL
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS chat_attachments_storage_deny_insert ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_select ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_update ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_deny_delete ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_insert ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_select ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_update ON storage.objects;
DROP POLICY IF EXISTS chat_attachments_storage_restrict_delete ON storage.objects;

-- RESTRICTIVE: anon/authenticated cannot touch attachment buckets directly.
-- Service-role signed URLs bypass RLS. Existing permissive policies for other
-- buckets continue to apply and are AND-ed with these restrictions.
-- Policies are scoped via WITH CHECK/USING on attachment bucket ids only for
-- the deny path; other buckets remain pass-through for the RESTRICTIVE clause.

CREATE POLICY chat_attachments_storage_restrict_insert
  ON storage.objects
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated, anon
  WITH CHECK (bucket_id NOT IN ('chat-attachments', 'chat-attachments-quarantine'));

CREATE POLICY chat_attachments_storage_restrict_select
  ON storage.objects
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated, anon
  USING (bucket_id NOT IN ('chat-attachments', 'chat-attachments-quarantine'));

CREATE POLICY chat_attachments_storage_restrict_update
  ON storage.objects
  AS RESTRICTIVE
  FOR UPDATE
  TO authenticated, anon
  USING (bucket_id NOT IN ('chat-attachments', 'chat-attachments-quarantine'));

CREATE POLICY chat_attachments_storage_restrict_delete
  ON storage.objects
  AS RESTRICTIVE
  FOR DELETE
  TO authenticated, anon
  USING (bucket_id NOT IN ('chat-attachments', 'chat-attachments-quarantine'));
