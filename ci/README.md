# CI workflow definitions

These GitHub Actions workflows could not be pushed into `.github/workflows/`
by the automation account (it lacks the `workflows` permission). A maintainer
with workflow permission should move them into place:

```bash
mkdir -p .github/workflows
git mv ci/mobile-ci.yml ci/web-ci.yml .github/workflows/
git commit -m "Enable CI workflows"
```

- `mobile-ci.yml` — Flutter: pub get, analyze, test, debug APK artifact.
- `web-ci.yml` — Web: npm ci + vite build.
