-- Chat attachments foundation (uploads DISABLED by default).
-- Does not weaken existing chats/messages RLS.
-- Rollback: supabase/rollbacks/20260811120000_rollback_chat_attachments_foundation.sql

CREATE OR REPLACE FUNCTION public.is_chat_member(p_chat_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.chat_members m
    WHERE m.chat_id = p_chat_id
      AND m.user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_chat_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_chat_member(uuid) TO authenticated, service_role;

CREATE TABLE public.attachment_runtime_config (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  uploads_enabled boolean NOT NULL DEFAULT false,
  downloads_enabled boolean NOT NULL DEFAULT false,
  max_image_bytes bigint NOT NULL DEFAULT 10485760,
  max_document_bytes bigint NOT NULL DEFAULT 26214400,
  max_audio_bytes bigint NOT NULL DEFAULT 26214400,
  max_video_bytes bigint NOT NULL DEFAULT 104857600,
  max_per_message integer NOT NULL DEFAULT 5,
  max_initiations_per_user_day integer NOT NULL DEFAULT 50,
  max_bytes_per_user_day bigint NOT NULL DEFAULT 524288000,
  max_initiations_per_chat_day integer NOT NULL DEFAULT 200,
  max_concurrent_uploads_per_user integer NOT NULL DEFAULT 3,
  upload_url_ttl_seconds integer NOT NULL DEFAULT 900,
  download_url_ttl_seconds integer NOT NULL DEFAULT 60,
  initiation_ttl_hours integer NOT NULL DEFAULT 24,
  soft_delete_purge_days integer NOT NULL DEFAULT 7,
  scanner_outage_fail_minutes integer NOT NULL DEFAULT 15,
  allowed_content_types text[] NOT NULL DEFAULT ARRAY[
    'image/jpeg','image/png','image/webp','image/gif',
    'application/pdf','text/plain',
    'audio/mpeg','audio/mp4','audio/ogg','audio/webm',
    'video/mp4','video/webm'
  ]::text[],
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.attachment_runtime_config (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.attachment_runtime_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY attachment_runtime_config_select_authenticated
  ON public.attachment_runtime_config
  FOR SELECT TO authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.attachment_runtime_config FROM anon, authenticated;
GRANT SELECT ON public.attachment_runtime_config TO authenticated;
GRANT ALL ON public.attachment_runtime_config TO service_role;

CREATE TABLE public.chat_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id uuid NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  uploader_id uuid NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  uploader_attribution jsonb NOT NULL,
  uploader_tombstoned_at timestamptz NULL,
  storage_bucket text NOT NULL DEFAULT 'chat-attachments',
  storage_path text NOT NULL,
  original_filename text NOT NULL,
  content_type text NOT NULL,
  declared_content_type text NOT NULL,
  byte_size bigint NULL CHECK (byte_size IS NULL OR byte_size > 0),
  declared_byte_size bigint NOT NULL CHECK (declared_byte_size > 0),
  client_checksum_sha256 text NULL CHECK (client_checksum_sha256 IS NULL OR char_length(client_checksum_sha256) = 64),
  checksum_sha256 text NULL CHECK (checksum_sha256 IS NULL OR char_length(checksum_sha256) = 64),
  status text NOT NULL DEFAULT 'initiated'
    CHECK (status IN (
      'initiated','uploading','uploaded','scanning','available',
      'quarantined','failed','deleted'
    )),
  failure_code text NULL,
  scan_engine text NULL,
  scan_external_id text NULL,
  scan_started_at timestamptz NULL,
  scan_finished_at timestamptz NULL,
  upload_expires_at timestamptz NOT NULL,
  available_at timestamptz NULL,
  deleted_at timestamptz NULL,
  purge_after timestamptz NULL,
  quota_reserved_bytes bigint NOT NULL CHECK (quota_reserved_bytes >= 0),
  quota_released boolean NOT NULL DEFAULT false,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_attachments_attribution_shape CHECK (
    jsonb_typeof(uploader_attribution) = 'object'
    AND (uploader_attribution ? 'profile_id')
    AND (uploader_attribution ? 'display_name')
  ),
  CONSTRAINT chat_attachments_message_bind_check CHECK (
    message_id IS NULL OR status IN ('available', 'deleted')
  ),
  CONSTRAINT chat_attachments_storage_path_unique UNIQUE (storage_bucket, storage_path)
);

CREATE UNIQUE INDEX chat_attachments_idempotency_uidx
  ON public.chat_attachments ((uploader_attribution->>'profile_id'), idempotency_key);

CREATE INDEX chat_attachments_chat_created_idx
  ON public.chat_attachments (chat_id, created_at DESC);

CREATE INDEX chat_attachments_message_idx
  ON public.chat_attachments (message_id)
  WHERE message_id IS NOT NULL;

CREATE INDEX chat_attachments_uploader_created_idx
  ON public.chat_attachments (uploader_id, created_at DESC)
  WHERE uploader_id IS NOT NULL;

CREATE INDEX chat_attachments_status_queue_idx
  ON public.chat_attachments (status, updated_at)
  WHERE status IN ('initiated', 'uploading', 'uploaded', 'scanning');

CREATE INDEX chat_attachments_purge_idx
  ON public.chat_attachments (purge_after)
  WHERE purge_after IS NOT NULL AND status = 'deleted';

CREATE OR REPLACE FUNCTION public.tg_chat_attachments_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER chat_attachments_touch_updated_at
  BEFORE UPDATE ON public.chat_attachments
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_chat_attachments_touch_updated_at();

CREATE OR REPLACE FUNCTION public.tg_messages_soft_delete_attachments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purge_days integer;
BEGIN
  SELECT soft_delete_purge_days INTO v_purge_days
  FROM public.attachment_runtime_config
  WHERE id = 1;

  UPDATE public.chat_attachments a
  SET
    status = 'deleted',
    deleted_at = coalesce(a.deleted_at, now()),
    purge_after = coalesce(a.purge_after, now() + make_interval(days => coalesce(v_purge_days, 7))),
    failure_code = coalesce(a.failure_code, 'MESSAGE_DELETED')
  WHERE a.message_id = OLD.id
    AND a.status <> 'deleted';

  RETURN OLD;
END;
$$;

CREATE TRIGGER messages_before_delete_soft_delete_attachments
  BEFORE DELETE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_messages_soft_delete_attachments();

ALTER TABLE public.chat_attachments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.chat_attachments FROM anon, authenticated;
GRANT SELECT ON public.chat_attachments TO authenticated;
GRANT ALL ON public.chat_attachments TO service_role;

CREATE POLICY chat_attachments_select_member
  ON public.chat_attachments
  FOR SELECT
  TO authenticated
  USING (
    deleted_at IS NULL
    AND status <> 'quarantined'
    AND status IN ('initiated', 'uploading', 'uploaded', 'scanning', 'available', 'failed')
    AND public.is_chat_member(chat_id)
    AND (
      status = 'available'
      OR coalesce(uploader_id, (uploader_attribution->>'profile_id')::uuid) = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.attachment_sanitize_filename(p_name text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  v := coalesce(p_name, '');
  v := regexp_replace(v, '[[:cntrl:]]', '', 'g');
  v := regexp_replace(v, '[\\/]+', '_', 'g');
  v := trim(both from v);
  IF char_length(v) = 0 THEN
    v := 'file';
  END IF;
  IF char_length(v) > 255 THEN
    v := left(v, 255);
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.attachment_release_quota(p_attachment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.chat_attachments
  SET quota_released = true
  WHERE id = p_attachment_id
    AND quota_released = false;
END;
$$;

CREATE OR REPLACE FUNCTION public.initiate_chat_attachment(
  p_chat_id uuid,
  p_original_filename text,
  p_declared_content_type text,
  p_declared_byte_size bigint,
  p_idempotency_key text,
  p_client_checksum_sha256 text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_display text;
  v_existing public.chat_attachments%ROWTYPE;
  v_id uuid;
  v_path text;
  v_filename text;
  v_max bigint;
  v_init_count integer;
  v_byte_sum bigint;
  v_chat_init integer;
  v_concurrent integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1 FOR UPDATE;
  IF NOT FOUND OR NOT v_cfg.uploads_enabled THEN
    RAISE EXCEPTION 'UPLOADS_DISABLED' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_chat_member(p_chat_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_REQUIRED' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_existing
  FROM public.chat_attachments
  WHERE (uploader_attribution->>'profile_id') = v_uid::text
    AND idempotency_key = p_idempotency_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'attachment_id', v_existing.id,
      'status', v_existing.status,
      'storage_bucket', v_existing.storage_bucket,
      'storage_path', v_existing.storage_path,
      'upload_expires_at', v_existing.upload_expires_at,
      'declared_byte_size', v_existing.declared_byte_size,
      'idempotent_replay', true
    );
  END IF;

  IF p_declared_content_type IS NULL
     OR NOT (p_declared_content_type = ANY (v_cfg.allowed_content_types)) THEN
    RAISE EXCEPTION 'CONTENT_TYPE_DENIED' USING ERRCODE = '22023';
  END IF;

  v_max := CASE
    WHEN p_declared_content_type LIKE 'image/%' THEN v_cfg.max_image_bytes
    WHEN p_declared_content_type LIKE 'video/%' THEN v_cfg.max_video_bytes
    WHEN p_declared_content_type LIKE 'audio/%' THEN v_cfg.max_audio_bytes
    ELSE v_cfg.max_document_bytes
  END;

  IF p_declared_byte_size IS NULL OR p_declared_byte_size <= 0 OR p_declared_byte_size > v_max THEN
    RAISE EXCEPTION 'SIZE_DENIED' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_concurrent
  FROM public.chat_attachments
  WHERE (uploader_attribution->>'profile_id') = v_uid::text
    AND status IN ('initiated', 'uploading')
    AND upload_expires_at > now()
    AND deleted_at IS NULL;

  IF v_concurrent >= v_cfg.max_concurrent_uploads_per_user THEN
    RAISE EXCEPTION 'CONCURRENT_LIMIT' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_init_count
  FROM public.chat_attachments
  WHERE (uploader_attribution->>'profile_id') = v_uid::text
    AND created_at >= now() - interval '24 hours';

  IF v_init_count >= v_cfg.max_initiations_per_user_day THEN
    RAISE EXCEPTION 'USER_INITIATION_QUOTA' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(sum(CASE WHEN NOT quota_released THEN quota_reserved_bytes ELSE 0 END), 0)
       + coalesce(sum(CASE WHEN status = 'available' THEN coalesce(byte_size, 0) ELSE 0 END), 0)
  INTO v_byte_sum
  FROM public.chat_attachments
  WHERE (uploader_attribution->>'profile_id') = v_uid::text
    AND created_at >= now() - interval '24 hours';

  IF v_byte_sum + p_declared_byte_size > v_cfg.max_bytes_per_user_day THEN
    RAISE EXCEPTION 'USER_BYTE_QUOTA' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_chat_init
  FROM public.chat_attachments
  WHERE chat_id = p_chat_id
    AND created_at >= now() - interval '24 hours';

  IF v_chat_init >= v_cfg.max_initiations_per_chat_day THEN
    RAISE EXCEPTION 'CHAT_INITIATION_QUOTA' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), 'Member')
  INTO v_display
  FROM public.profiles p
  WHERE p.id = v_uid;

  v_filename := public.attachment_sanitize_filename(p_original_filename);
  v_id := gen_random_uuid();
  v_path := 'chats/' || p_chat_id::text || '/attachments/' || v_id::text || '/original';

  INSERT INTO public.chat_attachments (
    id, chat_id, uploader_id, uploader_attribution,
    storage_path, original_filename, content_type, declared_content_type,
    declared_byte_size, client_checksum_sha256, status,
    upload_expires_at, quota_reserved_bytes, idempotency_key
  ) VALUES (
    v_id, p_chat_id, v_uid,
    jsonb_build_object('profile_id', v_uid, 'display_name', coalesce(v_display, 'Member')),
    v_path, v_filename, p_declared_content_type, p_declared_content_type,
    p_declared_byte_size, lower(p_client_checksum_sha256), 'initiated',
    now() + make_interval(secs => v_cfg.upload_url_ttl_seconds),
    p_declared_byte_size, p_idempotency_key
  );

  RETURN jsonb_build_object(
    'attachment_id', v_id,
    'status', 'initiated',
    'storage_bucket', 'chat-attachments',
    'storage_path', v_path,
    'upload_expires_at', now() + make_interval(secs => v_cfg.upload_url_ttl_seconds),
    'declared_byte_size', p_declared_byte_size,
    'upload_mode', CASE WHEN p_declared_byte_size >= 6291456 THEN 'resumable' ELSE 'signed' END,
    'idempotent_replay', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_chat_attachment_uploading(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.chat_attachments%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.chat_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF auth.uid() IS NOT NULL
     AND auth.role() <> 'service_role'
     AND coalesce(v_row.uploader_id, (v_row.uploader_attribution->>'profile_id')::uuid) <> auth.uid() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_row.status = 'initiated' THEN
    UPDATE public.chat_attachments SET status = 'uploading' WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'uploading');
  END IF;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', v_row.status);
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_chat_attachment(
  p_attachment_id uuid,
  p_byte_size bigint,
  p_content_type text,
  p_checksum_sha256 text,
  p_client_checksum_sha256 text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_row public.chat_attachments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1;
  IF NOT v_cfg.uploads_enabled THEN
    RAISE EXCEPTION 'UPLOADS_DISABLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row FROM public.chat_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF coalesce(v_row.uploader_id, (v_row.uploader_attribution->>'profile_id')::uuid) <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_chat_member(v_row.chat_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_row.status IN ('uploaded', 'scanning', 'available') THEN
    RETURN jsonb_build_object('attachment_id', v_row.id, 'status', v_row.status, 'idempotent', true);
  END IF;

  IF v_row.status IN ('failed', 'deleted', 'quarantined') THEN
    RETURN jsonb_build_object(
      'attachment_id', v_row.id,
      'status', v_row.status,
      'failure_code', v_row.failure_code,
      'idempotent', true
    );
  END IF;

  IF v_row.status NOT IN ('initiated', 'uploading') THEN
    RAISE EXCEPTION 'INVALID_STATE' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.upload_expires_at < now() THEN
    UPDATE public.chat_attachments
    SET status = 'failed', failure_code = 'UPLOAD_EXPIRED', quota_released = true
    WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'UPLOAD_EXPIRED');
  END IF;

  IF p_byte_size IS NULL OR p_byte_size <= 0 OR p_byte_size > v_row.declared_byte_size THEN
    UPDATE public.chat_attachments
    SET status = 'failed', failure_code = 'SIZE_MISMATCH', quota_released = true
    WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'SIZE_MISMATCH');
  END IF;

  IF p_content_type IS NULL OR p_content_type <> v_row.declared_content_type
     OR NOT (p_content_type = ANY (v_cfg.allowed_content_types)) THEN
    UPDATE public.chat_attachments
    SET status = 'failed', failure_code = 'MIME_MISMATCH', quota_released = true
    WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'MIME_MISMATCH');
  END IF;

  IF p_checksum_sha256 IS NULL OR char_length(p_checksum_sha256) <> 64 THEN
    UPDATE public.chat_attachments
    SET status = 'failed', failure_code = 'CHECKSUM_MISSING', quota_released = true
    WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'CHECKSUM_MISSING');
  END IF;

  IF coalesce(p_client_checksum_sha256, v_row.client_checksum_sha256) IS NOT NULL
     AND lower(coalesce(p_client_checksum_sha256, v_row.client_checksum_sha256)) <> lower(p_checksum_sha256) THEN
    UPDATE public.chat_attachments
    SET status = 'failed', failure_code = 'CHECKSUM_MISMATCH', quota_released = true
    WHERE id = p_attachment_id;
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'CHECKSUM_MISMATCH');
  END IF;

  UPDATE public.chat_attachments
  SET
    status = 'scanning',
    byte_size = p_byte_size,
    content_type = p_content_type,
    checksum_sha256 = lower(p_checksum_sha256),
    client_checksum_sha256 = coalesce(lower(p_client_checksum_sha256), client_checksum_sha256),
    scan_started_at = now()
  WHERE id = p_attachment_id;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'scanning');
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_chat_attachment(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_row public.chat_attachments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1;
  IF NOT v_cfg.uploads_enabled THEN
    RAISE EXCEPTION 'UPLOADS_DISABLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row FROM public.chat_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF coalesce(v_row.uploader_id, (v_row.uploader_attribution->>'profile_id')::uuid) <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_row.status NOT IN ('initiated', 'uploading') THEN
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', v_row.status, 'idempotent', true);
  END IF;

  UPDATE public.chat_attachments
  SET status = 'failed', failure_code = 'CANCELLED', quota_released = true
  WHERE id = p_attachment_id;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', 'CANCELLED');
END;
$$;

CREATE OR REPLACE FUNCTION public.soft_delete_chat_attachment(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_row public.chat_attachments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.chat_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF coalesce(v_row.uploader_id, (v_row.uploader_attribution->>'profile_id')::uuid) <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_row.status = 'deleted' THEN
    RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'deleted', 'idempotent', true);
  END IF;

  IF v_row.status <> 'available' THEN
    RAISE EXCEPTION 'INVALID_STATE' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1;

  UPDATE public.chat_attachments
  SET
    status = 'deleted',
    deleted_at = now(),
    purge_after = now() + make_interval(days => v_cfg.soft_delete_purge_days)
  WHERE id = p_attachment_id;

  RETURN jsonb_build_object(
    'attachment_id', p_attachment_id,
    'status', 'deleted',
    'purge_after', now() + make_interval(days => v_cfg.soft_delete_purge_days)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_chat_attachment_download_grant(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_row public.chat_attachments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1;
  IF NOT v_cfg.downloads_enabled THEN
    RAISE EXCEPTION 'DOWNLOADS_DISABLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row FROM public.chat_attachments WHERE id = p_attachment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status <> 'available' OR v_row.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'NOT_AVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_chat_member(v_row.chat_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'attachment_id', v_row.id,
    'storage_bucket', v_row.storage_bucket,
    'storage_path', v_row.storage_path,
    'expires_in', v_cfg.download_url_ttl_seconds,
    'content_type', v_row.content_type,
    'byte_size', v_row.byte_size,
    'original_filename', v_row.original_filename
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bind_attachments_to_message(
  p_message_id uuid,
  p_attachment_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_msg record;
  v_id uuid;
  v_row public.chat_attachments%ROWTYPE;
  v_cfg public.attachment_runtime_config%ROWTYPE;
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cfg FROM public.attachment_runtime_config WHERE id = 1;

  SELECT id, chat_id, sender_id INTO v_msg
  FROM public.messages
  WHERE id = p_message_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_msg.sender_id <> v_uid THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_attachment_ids IS NULL OR cardinality(p_attachment_ids) = 0 THEN
    RAISE EXCEPTION 'EMPTY_ATTACHMENTS' USING ERRCODE = '22023';
  END IF;

  IF cardinality(p_attachment_ids) > v_cfg.max_per_message THEN
    RAISE EXCEPTION 'TOO_MANY_ATTACHMENTS' USING ERRCODE = 'P0001';
  END IF;

  FOREACH v_id IN ARRAY p_attachment_ids LOOP
    SELECT * INTO v_row FROM public.chat_attachments WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_row.chat_id <> v_msg.chat_id THEN
      RAISE EXCEPTION 'CHAT_MISMATCH' USING ERRCODE = '42501';
    END IF;
    IF coalesce(v_row.uploader_id, (v_row.uploader_attribution->>'profile_id')::uuid) <> v_uid THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    IF v_row.status <> 'available' OR v_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'NOT_AVAILABLE' USING ERRCODE = 'P0001';
    END IF;
    IF v_row.message_id IS NOT NULL AND v_row.message_id <> p_message_id THEN
      RAISE EXCEPTION 'ALREADY_BOUND' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.chat_attachments
    SET message_id = p_message_id
    WHERE id = v_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('message_id', p_message_id, 'bound_count', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.attachment_worker_set_available(p_attachment_id uuid, p_scan_engine text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_attachments
  SET
    status = 'available',
    available_at = now(),
    scan_finished_at = now(),
    scan_engine = p_scan_engine,
    failure_code = NULL,
    quota_released = true
  WHERE id = p_attachment_id
    AND status = 'scanning';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATE' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'available');
END;
$$;

CREATE OR REPLACE FUNCTION public.attachment_worker_set_quarantined(
  p_attachment_id uuid,
  p_scan_engine text,
  p_failure_code text DEFAULT 'MALWARE'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_attachments
  SET
    status = 'quarantined',
    storage_bucket = 'chat-attachments-quarantine',
    storage_path = regexp_replace(storage_path, '/original$', '/quarantine'),
    scan_finished_at = now(),
    scan_engine = p_scan_engine,
    failure_code = p_failure_code,
    quota_released = true
  WHERE id = p_attachment_id
    AND status = 'scanning';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATE' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'quarantined');
END;
$$;

CREATE OR REPLACE FUNCTION public.attachment_worker_set_failed(
  p_attachment_id uuid,
  p_failure_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_attachments
  SET
    status = 'failed',
    failure_code = p_failure_code,
    scan_finished_at = coalesce(scan_finished_at, now()),
    quota_released = true
  WHERE id = p_attachment_id
    AND status IN ('initiated', 'uploading', 'uploaded', 'scanning');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATE' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('attachment_id', p_attachment_id, 'status', 'failed', 'failure_code', p_failure_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.tombstone_uploader_attachments(p_profile_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_attachments
  SET
    uploader_id = NULL,
    uploader_tombstoned_at = coalesce(uploader_tombstoned_at, now())
  WHERE uploader_id = p_profile_id
     OR (uploader_attribution->>'profile_id') = p_profile_id::text;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.initiate_chat_attachment(uuid, text, text, bigint, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_chat_attachment_uploading(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_chat_attachment(uuid, bigint, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_chat_attachment(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.soft_delete_chat_attachment(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_chat_attachment_download_grant(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bind_attachments_to_message(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.attachment_worker_set_available(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.attachment_worker_set_quarantined(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.attachment_worker_set_failed(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tombstone_uploader_attachments(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.attachment_release_quota(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.initiate_chat_attachment(uuid, text, text, bigint, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_chat_attachment_uploading(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_chat_attachment(uuid, bigint, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_chat_attachment(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_chat_attachment(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_chat_attachment_download_grant(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bind_attachments_to_message(uuid, uuid[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.attachment_worker_set_available(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.attachment_worker_set_quarantined(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.attachment_worker_set_failed(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.tombstone_uploader_attachments(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.attachment_release_quota(uuid) TO service_role;
