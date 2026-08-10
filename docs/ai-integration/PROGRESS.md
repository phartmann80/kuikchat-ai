# KuikChat AI Integration Progress

## Status: Phase 1 - In Progress

## Decisions

- Langdock EU OpenAI-compatible API is primary with `gpt-5.4-mini`.
- Langdock is the production Hermes text provider.
- Logicc is the approved secondary text provider (inactive until configured).
- Provider failover to any non-approved router has been removed from `ai-gateway`.
- Phase 1 stores request metadata only; no prompts or completions.
- The live Supabase target is `fkvikwkmrlyhpjtaydln`; the checked-in project ID is obsolete and must not be used for deployment.

## Blockers

- Supabase CLI authentication is required before applying the migration, secrets, and Edge Function to the live project. The CLI is installed but has no access token on this machine.

## Session Log

### 2026-06-30

- Confirmed both provider credentials and model availability.
- Confirmed Langdock EU OpenAI-compatible chat-completions contract for Hermes text.
- Implemented the usage migration, typed gateway, guardrails, and provider failover.
- Passed five Deno unit tests and Deno type-check.
- Passed the existing Vite production build.
- Confirmed a real Langdock `gpt-5.4-mini` request returns HTTP 200.
