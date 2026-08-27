-- ============================================================================
-- KuikChat PERSONAL environment - core schema, RLS, and RPC surface.
--
-- Target: a DEDICATED Supabase project for the Personal environment.
-- This is NOT the prototype web project (supabase/ at repo root) and NOT the
-- future Business project. Never apply Business tables to this project and
-- never join across environments.
--
-- Review status: written for review in Milestone 1. Apply with:
--   supabase db push   (linked to the Personal project only)
-- Rollback: this is migration 0001; rollback = drop schema objects listed
-- here (see docs/adr/ADR-001 "Failure and recovery").
-- ============================================================================

-- ---------------------------------------------------------------------------
-- private schema: internal authorization helpers.
--
-- PostgREST exposes only the `public` schema, so functions in `private`
-- have NO API surface. This prevents clients from probing block
-- relationships or conversation membership by calling helpers directly.
-- `authenticated` receives USAGE + per-function EXECUTE only because RLS
-- policies evaluate these helpers with the querying user's privileges.
-- ---------------------------------------------------------------------------
create schema private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
grant usage on schema private to service_role;
-- Future-proof: functions created in `private` later must opt IN to access.
alter default privileges in schema private revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  avatar_url   text,
  about        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Deliberately NO blanket "all authenticated users can browse profiles"
-- policy (the web prototype has one; it is a directory-harvesting risk).
-- Profiles are visible only to yourself and to people you share a
-- conversation with. Lookup by email goes through the rate-limitable RPC
-- find_profile_by_email below.
create policy "profiles: own row full read"
  on public.profiles for select to authenticated
  using (user_id = (select auth.uid()));

-- NOTE: "profiles: visible to conversation partners" is created further down,
-- after conversation_members exists.

create policy "profiles: insert own"
  on public.profiles for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Trigger-only: no role may call this via the API. EXECUTE was validated at
-- trigger creation (as postgres); firing does not re-check the caller.
-- supabase_auth_admin keeps EXECUTE as defense-in-depth for GoTrue.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- contacts / blocked contacts
-- ---------------------------------------------------------------------------
create table public.contacts (
  owner_id   uuid not null references public.profiles (user_id) on delete cascade,
  contact_id uuid not null references public.profiles (user_id) on delete cascade,
  alias      text,
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  check (owner_id <> contact_id)
);

alter table public.contacts enable row level security;

create policy "contacts: owner full access"
  on public.contacts for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create table public.blocked_contacts (
  blocker_id uuid not null references public.profiles (user_id) on delete cascade,
  blocked_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.blocked_contacts enable row level security;

create policy "blocked: owner full access"
  on public.blocked_contacts for all to authenticated
  using (blocker_id = (select auth.uid()))
  with check (blocker_id = (select auth.uid()));

create or replace function private.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.blocked_contacts
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

-- Not part of the API surface (private schema); anon has no access at all;
-- authenticated keeps the minimum EXECUTE needed for RLS policy evaluation.
revoke execute on function private.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function private.is_blocked_between(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- conversations + membership
-- ---------------------------------------------------------------------------
create table public.conversations (
  id                    uuid primary key default gen_random_uuid(),
  is_direct             boolean not null default true,
  title                 text,               -- null for direct conversations
  created_by            uuid not null references public.profiles (user_id),
  -- Disappearing messages: null = off; otherwise per-conversation TTL.
  disappearing_ttl_secs integer check (disappearing_ttl_secs is null or disappearing_ttl_secs > 0),
  -- Canonical de-duplication key for direct conversations ("uuidA:uuidB",
  -- sorted). Enforced unique so two users can only ever have one direct chat.
  direct_key            text unique,
  created_at            timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (user_id) on delete cascade,
  role            text not null default 'member' check (role in ('member', 'admin')),
  joined_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;

-- SECURITY DEFINER membership check avoids recursive RLS between
-- conversations and conversation_members. Lives in the non-exposed
-- `private` schema so it cannot be called through the API.
create or replace function private.is_conversation_member(conv uuid, member uuid)
returns boolean
language sql
stable
security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = member
  );
$$;

revoke execute on function private.is_conversation_member(uuid, uuid) from public, anon;
grant execute on function private.is_conversation_member(uuid, uuid) to authenticated, service_role;

create policy "conversations: members can read"
  on public.conversations for select to authenticated
  using (private.is_conversation_member(id, (select auth.uid())));

-- Creation happens exclusively through open_direct_conversation (below) so
-- membership + block checks are atomic. No direct INSERT policy on purpose.

create policy "members: members can read membership"
  on public.conversation_members for select to authenticated
  using (private.is_conversation_member(conversation_id, (select auth.uid())));

-- Deferred profile policy (needs conversation_members): profiles are visible
-- to people you share a conversation with. No browsable directory exists.
create policy "profiles: visible to conversation partners"
  on public.profiles for select to authenticated
  using (
    exists (
      select 1
      from public.conversation_members me
      join public.conversation_members them
        on them.conversation_id = me.conversation_id
      where me.user_id = (select auth.uid())
        and them.user_id = profiles.user_id
    )
  );

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null references public.profiles (user_id) on delete cascade,
  -- Client-generated idempotency key: retries can never duplicate a message.
  client_id       uuid not null,
  kind            text not null default 'text' check (kind in ('text')),
  body            text not null check (char_length(body) <= 4000),
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  -- Disappearing messages: server-computed expiry, swept by scheduled job.
  expires_at      timestamptz,
  unique (conversation_id, sender_id, client_id),
  -- Composite key target so read states can enforce that the referenced
  -- message belongs to the same conversation (see message_read_states).
  unique (conversation_id, id)
);

create index idx_messages_conversation_created
  on public.messages (conversation_id, created_at desc);

alter table public.messages enable row level security;

create policy "messages: members can read"
  on public.messages for select to authenticated
  using (private.is_conversation_member(conversation_id, (select auth.uid())));

create policy "messages: members can send as themselves"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
    -- Block enforcement: cannot send when any other member has a block
    -- relationship with the sender (direct conversations).
    and not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.user_id <> (select auth.uid())
        and private.is_blocked_between(cm.user_id, (select auth.uid()))
    )
  );

