-- Rollback for 20260811120000_chat_attachments_foundation.sql
-- Restores pre-attachment schema. Leaves chats/messages RLS untouched.

DROP TRIGGER IF EXISTS messages_before_delete_soft_delete_attachments ON public.messages;
DROP FUNCTION IF EXISTS public.tg_messages_soft_delete_attachments();

DROP TRIGGER IF EXISTS chat_attachments_touch_updated_at ON public.chat_attachments;
DROP FUNCTION IF EXISTS public.tg_chat_attachments_touch_updated_at();

DROP FUNCTION IF EXISTS public.initiate_chat_attachment(uuid, text, text, bigint, text, text);
DROP FUNCTION IF EXISTS public.mark_chat_attachment_uploading(uuid);
DROP FUNCTION IF EXISTS public.finalize_chat_attachment(uuid, bigint, text, text, text);
DROP FUNCTION IF EXISTS public.cancel_chat_attachment(uuid);
DROP FUNCTION IF EXISTS public.soft_delete_chat_attachment(uuid);
DROP FUNCTION IF EXISTS public.create_chat_attachment_download_grant(uuid);
DROP FUNCTION IF EXISTS public.bind_attachments_to_message(uuid, uuid[]);
DROP FUNCTION IF EXISTS public.attachment_worker_set_available(uuid, text);
DROP FUNCTION IF EXISTS public.attachment_worker_set_quarantined(uuid, text, text);
DROP FUNCTION IF EXISTS public.attachment_worker_set_failed(uuid, text);
DROP FUNCTION IF EXISTS public.tombstone_uploader_attachments(uuid);
DROP FUNCTION IF EXISTS public.attachment_release_quota(uuid);
DROP FUNCTION IF EXISTS public.attachment_sanitize_filename(text);
DROP FUNCTION IF EXISTS public.is_chat_member(uuid);

DROP TABLE IF EXISTS public.chat_attachments;
DROP TABLE IF EXISTS public.attachment_runtime_config;
