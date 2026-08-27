# supabase-personal

Migrations and configuration for the **dedicated Personal Supabase project**.

This is NOT the prototype web project (`supabase/` at the repo root) and NOT
the future Business project (`supabase-business/`, does not exist yet).
Never apply these migrations to any other project, and never add Business
tables here — the environments are isolated by design (see
`docs/adr/ADR-001-personal-business-isolation.md`).

## Applying

```bash
# One-time: link this directory to the Personal project (dev or prod)
supabase link --project-ref <PERSONAL_PROJECT_REF> --workdir supabase-personal

# Apply migrations
supabase db push --workdir supabase-personal
```

## Rules

- RLS on every table; no exceptions.
- No public storage buckets.
- No service-role keys in any client or in this repository.
- Schema changes only via reviewed SQL migrations in `migrations/`.
