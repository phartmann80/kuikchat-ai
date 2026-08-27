# Milestone 1 status — Flutter foundation + Personal messaging slice

Date: 2026-08-27
Branch: `arena/01a04418-kuikchat-ai`

## Acceptance criteria tracking

| Criterion | State | Evidence / notes |
| --- | --- | --- |
| Flutter Android project builds | Pending CI | Full project committed under `mobile/`; Flutter/Android SDK downloads are blocked in the authoring sandbox (Google-hosted), so build/analyze/test run in GitHub Actions (`mobile-ci.yml`) and on developer machines |
| Personal/Business switching works | Implemented | `AppShell` + `platformScopeProvider`; covered by widget test |
| Personal and Business navigation visibly separate | Implemented | Separate destination sets and screens; widget test asserts separation |
| Settings sections navigable | Implemented | Account (live profile + sign out), Appearance, About (real license page) |
| Dark theme consistent | Implemented | Single Material 3 dark theme, brand blue/green from web tokens |
| No emoji-style UI icons | Implemented | Lucide icons only, names verified against Lucide v0.257.0 |
| Existing web app still builds | Verified | `npm ci && npm run build` exit 0 in sandbox (vite 5.4.19) |
| No fake conversations | Implemented | Empty states everywhere; widget test asserts no placeholder tiles |
| Personal backend contract documented | Done | `docs/personal-backend-contract.md` |
| Personal migrations + RLS reviewed | Ready for review | `supabase-personal/migrations/0001_personal_core.sql`; syntax validated with libpg_query (64 statements OK); needs human review + staging apply |
| Personal text messaging works end to end | Code complete, unverified against live backend | Requires a provisioned Personal Supabase project; repositories + RPCs implemented |
| Realtime message delivery works | Code complete, unverified against live backend | postgres_changes under RLS; reconciliation covered by unit test with fakes |
| Failed-send and retry states work | Implemented + unit tested | Idempotent `client_id`; state machine tests |
| Automated tests pass | Pending CI | 17 tests committed; cannot execute in authoring sandbox (no Dart SDK reachable) |
| No secrets committed | Verified | grep audit; endpoints via `--dart-define` only; anon key only, never service-role |

## Honest limitations

- No screenshot/recording yet: no Android SDK/emulator available in the
  authoring environment. First device run must be captured by Developer A.
- Messaging is not yet exercised against a live Personal Supabase project —
  provisioning the project and applying migration 0001 is the current
  blocker for end-to-end verification.
- Current encryption is TLS + at-rest only. It is NOT end-to-end encryption
  and is not described as such anywhere.
- 2FA, session revocation UI, ghost mode, disappearing-message sweeper,
  media upload, calls, Hermes AI in mobile, billing: not implemented, not
  claimed.
