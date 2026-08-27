# ADR-001: Personal / Business isolation and Personal backend platform

- Status: Proposed (needs sign-off from KuikChat technical direction)
- Date: 2026-08-27
- Owners: Architecture workstream (Developer E), reviewed by B and D

## Context

KuikChat is one Android application containing two independent environments:
Personal (consumer messaging) and Business (professional inbox, CRM, billing).
The directive requires separate navigation, service boundaries, permissions,
database environments, storage buckets, security policies, realtime channels,
and analytics/audit boundaries. The existing Vite/React web prototype and its
Supabase project remain in place and untouched.

## Decision 1 — Why Personal and Business are isolated

Personal and Business run on **separate Supabase projects** (separate
Postgres databases, separate auth user pools, separate storage, separate
realtime clusters, separate API keys).

Rationale:

- **Blast radius.** A vulnerability, leaked key, or bad RLS policy in one
  environment cannot expose the other's data.
- **Different data protection profiles.** Personal data is consumer PII with
  GDPR erasure semantics; Business data includes customer records, audit
  logs, and billing state with retention obligations. One retention policy
  cannot serve both.
- **Different permission models.** Personal is symmetric (peers in
  conversations); Business is hierarchical (org -> team -> agent -> customer)
  and needs admin audit logging. Mixing them in one schema invites unscoped
  queries.
- **Independent scaling and migration cadence.** Business schema churn (CRM,
  automations) must never require a migration window on the Personal
  messaging database.
- **No cross-platform joins by construction.** With separate projects, a
  cross-environment join is impossible at the database level, not just
  forbidden by convention.

Cost accepted: a user with both roles has two accounts/sessions; any future
cross-environment feature must go through an explicit server-side API, never
a database join. We accept this deliberately.

## Decision 2 — Database deployment model and environment naming

Four isolated environments (plus the frozen prototype). Exact names:

| Environment | Supabase project | Status | Migrations source of truth |
| --- | --- | --- | --- |
| Personal development | `kuikchat-personal-dev` | **required for Milestone 1** — provisioning is the current blocker | `supabase-personal/migrations/` |
| Personal production | `kuikchat-personal-prod` | NOT provisioned; only after dev migration + RLS matrix pass | `supabase-personal/migrations/` |
| Business development | `kuikchat-business-dev` | later workstream; NOT provisioned | `supabase-business/migrations/` (directory does not exist yet — created when the Business workstream starts) |
| Business production | `kuikchat-business-prod` | later workstream; NOT provisioned | `supabase-business/migrations/` |
| Web prototype (existing) | current project | frozen; to be migrated later, nothing deleted | `supabase/migrations/` |

Source-of-truth rules (no ambiguity permitted):

- `supabase/` applies ONLY to the existing web prototype project. It must
  never be applied to any Personal or Business project.
- `supabase-personal/` applies ONLY to `kuikchat-personal-dev` and, after
  acceptance, `kuikchat-personal-prod`.
- Business projects will get their own directory, their own migrations,
  their own storage buckets, their own realtime channels, and their own
  policies. Business must NOT reuse Personal tables, migrations, repository
  classes, or authorization policies — not even by copy-rename; it gets its
  own reviewed contract.
- Migrations are applied only by CI or a release engineer via
  `supabase db push` against the explicitly linked project — never by hand
  in the dashboard.

Verification gate: `kuikchat-personal-prod` may not be created until
migration 0001 applies cleanly to `kuikchat-personal-dev` AND
`supabase-personal/tests/rls_matrix.sql` passes there.

## Decision 3 — Authentication and session strategy

- Supabase Auth (GoTrue) per project. Personal client uses email+password in
  Milestone 1; OAuth and phone sign-in are later, additive work.
- The Flutter client holds only the **anon (publishable) key**, injected at
  build time via `--dart-define`. Anon keys are safe to embed because every
  table has RLS; still, keys are not committed to the repository.
- **No service-role key ever ships in any client** (Flutter or web). Service
  role is used only by server-side jobs (Edge Functions, sweepers).
- Sessions: Supabase refresh-token sessions, stored by `supabase_flutter` in
  platform secure storage. `device_sessions` table records active devices;
  revocation UI is a security-workstream deliverable and is **not implemented
  yet** (recorded honestly — see Non-goals).
- App-based 2FA and backup codes: planned on Supabase Auth MFA (TOTP). **Not
  implemented in Milestone 1** and not claimed anywhere in the product.

## Decision 4 — Storage access strategy

- One **private** bucket per concern; the first is `personal-media`. There
  are **no public buckets** in the Personal project.
- Object paths are structured (`<conversation_id>/<uploader_id>/<uuid>`), and
  storage RLS policies authorize reads by conversation membership and writes
  by uploader identity.
- Clients access media exclusively through short-lived signed URLs created
  after an authorized read.
- The prototype web project's public `avatars` bucket is a known gap in the
  old project; the Personal project does not repeat it.

## Decision 5 — Realtime authorization

- Message and read-state delivery uses Postgres Changes subscriptions, which
  enforce the same RLS policies as queries: a client can only receive events
  for conversations it is a member of.
- Typing indicators and presence will use **private broadcast/presence
  channels** authorized per conversation (no database writes per keystroke).
  Channel authorization must be verified in tests before typing/presence
  ships; until then the client shows no typing/presence UI.

