# Personal backend contract (v1)

Scope: the PERSONAL environment only. Business has no backend yet and will
get its own contract, project, and documentation. Nothing in this document
may be joined to or reused by Business.

Backing service: dedicated Supabase project (`supabase-personal/`), applied
via `supabase-personal/migrations/0001_personal_core.sql`.

## Domains and tables

| Domain | Table / mechanism | Notes |
| --- | --- | --- |
| Authentication | Supabase Auth (email+password) | anon key in client, RLS everywhere, no service-role key in clients |
| User profiles | `profiles` | auto-created by trigger on signup; visible only to self and conversation partners |
| Contacts | `contacts` | owner-scoped saved contacts with alias |
| Conversations | `conversations` | direct conversations de-duplicated via `direct_key`; group-ready membership model |
| Conversation members | `conversation_members` | roles `member`/`admin` |
| Messages | `messages` | text v1, 4000-char input limit, idempotent `client_id`, soft delete, immutability trigger |
| Message attachments | `message_attachments` | metadata rows; binary data in private `personal-media` bucket |
| Reactions | `message_reactions` | one row per (message, user, emoji) |
| Read states | `message_read_states` | per-user watermark (`last_read_message_id`) |
| Typing state | realtime private broadcast channel (planned) | no table; no UI until channel authorization is tested |
| Presence | realtime presence channel (planned) | no table; same condition |
| Blocked contacts | `blocked_contacts` | enforced inside `open_direct_conversation` and profile lookup |
| Message deletion | `messages.deleted_at` | update policy limited to sender; trigger blanks body |
| Disappearing messages | `conversations.disappearing_ttl_secs` + `messages.expires_at` | expiry stamped by trigger; server-side sweeper REQUIRED before UI exposure |
| Device sessions | `device_sessions` | inventory for future revocation UI |
| Encryption metadata | `encryption_keys` | public key material only; reserved for future E2EE — current system is NOT E2EE |

## RPC surface (what the Flutter client calls)

| Function | Auth | Purpose |
| --- | --- | --- |
| `find_profile_by_email(text)` | authenticated only | exact-email minimal profile lookup; respects block lists; no directory browsing; email never returned |
| `open_direct_conversation(uuid)` | authenticated only | atomic get-or-create direct conversation; enforces blocks + membership |
| `list_conversations()` | authenticated only | caller's conversations with preview, last activity, unread count |

Everything else is plain table access under RLS:
`messages` (select/insert/soft-delete-update), `message_read_states`
(select/upsert), realtime subscriptions on both.

## Authorization rules (enforced server-side)

1. Every user-owned table has RLS enabled; there are no policy-less tables.
2. Membership checks go through `is_conversation_member()` (SECURITY
   DEFINER) — every conversation operation is authorized per call.
3. Senders can only insert messages as themselves and only into
   conversations they are members of.
4. Messages are immutable after insert except sender soft-deletion.
5. Storage: `personal-media` is private; reads require conversation
   membership, writes require the uploader path prefix to match the caller.
6. Realtime postgres_changes respects the same RLS policies.
7. `anon` role has no execute rights on the RPC surface.

## Client failure contract

Repositories map backend errors to typed failures the UI must handle:
`network`, `unauthorized`, `notFound`, `blocked`, `conflict`, `rateLimited`,
`notConfigured`, `unknown`. Send operations are idempotent via `client_id`;
retry re-uses the same id.

## Explicitly not implemented (do not claim otherwise)

- End-to-end encryption (current: TLS + at-rest only)
- 2FA / backup codes / session revocation UI
- Typing indicators / presence (channel auth not yet tested)
- Media upload pipeline (bucket + policies exist; no client code)
- Disappearing-message sweeper job
- Rate limiting beyond Supabase defaults (dedicated limits are a
  security-hardening deliverable)
