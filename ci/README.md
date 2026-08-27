# CI workflow definitions

These GitHub Actions workflows could not be pushed into `.github/workflows/`
by the automation account (it lacks the `workflows` permission). A maintainer
with workflow permission should move them into place:

```bash
mkdir -p .github/workflows
git mv ci/mobile-ci.yml ci/web-ci.yml .github/workflows/
git commit -m "Enable CI workflows"
```

- `mobile-ci.yml` — Flutter (pinned 3.47.2): boundary checks, shell lint
  (bash -n + ShellCheck, merge-blocking), pub get,
  lockfile drift guard + artifact, analyze, tests, debug APK; plus SQL
  migration validation (libpg_query, pinned 17.7.4) and secret scanning
  (gitleaks) jobs.
- `web-ci.yml` — Web: npm ci + vite build.

## Supply-chain pinning policy

- All third-party actions are pinned to immutable commit SHAs (the tag they
  correspond to is kept as a trailing comment).
- The SQL validation dependency `libpg-query` is pinned to an exact version.
- ShellCheck: the shell-lint job currently uses the runner-provided
  ShellCheck on `ubuntu-latest` and prints its version as the first command
  (the CI-printed version is the authoritative evidence). This is a
  documented runner-version dependency requiring explicit approval before
  final merge; the alternative is pinning a checksum-verified ShellCheck
  release binary in the workflow — the maintainer enabling CI should record
  which option is approved. Local preparation runs used ShellCheck 0.11.0.
- Update process: a PR that (1) bumps the SHA/version, (2) states the tag it
  maps to and links the upstream release notes, and (3) is reviewed by the
  security workstream (Developer D). Never update a pin by editing a
  workflow in the GitHub UI.