## Decision 6 — Backup and restore

- Supabase automated daily backups on both Personal instances; prod
  additionally uses PITR when we move to a paid tier.
- Restore procedure: restore to a fresh instance, verify, then repoint via
  environment configuration (`--dart-define` values in the build pipeline);
  the app has an explicit "backend not configured" state, so a misconfigured
  build fails loudly and honestly.
- Restore drills are a release-blocking checklist item before production
  rollout (phase 10). **No restore has been rehearsed yet.**

## Decision 7 — Encryption responsibilities

- Today: TLS in transit, provider encryption at rest. **This is transport +
  at-rest encryption, NOT end-to-end encryption.** The server can read
  message bodies. Product copy, marketing pages, and in-app text must not
  say "end-to-end encrypted" until an E2EE protocol actually ships.
- The `encryption_keys` table reserves the metadata surface (per-device
  public identity keys / prekeys) for a future E2EE rollout modeled on the
  Signal protocol. Private keys will never leave devices; the server stores
  public material only.
- Key handling for E2EE (generation, rotation, verification UX, multi-device)
  is its own ADR before implementation.

## Decision 8 — Account deletion

- Personal: deletion of the auth user cascades through `profiles` to all
  owned rows (FKs are `on delete cascade`). Messages authored by the deleted
  user in other people's conversations are soft-deleted (body cleared) rather
  than removed, preserving conversation integrity — same model as WhatsApp.
- Deletion is executed by a server-side function (service role, Edge
  Function) after re-authentication; the client can only request it.
- "Account self-destruct" (timed deletion) is a security-workstream feature
  layered on the same server-side path. **Not implemented yet.**

## Decision 9 — Data retention

- Messages: retained until user deletion, conversation deletion, or
  disappearing-message expiry (`expires_at`, swept by a scheduled server-side
  job — the sweeper is required before disappearing messages are exposed in
  UI).
- Device sessions: revoked sessions retained 90 days for security forensics
  (estimate; to be confirmed with counsel).
- Business (future) will define its own retention/audit rules in its own ADR.

## Decision 10 — GDPR / privacy

- Lawful basis: contract performance for messaging; consent for optional
  features (e.g., contact sync — not implemented).
- Data subject rights: export and erasure are served per environment; because
  projects are isolated, a Personal erasure cannot leak into or depend on
  Business data.
- Data minimization: profile lookup by exact email only (no user directory);
  emails are not exposed through the API surface; no analytics SDK is present
  in the Milestone 1 client.
- EU hosting region for both Personal instances.

## Decision 11 — Failure and recovery behavior

- The client treats the backend as unreliable by design: every repository
  call maps errors to typed failures (network / unauthorized / not-found /
  blocked / conflict), and the UI has explicit offline, failed-send, retry,
  and unauthorized states.
- Sends are **idempotent**: a client-generated `client_id` with a unique
  constraint means a retry after timeout can never duplicate a message.
- Realtime disconnects degrade to manual refresh; reconnection re-syncs via
  history load. (Automatic gap-fill on reconnect is Milestone 2 work.)
- Rollback of migration 0001: drop the created tables/functions/policies and
  the `personal-media` bucket; no other system references them yet.

## Rollback procedure

- **Client:** revert the offending commit(s) on the feature branch; the web
  app is untouched by mobile changes (`mobile/` is additive). A broken
  mobile build never affects web deployment.
- **Migration 0001 (pre-production only):** drop the created objects —
  tables (`profiles`, `contacts`, `blocked_contacts`, `conversations`,
  `conversation_members`, `messages`, `message_attachments`,
  `message_reactions`, `message_read_states`, `device_sessions`,
  `encryption_keys`), the `private` schema with its helpers
  (`private.is_blocked_between`, `private.is_conversation_member`),
  public functions (`handle_new_user`, `enforce_message_immutability`,
  `stamp_message_expiry`, `find_profile_by_email`,
  `open_direct_conversation`, `list_conversations`), the trigger on
  `auth.users`, and the `personal-media` bucket. Because dev holds no real
  user data, dropping and re-applying is the approved rollback. Once
  production data exists, rollbacks require forward-fix migrations plus the
  backup/restore path above — destructive rollback is then forbidden.
- **Configuration:** builds are pointed at a backend exclusively via
  `--dart-define`; rolling back an environment repoint is a rebuild with the
  previous values.

## Review triggers

This ADR must be re-reviewed before any of the following:

- Provisioning any production project
- Introducing the Business backend (new ADR required)
- Any E2EE implementation work (new ADR required)
- Adding cross-environment features of any kind
- Changing authentication providers or session storage
- Adding a new storage bucket or making any bucket public (public buckets
  are currently forbidden)
- Adding analytics or telemetry to the mobile client

## Capacity and performance

No load testing has been performed. **Any throughput/latency figures anyone
quotes for this system are estimates until a load test exists.** Baseline
load tests are scheduled before the production rollout phase.

## Non-goals of Milestone 1 (explicitly not implemented)

2FA, backup codes, session revocation UI, ghost mode, account self-destruct,
disappearing-message sweeper, media upload, calls, stories/short video,
Hermes AI in the mobile client, billing, Business backend. None of these are
claimed in product UI or docs as existing.
