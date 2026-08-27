# KuikChat AI

KuikChat AI is a chat app prototype with AI features, auth, public pages, and Supabase functions. I built it to explore what a clean chat product could look like with login, protected chat, help pages, legal pages, and AI tools behind it.

Live site: [kuikchat-ai.vercel.app](https://kuikchat-ai.vercel.app)

## What it does

- Public landing, pricing, feature, security, help, status, and legal pages
- Supabase login and protected chat route
- Chat UI built with reusable shadcn/ui components
- Supabase functions for AI chat, image generation, translation, and voice transcription
- PWA assets and Vercel config
- Supabase migrations for app data

## Tech stack

- Vite, React, TypeScript
- Tailwind CSS, shadcn/ui, Radix UI
- Supabase client, migrations, and functions
- TanStack Query
- Framer Motion and Lucide React
- Vercel

## Run it locally

```bash
git clone https://github.com/janpaul80/kuikchat-ai.git
cd kuikchat-ai
npm install
npm run dev
```

Open the local URL printed by Vite.

## Environment

Create a local `.env` file:

```env
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
```

Put service role keys and provider secrets in Supabase or Vercel secrets. Do not expose them in browser variables.

## Useful scripts

```bash
npm run dev        # Start Vite
npm run build      # Build the app
npm run build:dev  # Build in development mode
npm run lint       # Run ESLint
npm run preview    # Preview the build
```

## Notes

- `src/pages/` has the app routes and public pages.
- `src/components/` has UI, auth, layout, and landing components.
- `src/contexts/` has auth state.
- `src/integrations/supabase/` has the Supabase client and types.
- `supabase/functions/` has AI, translation, and voice endpoints.

## Status

Prototype. It is a useful base for a polished chat product, but production use needs real provider secrets, Supabase policy review, and deployment checks.

## Repository layout (multi-platform)

The web prototype above is preserved unchanged. Production work toward the
Android app happens in additive directories:

- `mobile/` — Flutter Android client (Personal + Business environments,
  Material 3 dark theme). See `mobile/README.md`.
- `supabase-personal/` — migrations for the dedicated, isolated **Personal**
  Supabase project (RLS on every table, private storage only). This is a
  different project from the prototype's `supabase/`.
- `docs/adr/` — architecture decision records
  (start with `ADR-001-personal-business-isolation.md`).
- `docs/personal-backend-contract.md` — the Personal service contract used
  by the mobile client.
- `.github/workflows/` — CI for the web build and the Flutter
  analyze/test/build pipeline.

Personal and Business are isolated by design: separate backend projects,
separate repositories/interfaces in the client, separate navigation. Do not
join or share tables across environments.

