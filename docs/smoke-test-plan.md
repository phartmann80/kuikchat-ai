# Personal messaging — live smoke test plan (Milestone 1 gate 4)

Preconditions:

- `kuikchat-personal-dev` provisioned, migration 0001 applied cleanly
- `supabase-personal/tests/rls_matrix.sql` passed against it
- **Data API exposure verified**: `private` schema absent from the exposed
  schemas list (record the actual deployed setting as evidence), and
  `supabase-personal/tests/api_denial.sh` ends with
  `ALL API DENIAL CHECKS PASSED` (covers anon + authenticated helper-RPC
  denial, profile-header rejection, restricted RPC denial, empty
  unauthenticated table reads, real-UUID device-session ownership, and
  fixture-based private storage read/list denial — requires the storage
  fixture and non-member test account documented in the script header)
- Debug build installed on a device/emulator, launched with
  `--dart-define=PERSONAL_SUPABASE_URL=... --dart-define=PERSONAL_SUPABASE_ANON_KEY=...`
  (anon key only, delivered via the approved secret channel — never chat,
  commits, or PRs)
- Two fresh test accounts: `qa-a@…`, `qa-b@…` (test inboxes, not personal
  emails), ideally on two devices; one device + a second session via a
  second emulator is acceptable

## Steps (all must pass; record each)

| # | Step | Expected |
| --- | --- | --- |
| 1 | Sign in as A | lands in Personal Chats; empty state "No conversations yet"; no placeholder rows |
| 2 | Settings → Account | A's real profile loads from backend |
| 3 | New chat → B's email | conversation opens; empty conversation state |
| 4 | A sends "hello" | bubble appears instantly as sending (clock), transitions to sent (check) |
| 5 | B (second device) opens app | conversation listed with preview "hello" and unread badge |
| 6 | B opens conversation | message visible; A sees read receipt (double check) shortly after |
| 7 | B replies | A receives it in realtime without refresh |
| 8 | Realtime echo check | A's own sent message appears exactly once (no duplicate from the realtime echo) |
| 9 | A enables airplane mode, sends "offline msg" | bubble shows failed state + "Not sent. Tap to retry"; offline banner visible |
| 10 | A taps retry while still offline | stays failed; no crash |
| 11 | A disables airplane mode, taps retry | message transitions to sent |
| 12 | Idempotency check | in the dev DB: `select count(*) from messages where body = 'offline msg'` → exactly 1; `client_id` identical across the retry attempts (verify via logs/DB) |
| 13 | A long-presses own message → Delete | bubble becomes "Message deleted" on both devices; DB body blanked |
| 14 | A signs out | returns to sign-in; reopening the app does NOT show chats; no cached conversation accessible |
| 15 | Sign-in with wrong password | clear error banner, no crash |

## Screenshots / recording to attach to the PR

1. Personal/Business switching (both scopes)
2. Personal navigation (Chats, Settings)
3. Business navigation (Inbox, Customers, Settings — honest "not connected" states)
4. Settings navigation (Account with live profile, Appearance, About/licenses)
5. Empty chat state
6. Successful two-account messaging (both devices visible)
7. Failed-send + retry state (airplane mode)
8. Narrow-phone shell (≤ 400 dp width, icon-only switcher)

## Explicitly out of scope for this smoke test

Typing indicators, presence, media, calls, disappearing messages — not
implemented; must not be tested as if they were.
