-- ============================================================================
-- KuikChat PERSONAL environment — RLS / authorization test matrix.
--
-- Run AFTER applying migrations to a CLEAN Personal DEVELOPMENT project:
--   psql "$PERSONAL_DEV_DB_URL" -f supabase-personal/tests/rls_matrix.sql
-- or paste into the Supabase SQL editor (runs as postgres).
--
-- The whole script runs in one transaction and ROLLS BACK at the end:
-- it leaves no data behind. It impersonates users by setting
-- request.jwt.claims + role, exactly like PostgREST does.
--
-- It FAILS LOUDLY (raises an exception) if any matrix row does not behave
-- as required. Success output ends with: ALL RLS MATRIX TESTS PASSED.
--
-- Matrix covered (per Milestone 1 review):
--   1  User A accessing their own records
--   2  User A attempting to access User B's records (no shared conversation)
--   3  User A accessing a shared conversation
--   4  User C attempting to access a non-member conversation
--   5  Blocked user attempting to create a conversation / send a message
--   6  Anonymous client attempting to call restricted RPCs
--   7  User attempting to write another user's private storage path,
--      non-member attempting to read/write conversation storage
--   plus: message immutability, soft-delete, read states, reactions,
--   attachments, device sessions.
--
-- NOT covered here (manual, API-level): signed-URL behavior of the storage
-- API, realtime channel delivery. See docs/smoke-test-plan.md.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Helpers (temp; vanish at rollback)
-- ---------------------------------------------------------------------------
create function pg_temp.exec_as(uid uuid, jwt_role text, stmt text)
returns text
language plpgsql
as $fn$
declare
  msg text;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid::text, 'role', jwt_role)::text,
    true
  );
  execute format('set local role %I', jwt_role);
  begin
    execute stmt;
    msg := 'OK';
  exception when others then
    msg := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';
  return msg;
end
$fn$;

create function pg_temp.count_as(uid uuid, jwt_role text, qry text)
returns bigint
language plpgsql
as $fn$
declare
  n bigint;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid::text, 'role', jwt_role)::text,
    true
  );
  execute format('set local role %I', jwt_role);
  execute 'select count(*) from (' || qry || ') q' into n;
  execute 'reset role';
  return n;
end
$fn$;

create temp table _results (
  seq   serial,
  test  text,
  pass  boolean,
  info  text
);

create function pg_temp.check_(test text, pass boolean, info text default '')
returns void
language sql
as $fn$
  insert into _results (test, pass, info) values (test, pass, info);
$fn$;

