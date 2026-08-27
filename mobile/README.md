# KuikChat Mobile (Flutter, Android)

The Android client for KuikChat: one app containing two isolated
environments — **Personal** and **Business** — with separate navigation
models and separate backend boundaries.

Status: Milestone 1 (foundation + Personal messaging vertical slice).
The Business environment has real, separate navigation but no backend yet;
its screens state that honestly.

## Requirements

- Flutter stable (3.24+; developed against current stable)
- Android SDK (API 34+ installed), a device or emulator
- A provisioned Personal Supabase project
  (`supabase-personal/migrations/` applied)

## Running

Backend endpoints are injected at build time. Nothing is read from committed
files and no secrets live in this repository.

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run \
  --dart-define=PERSONAL_SUPABASE_URL=https://<personal-project>.supabase.co \
  --dart-define=PERSONAL_SUPABASE_ANON_KEY=<personal-anon-key>
```

Only the **anon (publishable)** key is ever passed to the client. Data
access is enforced by RLS server-side. Service-role keys must never appear
in this app, in dart-defines, or in CI logs.

Running without the dart-defines is supported: the app boots into an
explicit "Personal backend not configured" screen instead of faking a
working state.

## Architecture

```
Flutter UI (features/)            widgets only, no backend imports
  -> State management (state/)    Riverpod controllers, view state machines
    -> Domain (domain/)           entities + use-cases, pure Dart
      -> Repository interfaces    (domain/*/repositories)
        -> Personal service impl  (data/personal, Supabase)
```

Rules enforced by this layering:

- No Supabase calls inside widgets. Widgets read providers only.
- Personal and Business repositories can never be mixed: Business will get
  its own interfaces, providers, and client (separate Supabase project).
- Tests replace repositories with controlled fakes (`test/fakes/`).
- Future WebRTC / Hermes / Stripe / media integrations arrive as independent
  modules behind their own interfaces.

## UI conventions

- Material 3, full dark theme, KuikChat blue (#3B82F6) / green (#22C55E).
- Lucide icons only (`lucide_icons`); no emoji-style UI icons.
- Responsive: bottom navigation on phones, navigation rail from 840 dp.
- Every screen implements loading / empty / error / offline / retry states.
  No placeholder conversations or fake data anywhere.

## Tests

```bash
flutter test
```

Covers: chat state machine (sending → sent, failed → retry with idempotent
client id, realtime reconciliation without duplicates), send-message use
case validation, conversation list states, shell navigation separation
(Personal vs Business), and theme/brand assertions.
