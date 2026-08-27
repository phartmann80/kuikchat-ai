# supabase-personal

Migrations and configuration for the **dedicated Personal Supabase project**.

This is NOT the prototype web project (`supabase/` at the repo root) and NOT
the future Business project (`supabase-business/`, does not exist yet).
Never apply these migrations to any other project, and never add Business
tables here — the environments are isolated by design (see
`docs/adr/ADR-001-personal-business-isolation.md`).

## Applying

Provision **development first** (`kuikchat-personal-dev`). Production must
not be provisioned until the dev migration and the RLS matrix pass.

```bash
# One-time: link this directory to the Personal DEV project
supabase link --project-ref <PERSONAL_DEV_PROJECT_REF> --workdir supabase-personal

# Apply migrations
supabase db push --workdir supabase-personal

# Run the authorization test matrix (self-cleaning; rolls back)
psql "$PERSONAL_DEV_DB_URL" -f tests/rls_matrix.sql
```

The matrix (`tests/rls_matrix.sql`) covers: own-record access, cross-user
denial, shared vs non-member conversations, block enforcement, anonymous
RPC denial, storage path authorization, message immutability, soft delete,
read states, reactions, attachments, and device sessions. It raises an
exception if any check fails.

## Rules

- RLS on every table; no exceptions.
- No public storage buckets.
- No service-role keys in any client or in this repository.
- Schema changes only via reviewed SQL migrations in `migrations/`.
- Internal authorization helpers live in the non-exposed `private` schema
  (`private.is_blocked_between`, `private.is_conversation_member`); never
  create authorization helpers in `public`, and never grant `anon` access
  to `private`.
- Every SECURITY DEFINER function pins `search_path = public, pg_temp` and
  uses schema-qualified references.