-- ---------------------------------------------------------------------------
-- Seed: three users (fires handle_new_user -> profiles)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, aud, role, raw_user_meta_data)
values
  ('00000000-0000-4000-8000-00000000000a', 'alice@rls.test', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-4000-8000-00000000000b', 'bob@rls.test',   'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-4000-8000-00000000000c', 'carol@rls.test', 'authenticated', 'authenticated', '{"display_name":"Carol"}');

do $$
declare
  alice constant uuid := '00000000-0000-4000-8000-00000000000a';
  bob   constant uuid := '00000000-0000-4000-8000-00000000000b';
  carol constant uuid := '00000000-0000-4000-8000-00000000000c';
  conv  uuid;
  r     text;
  n     bigint;
  body_after text;
  msg_id uuid;
begin
  -- 1. A reads own profile
  n := pg_temp.count_as(alice, 'authenticated',
        format('select 1 from public.profiles where user_id = %L', alice));
  perform pg_temp.check_('1  A reads own profile', n = 1, 'rows=' || n);

  -- 1b. A updates own profile
  r := pg_temp.exec_as(alice, 'authenticated',
        format('update public.profiles set about = ''hi'' where user_id = %L', alice));
  perform pg_temp.check_('1b A updates own profile', r = 'OK', r);

  -- 2. A reads B profile with NO shared conversation -> invisible
  n := pg_temp.count_as(alice, 'authenticated',
        format('select 1 from public.profiles where user_id = %L', bob));
  perform pg_temp.check_('2  A cannot see B profile (no shared conversation)', n = 0, 'rows=' || n);

  -- 2b. A cannot update B profile (0 rows affected; RLS filters)
  r := pg_temp.exec_as(alice, 'authenticated',
        format('update public.profiles set about = ''hacked'' where user_id = %L', bob));
  select about into body_after from public.profiles where user_id = bob;
  perform pg_temp.check_('2b A cannot modify B profile', coalesce(body_after,'') <> 'hacked', coalesce(body_after,'<null>'));

  -- 6. anonymous client on restricted RPCs -> denied
  r := pg_temp.exec_as(alice, 'anon', 'select public.list_conversations()');
  perform pg_temp.check_('6a anon cannot call list_conversations', r like 'ERR 42501%', r);
  r := pg_temp.exec_as(alice, 'anon',
        'select public.find_profile_by_email(''bob@rls.test'')');
  perform pg_temp.check_('6b anon cannot call find_profile_by_email', r like 'ERR 42501%', r);
  r := pg_temp.exec_as(alice, 'anon',
        format('select public.open_direct_conversation(%L)', bob));
  perform pg_temp.check_('6c anon cannot call open_direct_conversation', r like 'ERR 42501%', r);

  -- 3. A opens a direct conversation with B
  r := pg_temp.exec_as(alice, 'authenticated',
        format('select public.open_direct_conversation(%L)', bob));
  perform pg_temp.check_('3  A opens direct conversation with B', r = 'OK', r);

  select id into conv from public.conversations
   where direct_key = least(alice::text, bob::text) || ':' || greatest(alice::text, bob::text);
  perform pg_temp.check_('3b conversation row exists with both members',
    conv is not null and (select count(*) from public.conversation_members where conversation_id = conv) = 2, coalesce(conv::text,'<null>'));

  -- 3c. A sends a message
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into public.messages (conversation_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), ''hello bob'')',
    conv, alice));
  perform pg_temp.check_('3c A sends message in own conversation', r = 'OK', r);

  -- 3d. B reads the message
  n := pg_temp.count_as(bob, 'authenticated',
        format('select 1 from public.messages where conversation_id = %L', conv));
  perform pg_temp.check_('3d B reads messages of shared conversation', n = 1, 'rows=' || n);

  -- 3e. profiles become mutually visible once a conversation is shared
  n := pg_temp.count_as(alice, 'authenticated',
        format('select 1 from public.profiles where user_id = %L', bob));
  perform pg_temp.check_('3e A sees B profile after sharing a conversation', n = 1, 'rows=' || n);

  -- 4. C (non-member) probing the conversation
  n := pg_temp.count_as(carol, 'authenticated',
        format('select 1 from public.conversations where id = %L', conv));
  perform pg_temp.check_('4a C cannot see the conversation', n = 0, 'rows=' || n);
  n := pg_temp.count_as(carol, 'authenticated',
        format('select 1 from public.messages where conversation_id = %L', conv));
  perform pg_temp.check_('4b C cannot read its messages', n = 0, 'rows=' || n);
  r := pg_temp.exec_as(carol, 'authenticated', format(
    'insert into public.messages (conversation_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), ''intruder'')',
    conv, carol));
  perform pg_temp.check_('4c C cannot send into it', r like 'ERR 42501%', r);

  -- anon sees nothing at all
  n := pg_temp.count_as(alice, 'anon', 'select 1 from public.messages');
  perform pg_temp.check_('6d anon sees zero messages', n = 0, 'rows=' || n);

  -- read states: B marks read (legit)
  select id into msg_id from public.messages where conversation_id = conv limit 1;
  r := pg_temp.exec_as(bob, 'authenticated', format(
    'insert into public.message_read_states (conversation_id, user_id, last_read_message_id) values (%L, %L, %L)',
    conv, bob, msg_id));
  perform pg_temp.check_('3f B upserts own read state', r = 'OK', r);

  -- 4d. C cannot write read states for a conversation it is not in
  r := pg_temp.exec_as(carol, 'authenticated', format(
    'insert into public.message_read_states (conversation_id, user_id, last_read_message_id) values (%L, %L, %L)',
    conv, carol, msg_id));
  perform pg_temp.check_('4d C cannot write read states', r like 'ERR 42501%', r);

  -- reactions
  r := pg_temp.exec_as(bob, 'authenticated', format(
    'insert into public.message_reactions (message_id, user_id, emoji) values (%L, %L, ''+1'')', msg_id, bob));
  perform pg_temp.check_('3g B reacts to message', r = 'OK', r);
  r := pg_temp.exec_as(carol, 'authenticated', format(
    'insert into public.message_reactions (message_id, user_id, emoji) values (%L, %L, ''+1'')', msg_id, carol));
  perform pg_temp.check_('4e C cannot react', r like 'ERR 42501%', r);

  -- attachments
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into public.message_attachments (message_id, storage_path, mime_type, size_bytes) values (%L, %L, ''image/png'', 10)',
    msg_id, conv || '/' || alice || '/a.png'));
  perform pg_temp.check_('3h A attaches to own message', r = 'OK', r);
  r := pg_temp.exec_as(bob, 'authenticated', format(
    'insert into public.message_attachments (message_id, storage_path, mime_type, size_bytes) values (%L, %L, ''image/png'', 10)',
    msg_id, conv || '/' || bob || '/b.png'));
  perform pg_temp.check_('4f B cannot attach to A message', r like 'ERR 42501%', r);

  -- message immutability: A cannot edit own message body
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'update public.messages set body = ''edited'' where id = %L', msg_id));
  perform pg_temp.check_('7a message body is immutable (no editing)', r like 'ERR%', r);

  -- soft delete: A deletes own message; body must blank
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'update public.messages set deleted_at = now() where id = %L', msg_id));
  select body into body_after from public.messages where id = msg_id;
  perform pg_temp.check_('7b A soft-deletes own message, body blanked',
    r = 'OK' and body_after = '', r || ' body=' || coalesce(body_after,'<null>'));

  -- B cannot delete A's message (RLS filters the update)
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into public.messages (conversation_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), ''second'')',
    conv, alice));
  select id into msg_id from public.messages where conversation_id = conv and body = 'second';
  r := pg_temp.exec_as(bob, 'authenticated', format(
    'update public.messages set deleted_at = now() where id = %L', msg_id));
  perform pg_temp.check_('7c B cannot delete A message',
    (select deleted_at from public.messages where id = msg_id) is null, r);

  -- 5. blocking: B blocks A -> A can no longer send or re-open
  r := pg_temp.exec_as(bob, 'authenticated', format(
    'insert into public.blocked_contacts (blocker_id, blocked_id) values (%L, %L)', bob, alice));
  perform pg_temp.check_('5a B blocks A', r = 'OK', r);
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into public.messages (conversation_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), ''after block'')',
    conv, alice));
  perform pg_temp.check_('5b blocked sender cannot send', r like 'ERR 42501%', r);
  r := pg_temp.exec_as(alice, 'authenticated',
        format('select public.open_direct_conversation(%L)', bob));
  perform pg_temp.check_('5c blocked user cannot open conversation', r like 'ERR%', r);
  perform pg_temp.check_('5d blocked pair invisible in email lookup',
    (pg_temp.count_as(alice, 'authenticated',
       'select * from public.find_profile_by_email(''bob@rls.test'')')) = 0, '');

  -- device sessions: owner-scoped
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into public.device_sessions (user_id, device_name, platform) values (%L, ''pixel'', ''android'')', alice));
  perform pg_temp.check_('8a A registers own device session', r = 'OK', r);
  n := pg_temp.count_as(bob, 'authenticated', 'select 1 from public.device_sessions');
  perform pg_temp.check_('8b B cannot see A sessions', n = 0, 'rows=' || n);

  -- 7 (storage). Policy-level checks against storage.objects.
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into storage.objects (bucket_id, name) values (''personal-media'', %L)',
    conv || '/' || alice || '/photo.png'));
  perform pg_temp.check_('9a member uploads under own path', r = 'OK', r);
  r := pg_temp.exec_as(alice, 'authenticated', format(
    'insert into storage.objects (bucket_id, name) values (''personal-media'', %L)',
    conv || '/' || bob || '/fake.png'));
  perform pg_temp.check_('9b cannot upload under another user''s path', r like 'ERR 42501%', r);
  r := pg_temp.exec_as(carol, 'authenticated', format(
    'insert into storage.objects (bucket_id, name) values (''personal-media'', %L)',
    conv || '/' || carol || '/sneak.png'));
  perform pg_temp.check_('9c non-member cannot upload to conversation', r like 'ERR 42501%', r);
  n := pg_temp.count_as(carol, 'authenticated',
        'select 1 from storage.objects where bucket_id = ''personal-media''');
  perform pg_temp.check_('9d non-member cannot list conversation media', n = 0, 'rows=' || n);
  n := pg_temp.count_as(bob, 'authenticated',
        'select 1 from storage.objects where bucket_id = ''personal-media''');
  perform pg_temp.check_('9e member can read conversation media', n = 1, 'rows=' || n);
end
$$;

-- ---------------------------------------------------------------------------
-- Report + hard failure if anything failed
-- ---------------------------------------------------------------------------
select case when pass then 'PASS' else 'FAIL' end as result, test, info
from _results order by seq;

do $$
declare
  failed int;
begin
  select count(*) into failed from _results where not pass;
  if failed > 0 then
    raise exception 'RLS MATRIX: % test(s) FAILED — see result set above', failed;
  end if;
  raise notice 'ALL RLS MATRIX TESTS PASSED (% checks)', (select count(*) from _results);
end
$$;

rollback;
