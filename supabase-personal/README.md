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

## Data API exposure configuration (release gate)

The security of the `private` authorization helpers depends on the deployed
PostgREST configuration, not only on the schema name. Supabase can expose
custom schemas through the Data API, so this MUST be verified per project:

- Dashboard → Project Settings → Data API → **Exposed schemas** must contain
  ONLY `public` (plus Supabase's managed `graphql_public` if enabled).
  `private` must NEVER be added.
- **Extra search path** must NOT include `private`.
- Verify live with the API-level negative tests:

```bash
export PERSONAL_DEV_URL=...            # via approved secret channel
export PERSONAL_DEV_ANON_KEY=...       # anon key only
export TEST_USER_EMAIL=... TEST_USER_PASSWORD=...
bash tests/api_denial.sh               # must end: ALL API DENIAL CHECKS PASSED
```

Release gate: `private schema is not exposed through the Personal Data API`.
Re-verify after ANY change to Data API settings and before every production
promotion.

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
