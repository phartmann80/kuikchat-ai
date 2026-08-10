# KuikChat AI Integration Research

## Overview

KuikChat will expose one server-side AI gateway for general assistance and later chat actions, document analysis, image generation, and asynchronous video generation.

## Recommended Approach

- Run provider calls in a Supabase Edge Function so provider credentials never enter the Vite bundle.
- Use Langdock's OpenAI-compatible EU endpoint as the Hermes text primary.
- Logicc is the approved secondary text provider and remains inactive until role and credentials are approved.
- Do not use third-party public model routers for KuikChat Hermes text.
- Authenticate every request with the caller's Supabase JWT.
- Reserve usage atomically in Postgres before calling a provider.
- Keep operational logs metadata-only. Conversation content is introduced only with the RLS-scoped history tables in Phase 2.

## Provider Contracts

- Langdock: `POST https://api.langdock.com/openai/eu/v1/chat/completions`, Bearer authentication, model `gpt-5.4-mini`.
- Logicc: OpenAI-compatible chat endpoint (exact base URL and model TBD when activated). Role: optional secondary Hermes text provider only after credential and product approval.

## Guardrails

- 30 requests per rolling hour and 100 requests per rolling day per authenticated user.
- Maximum 20 messages and 12,000 characters per request.
- Maximum 800 generated tokens and a 30-second provider timeout.
- Future document uploads: 15 MB per file, validated server-side before extraction.

## Risks and Mitigations

- Provider outage: Langdock primary with optional Logicc failover (disabled by default) and sanitized errors.
- Runaway cost: database-backed per-user reservations and output limits.
- Data leakage: server-only secrets, JWT verification, RLS, and metadata-only usage logs.
- Duplicate requests: unique request IDs in the usage ledger.

## References

- https://docs.langdock.com/api-endpoints/completion/openai