-- Update is restricted to soft-deleting YOUR OWN message. A trigger keeps
-- body/sender/conversation immutable.
create policy "messages: sender can soft delete own"
  on public.messages for update to authenticated
  using (sender_id = (select auth.uid()))
  with check (sender_id = (select auth.uid()));

create or replace function public.enforce_message_immutability()
returns trigger
language plpgsql
as $$
begin
  if new.conversation_id <> old.conversation_id
     or new.sender_id <> old.sender_id
     or new.client_id <> old.client_id
     or new.created_at <> old.created_at
     or (old.deleted_at is not null and new.deleted_at is distinct from old.deleted_at)
     -- No message editing: body may only change as part of soft deletion.
     or (new.deleted_at is null and new.body is distinct from old.body)
  then
    raise exception 'messages are immutable except for soft deletion';
  end if;
  if new.deleted_at is not null then
    new.body := '';
  end if;
  return new;
end;
$$;

create trigger messages_immutability
  before update on public.messages
  for each row execute function public.enforce_message_immutability();

revoke execute on function public.enforce_message_immutability() from public, anon, authenticated;

-- Disappearing messages: stamp expiry from the conversation setting.
create or replace function public.stamp_message_expiry()
returns trigger
language plpgsql
security definer set search_path = public, pg_temp
as $$
declare
  ttl integer;
begin
  select disappearing_ttl_secs into ttl
    from public.conversations where id = new.conversation_id;
  if ttl is not null then
    new.expires_at := now() + make_interval(secs => ttl);
  end if;
  return new;
end;
$$;

create trigger messages_stamp_expiry
  before insert on public.messages
  for each row execute function public.stamp_message_expiry();

revoke execute on function public.stamp_message_expiry() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- attachments / reactions / read states
-- ---------------------------------------------------------------------------
create table public.message_attachments (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid not null references public.messages (id) on delete cascade,
  storage_path text not null,           -- object in the private personal-media bucket
  mime_type    text not null,
  size_bytes   bigint not null check (size_bytes > 0),
  created_at   timestamptz not null default now()
);

alter table public.message_attachments enable row level security;

create policy "attachments: conversation members can read"
  on public.message_attachments for select to authenticated
  using (
    exists (
      select 1 from public.messages m
      where m.id = message_id
        and private.is_conversation_member(m.conversation_id, (select auth.uid()))
    )
  );

