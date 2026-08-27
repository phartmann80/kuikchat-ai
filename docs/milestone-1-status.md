# Milestone 1 status — Flutter foundation + Personal messaging slice

Date: 2026-08-27 (updated after review decision: **approved with changes —
not accepted for merge**)
Branch: `arena/01a04418-kuikchat-ai`
Status: `Ready for review — not approved for merge`

## Merge gates from the review, and their current state

| # | Required action | State | Owner |
| --- | --- | --- | --- |
| 1 | CI enabled and executed | **Blocked on maintainer**: automation account lacks GitHub `workflows` permission; workflow files are staged in `ci/` with move instructions (`ci/README.md`). Flutter pinned to **3.47.2**; all third-party actions pinned to **immutable commit SHAs**; `libpg-query` pinned to **17.7.4**; pin-update process documented in `ci/README.md`. CI includes analyze, tests, debug APK, secret scan (gitleaks), SQL validation (libpg_query), architecture-boundary guard, and lockfile drift check | Maintainer + Dev D |
| 1b | Commit `pubspec.lock` | **Blocked on toolchain**: the authoring sandbox cannot reach Flutter/Dart SDK or pub.dev archives (Google-hosted endpoints blocked), so `pub get` cannot run here. First CI run uploads `pubspec.lock` as an artifact for a maintainer to commit; from then on CI fails on lockfile drift | Dev D |
| 2 | Migration applied to real Personal dev project | **Blocked on provisioning** of `kuikchat-personal-dev`. Ready to execute: migration 0001 + executable authorization matrix `supabase-personal/tests/rls_matrix.sql` (**49 checks**: own records, cross-user access, shared vs non-member conversations, block enforcement, anon RPC denial, helper direct-call denial, temp-schema shadowing regression, storage paths, immutability, soft delete, read states, reactions, attachments, device sessions; self-cleaning ROLLBACK) | Dev B |
| 2b | Helper-function exposure correction (review of c2c247d) | **Done in migration 0001** (not yet applied anywhere, so corrected in place): `private.is_blocked_between` / `private.is_conversation_member` moved to the non-exposed `private` schema; `anon` has no schema access; `authenticated` keeps only the minimal EXECUTE needed for RLS evaluation; all policy/trigger/function references updated; every SECURITY DEFINER function pins `search_path = public, pg_temp`; trigger functions revoked from all client roles; matrix tests 10a–10d and 11a–11b added. Live re-run still required on gate 2 | Dev B + D |
| 2c | Data API exposure proof (review of 871933a, corrected per review of be433e0) | **Prepared, blocked on gate 2 for execution**: `supabase-personal/tests/api_denial.sh` rewritten per review — parses and validates the real authenticated `USER_ID`/`USER_JWT` (hard exit 2 if unparseable, never continues with an invalid filter); device-session checks use the real UUID (`user_id=neq.<uuid>` + owner-can-read-own + cross-user denial + filter-accepted); storage tests are fixture-based (`TEST_MEDIA_OBJECT_PATH`, authorized-read-must-succeed gate, real `POST /object/list` endpoint, disclosure of the known object is a hard failure, 405 never accepted, non-member authenticated account required); transport errors reported separately and never as a pass; temp files cleaned via trap; credentials/tokens never printed (dry-run verified). Exposed-schema evidence recording required in output | Dev B + D |
| 2d | Read-state integrity hardening (review of 871933a) | **Done in migration 0001**: update policy now requires membership in both USING and WITH CHECK; composite FK `(conversation_id, last_read_message_id) → messages (conversation_id, id)` (backed by new unique key on messages) makes cross-conversation read states impossible at the constraint level; matrix section 12 added (12a–12e: same-conversation create, cross-conversation reference denial, non-member move denial, non-member update no-op, user reassignment denial). Live run pending gate 2 | Dev B |
| 2e | CI least-privilege permissions (review of 871933a) | **Done**: both workflows declare top-level `permissions: contents: read`; no write scopes | Dev D |
| 3 | Environment naming and isolation documented | **Done**: ADR-001 Decision 2 now specifies `kuikchat-personal-dev/prod`, `kuikchat-business-dev/prod`, source-of-truth mapping for `supabase/` vs `supabase-personal/` vs future `supabase-business/`, and the rule that Business may not copy-rename Personal code or policies | Dev E |
| 4 | Live two-account smoke test | **Blocked on gate 2**. Executable plan with step-by-step expectations and required screenshot list: `docs/smoke-test-plan.md` | Dev A + C |
| 5 | Flutter implementation review checklist | **Done in code** (see below) | Dev A |
| 6 | Documentation completeness | **Done**: ADR-001 now includes explicit rollback procedure and review triggers; encryption remains documented as TLS + at-rest, NOT E2EE | Dev E |

## Review checklist item 5 — verification notes

- No Supabase calls in widgets: enforced by `tools/check_boundaries.sh`
  (now a CI step); currently passing.
- No service-role/provider secrets in client code: boundary check rule 4 +
  gitleaks in CI; grep audit passing.
- Personal repositories cannot receive Business data types: no Business
  types exist; boundary check rule 3 fails CI if a Business import ever
  appears under `lib/{data,domain}/personal/`.
- Platform switching: each scope keeps its own navigation index; switching
  scopes swaps the full destination set and screen (widget-tested).
- Narrow phone viewport: switcher becomes icon-only below 400 dp and the
  title ellipsizes; new widget test at 360×690 asserts no layout exceptions
  in both scopes.
- Settings accuracy: there are **no local-state toggles presented as saved
  settings**. Account = live backend profile + sign out (backend call);
  Appearance = a factual statement that only one dark theme ships (no
  toggle); About = real version + real license page.
- No "coming soon" labels; no fake conversations/customers (widget-tested).
- Lucide icon names: all 34 used names verified against the Lucide v0.257.0
  icon set (the pinned package's generation source); one fix applied
  (`penSquare` → `edit`).
- Android permissions: `INTERNET` only, matching implemented capability.

## Honest limitations (unchanged unless noted)

- No build/analyzer/test execution and no device screenshots can be produced
  from the authoring sandbox (Flutter/Dart/Android SDK downloads and pub.dev
  archives are network-blocked there). CI and a developer machine are the
  execution paths; commands and pinned versions are committed.
- The RLS matrix is written and parser-validated but has NOT yet run against
  a live database — that is exactly what gate 2 requires.
- Encryption today: TLS in transit + provider at-rest. **NOT end-to-end
  encryption**, and stated as such everywhere.
- Not implemented and not claimed: 2FA, backup codes, session revocation UI,
  ghost mode, self-destruct, disappearing-message sweeper, media upload,
  calls, Hermes AI in mobile, billing, Business backend, typing/presence.

## No production work has started on WebRTC, Stripe, or short video, per the review decision.
