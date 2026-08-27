#!/usr/bin/env bash
# Architecture boundary guards for the Flutter client. Run from mobile/ (CI)
# or repo root. Fails the build when a layering rule is violated.
set -euo pipefail

cd "$(dirname "$0")/../mobile"

fail=0

echo "== Rule 1: no Supabase imports inside widgets (lib/features/) =="
if grep -rn "package:supabase" lib/features/ 2>/dev/null; then
  echo "VIOLATION: widgets must not import Supabase."
  fail=1
else
  echo "OK"
fi

echo "== Rule 2: no Supabase imports in domain layer (pure Dart) =="
if grep -rn "package:supabase\|package:flutter/" lib/domain/ 2>/dev/null; then
  echo "VIOLATION: domain layer must stay free of Flutter and backend SDKs."
  fail=1
else
  echo "OK"
fi

echo "== Rule 3: no Business imports inside Personal layers =="
if grep -rniE "^import .*business" lib/data/personal/ lib/domain/personal/ 2>/dev/null; then
  echo "VIOLATION: Personal services must not import Business code."
  fail=1
else
  echo "OK"
fi

echo "== Rule 4: no service-role keys or inline secrets =="
if grep -rniE "service_role|service-role-key|eyJhbGciOi" lib/ test/ 2>/dev/null; then
  echo "VIOLATION: possible secret or service-role usage in client code."
  fail=1
else
  echo "OK"
fi

echo "== Rule 5: backend endpoints only via --dart-define =="
if grep -rnE "https://[a-z0-9]+\.supabase\.co" lib/ test/ 2>/dev/null; then
  echo "VIOLATION: hardcoded Supabase project URL found."
  fail=1
else
  echo "OK"
fi

exit $fail
