-- ROLLBACK for supabase/migrations/20260809073000_fix_upsert_direct_chat_idempotent.sql
-- This is the exact live definition of public.upsert_direct_chat(uuid) captured
-- from project fkvikwkmrlyhpjtaydln on 2026-08-09 (before replacement), via
-- pg_get_functiondef. Grants at capture time: EXECUTE for PUBLIC, postgres,
-- anon, authenticated, service_role.
--
-- NOTE: this file is documentation only. It lives outside supabase/migrations
-- so it is never applied automatically. Running it restores the previous
-- (non-idempotent) behavior.

CREATE OR REPLACE FUNCTION public.upsert_direct_chat(p_other uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me      uuid := auth.uid();
  v_chat_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_other is null or p_other = v_me then
    raise exception 'Invalid target user';
  end if;

  -- Find an existing direct chat that contains both users (and only them)
  select c.id
    into v_chat_id
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = v_me
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = p_other
  where c.type = 'direct'
  group by c.id
  having count(*) >= 2
  limit 1;

  if v_chat_id is not null then
    return v_chat_id;
  end if;

  -- Create the chat
  insert into public.chats (type, created_by)
  values ('direct', v_me)
  returning id into v_chat_id;

  -- Add both members
  insert into public.chat_members (chat_id, user_id, role)
  values
    (v_chat_id, v_me,    'member'),
    (v_chat_id, p_other, 'member')
  on conflict (chat_id, user_id) do nothing;

  return v_chat_id;
end;
$function$;

-- Restore the original (broader) grants that existed at capture time:
GRANT EXECUTE ON FUNCTION public.upsert_direct_chat(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_direct_chat(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.upsert_direct_chat(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_direct_chat(uuid) TO service_role;
