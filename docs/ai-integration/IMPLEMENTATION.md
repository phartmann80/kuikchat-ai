# KuikChat AI Integration Implementation Plan

## Phase Summary

1. Edge gateway, provider failover, rate limiting, and metadata logging.
2. General assistant, language detection, and per-user conversation history.
3. In-chat draft, refine, summarize, and translate actions.
4. Server-side document extraction and analysis.
5. Synchronous image generation.
6. Asynchronous video/Hyperframes jobs.

## Phase 1: Gateway and Failover

### Tasks

- [x] Confirm live provider endpoints, authentication, and model identifiers.
- [x] Add the RLS-protected usage ledger and atomic reservation function.
- [x] Implement the authenticated Edge Function gateway.
- [x] Add typed Langdock provider (Logicc optional, disabled by default).
- [x] Remove non-approved third-party router dependencies from gateway boot.
- [x] Add request/token/rate guardrails and sanitized errors.
- [x] Test primary success and fallback behavior locally.
- [ ] Deploy to the live Supabase project and prove both paths.

### Success Criteria

- A trivial authenticated text call succeeds through Langdock.
- Disabling Langdock returns a normalized gateway error unless Logicc fallback is explicitly enabled and configured.
- Both requests are recorded without prompt or completion content.
- Over-limit and unauthenticated requests are rejected server-side.

## Phase 2: General Assistant

Begins only after Phase 1 review approval. It adds the dark-themed UI, language detection, conversation/message tables, history, and per-user isolation tests.
