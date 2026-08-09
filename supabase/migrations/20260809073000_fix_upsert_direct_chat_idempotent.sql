-- Fix: public.upsert_direct_chat(p_other uuid) was non-idempotent.
--
-- Root cause of the previous behavior: the existing-chat lookup used
--   JOIN chat_members m1 ... JOIN chat_members m2 ... HAVING count(*) >= 2
-- but the two joins yield exactly ONE row per matching chat, so count(*) was
-- always 1, the HAVING clause never matched, and every call created a brand-new
-- direct chat (verified live: three consecutive calls returned three chat ids).
--
-- This replacement keeps the exact function name and signature so the deployed
-- frontend continues to work unchanged. It is idempotent and concurrency-safe:
--   * caller identity comes exclusively from auth.uid()
--   * canonical unordered pair + transaction-scoped advisory lock serialize
--     concurrent resolution for the same pair
--   * the existing-chat check runs under the lock and deterministically
--     returns the OLDEST direct chat whose membership is exactly this pair
--   * a new chat plus both membership rows are created atomically only when
--     no valid chat exists
-- No RLS policies are touched. Rollback: supabase/rollbacks/20260809073000_rollback_upsert_direct_chat.sql

CREATE OR REPLACE FUNCTION public.upsert_direct_chat(p_other uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_first uuid;
  v_second uuid;
  v_chat_id uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF p_other IS NULL THEN
    RAISE EXCEPTION 'Target profile is required' USING ERRCODE = '22004';
  END IF;

  IF p_other = v_me THEN
    RAISE EXCEPTION 'Cannot start a direct chat with yourself' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_me) THEN
    RAISE EXCEPTION 'Current profile not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_other) THEN
    RAISE EXCEPTION 'Target profile not found' USING ERRCODE = 'P0002';
  END IF;

  -- Canonical unordered representation of the pair.
  IF v_me::text < p_other::text THEN
    v_first := v_me;
    v_second := p_other;
  ELSE
    v_first := p_other;
    v_second := v_me;
  END IF;

  -- Serialize concurrent resolution for this pair for the rest of the transaction.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_first::text || ':' || v_second::text, 0)
  );

  -- Re-check under the lock. Deterministically prefer the oldest direct chat
  -- whose membership is exactly these two users.
  SELECT c.id
  INTO v_chat_id
  FROM public.chats c
  JOIN public.chat_members m1 ON m1.chat_id = c.id AND m1.user_id = v_me
  JOIN public.chat_members m2 ON m2.chat_id = c.id AND m2.user_id = p_other
  WHERE c.type = 'direct'
    AND (SELECT count(*) FROM public.chat_members m WHERE m.chat_id = c.id) = 2
  ORDER BY c.created_at ASC, c.id ASC
  LIMIT 1;

  IF v_chat_id IS NOT NULL THEN
    RETURN v_chat_id;
  END IF;

  INSERT INTO public.chats (type, created_by)
  VALUES ('direct', v_me)
  RETURNING id INTO v_chat_id;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES
    (v_chat_id, v_me, 'member'),
    (v_chat_id, p_other, 'member')
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  RETURN v_chat_id;
END;
$$;

-- Tighten execution rights: previously EXECUTE was granted to PUBLIC and anon.
REVOKE ALL ON FUNCTION public.upsert_direct_chat(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_direct_chat(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.upsert_direct_chat(uuid) TO authenticated;