create policy "attachments: sender can attach to own message"
  on public.message_attachments for insert to authenticated
  with check (
    exists (
      select 1 from public.messages m
      where m.id = message_id and m.sender_id = (select auth.uid())
    )
  );

create table public.message_reactions (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  emoji      text not null check (char_length(emoji) <= 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

alter table public.message_reactions enable row level security;

create policy "reactions: members can read"
  on public.message_reactions for select to authenticated
  using (
    exists (
      select 1 from public.messages m
      where m.id = message_id
        and private.is_conversation_member(m.conversation_id, (select auth.uid()))
    )
  );

create policy "reactions: members write own"
  on public.message_reactions for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.messages m
      where m.id = message_id
        and private.is_conversation_member(m.conversation_id, (select auth.uid()))
    )
  );

create policy "reactions: delete own"
  on public.message_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

create table public.message_read_states (
  conversation_id      uuid not null references public.conversations (id) on delete cascade,
  user_id              uuid not null references public.profiles (user_id) on delete cascade,
  last_read_message_id uuid not null,
  last_read_at         timestamptz not null default now(),
  primary key (conversation_id, user_id),
  -- Integrity: the referenced message MUST belong to the same conversation.
  -- A plain FK to messages(id) would allow cross-conversation read states.
  foreign key (conversation_id, last_read_message_id)
    references public.messages (conversation_id, id) on delete cascade
);

alter table public.message_read_states enable row level security;

create policy "read states: members can read"
  on public.message_read_states for select to authenticated
  using (private.is_conversation_member(conversation_id, (select auth.uid())));

create policy "read states: upsert own"
  on public.message_read_states for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
  );

-- Both the existing row (USING) and the new row (WITH CHECK) must belong to
-- the caller AND to a conversation the caller is currently a member of, so
-- a read state can never be moved into a non-member conversation or
-- reassigned to another user.
create policy "read states: update own"
  on public.message_read_states for update to authenticated
  using (
    user_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
  )
  with check (
    user_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- device sessions + encryption metadata
--
-- NOTE ON ENCRYPTION: messages are protected by TLS in transit and encryption
-- at rest on the database. This is NOT end-to-end encryption; the server can
-- read message bodies. The table below only reserves the metadata surface for
-- a future E2EE rollout (key registration per device). Product copy must not
-- claim E2EE until that work ships. See ADR-001.
-- ---------------------------------------------------------------------------
create table public.device_sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (user_id) on delete cascade,
  device_name  text not null,
  platform     text not null check (platform in ('android', 'web')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at   timestamptz
);

alter table public.device_sessions enable row level security;

create policy "device sessions: owner full access"
  on public.device_sessions for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table public.encryption_keys (
  user_id    uuid not null references public.profiles (user_id) on delete cascade,
  device_id  uuid not null references public.device_sessions (id) on delete cascade,
  key_type   text not null check (key_type in ('identity', 'signed_prekey', 'one_time_prekey')),
  public_key text not null,             -- public material only; private keys never leave the device
  created_at timestamptz not null default now(),
  primary key (user_id, device_id, key_type, public_key)
);

alter table public.encryption_keys enable row level security;

create policy "encryption keys: owner writes own"
  on public.encryption_keys for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "encryption keys: conversation partners can read public keys"
  on public.encryption_keys for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.conversation_members me
      join public.conversation_members them
        on them.conversation_id = me.conversation_id
      where me.user_id = (select auth.uid())
        and them.user_id = encryption_keys.user_id
    )
  );

-- ---------------------------------------------------------------------------
-- RPC surface used by the Flutter client
-- ---------------------------------------------------------------------------

-- Exact-email profile lookup. Returns at most one minimal profile row.
-- Never exposes a browsable directory; email itself is not returned.
create or replace function public.find_profile_by_email(lookup_email text)
returns table (user_id uuid, display_name text, avatar_url text, about text)
language sql
stable
security definer set search_path = public, pg_temp
as $$
  select p.user_id, p.display_name, p.avatar_url, p.about
  from public.profiles p
  join auth.users u on u.id = p.user_id
  where lower(u.email) = lower(trim(lookup_email))
    and not private.is_blocked_between(p.user_id, (select auth.uid()))
  limit 1;
$$;

revoke execute on function public.find_profile_by_email(text) from public, anon;
grant execute on function public.find_profile_by_email(text) to authenticated;

