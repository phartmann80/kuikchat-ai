# CI workflow definitions

These GitHub Actions workflows could not be pushed into `.github/workflows/`
by the automation account (it lacks the `workflows` permission). A maintainer
with workflow permission should move them into place:

```bash
mkdir -p .github/workflows
git mv ci/mobile-ci.yml ci/web-ci.yml .github/workflows/
git commit -m "Enable CI workflows"
```

- `mobile-ci.yml` — Flutter (pinned 3.47.2): boundary checks, pub get,
  lockfile drift guard + artifact, analyze, tests, debug APK; plus SQL
  migration validation (libpg_query) and secret scanning (gitleaks) jobs.
- `web-ci.yml` — Web: npm ci + vite build.