-- Atomically returns-or-creates the direct conversation between the caller
-- and other_user, enforcing block lists.
create or replace function public.open_direct_conversation(other_user uuid)
returns json
language plpgsql
security definer set search_path = public, pg_temp
as $$
declare
  self_id uuid := (select auth.uid());
  conv_id uuid;
  dkey text;
begin
  if self_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if other_user = self_id then
    raise exception 'cannot open a conversation with yourself';
  end if;
  if not exists (select 1 from public.profiles where user_id = other_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if private.is_blocked_between(self_id, other_user) then
    raise exception 'conversation not allowed' using errcode = '42501';
  end if;

  dkey := least(self_id::text, other_user::text) || ':' || greatest(self_id::text, other_user::text);

  select id into conv_id from public.conversations where direct_key = dkey;
  if conv_id is null then
    insert into public.conversations (is_direct, created_by, direct_key)
    values (true, self_id, dkey)
    on conflict (direct_key) do update set direct_key = excluded.direct_key
    returning id into conv_id;

    insert into public.conversation_members (conversation_id, user_id)
    values (conv_id, self_id), (conv_id, other_user)
    on conflict do nothing;
  end if;

  return (
    select json_build_object(
      'id', c.id,
      'is_direct', c.is_direct,
      'title', coalesce(c.title, (
        select p.display_name from public.profiles p
        join public.conversation_members cm on cm.user_id = p.user_id
        where cm.conversation_id = c.id and p.user_id <> self_id
        limit 1
      )),
      'member_ids', (
        select json_agg(cm.user_id) from public.conversation_members cm
        where cm.conversation_id = c.id
      ),
      'last_message_preview', null,
      'last_message_at', null,
      'unread_count', 0
    )
    from public.conversations c where c.id = conv_id
  );
end;
$$;

revoke execute on function public.open_direct_conversation(uuid) from public, anon;
grant execute on function public.open_direct_conversation(uuid) to authenticated;

-- Conversation list for the caller, newest activity first.
create or replace function public.list_conversations()
returns json
language sql
stable
security definer set search_path = public, pg_temp
as $$
  select coalesce(json_agg(item order by item->>'last_message_at' desc nulls last), '[]'::json)
  from (
    select json_build_object(
      'id', c.id,
      'is_direct', c.is_direct,
      'title', coalesce(c.title, (
        select p.display_name from public.profiles p
        join public.conversation_members cm2 on cm2.user_id = p.user_id
        where cm2.conversation_id = c.id and p.user_id <> (select auth.uid())
        limit 1
      )),
      'member_ids', (
        select json_agg(cm3.user_id) from public.conversation_members cm3
        where cm3.conversation_id = c.id
      ),
      'last_message_preview', (
        select case when m.deleted_at is not null then 'Message deleted' else m.body end
        from public.messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1
      ),
      'last_message_at', (
        select m.created_at from public.messages m
        where m.conversation_id = c.id
        order by m.created_at desc limit 1
      ),
      'unread_count', (
        select count(*) from public.messages m
        where m.conversation_id = c.id
          and m.sender_id <> (select auth.uid())
          and m.deleted_at is null
          and m.created_at > coalesce((
            select rs.last_read_at from public.message_read_states rs
            where rs.conversation_id = c.id and rs.user_id = (select auth.uid())
          ), 'epoch'::timestamptz)
      )
    ) as item
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where cm.user_id = (select auth.uid())
  ) items;
$$;

revoke execute on function public.list_conversations() from public, anon;
grant execute on function public.list_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_read_states;

-- Realtime authorization: postgres_changes subscriptions respect the RLS
-- policies above, so a client only receives events for conversations it is
-- a member of. Typing indicators and presence will use authorized broadcast
-- channels (private channels), not database tables.

-- ---------------------------------------------------------------------------
-- Storage: PRIVATE media bucket. No public buckets in the Personal project.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('personal-media', 'personal-media', false);

-- Objects live under <conversation_id>/<uploader_uuid>/<uuid>.<ext>.
create policy "personal-media: members read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'personal-media'
    and private.is_conversation_member(((storage.foldername(name))[1])::uuid, (select auth.uid()))
  );

create policy "personal-media: members upload own path"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'personal-media'
    and private.is_conversation_member(((storage.foldername(name))[1])::uuid, (select auth.uid()))
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );
