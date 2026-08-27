#!/usr/bin/env bash
# ============================================================================
# Self-test harness for api_denial.sh.
#
# Runs the security-gate script against a local mock of the Supabase HTTP
# surface (selftest/mock_api.py) and asserts the REQUIRED failure semantics:
#
#   Missing configuration       -> exit 2
#   Invalid identity            -> exit 2
#   Transport failure           -> exit 2 (during sign-in)
#   Missing fixture             -> exit 2
#   Owner cannot read fixture   -> exit 2 (distinct from missing fixture)
#   Protected object disclosed  -> failure (exit 1, HARD FAILURE)
#   Unexpected 5xx              -> failure (exit 1)
#   Successful denial           -> pass   (exit 0)
#   Cleanup failure             -> warning, never silent (exit 0 + WARN)
#
# This proves the SCRIPT fails closed. It does NOT replace running
# api_denial.sh against the real kuikchat-personal-dev project.
#
# Usage: bash supabase-personal/tests/run_selftest.sh
# ============================================================================
set -u
cd "$(dirname "$0")" || exit 2

BASE_PORT="${MOCK_BASE_PORT:-8971}"
failures=0
scenario_index=0
scenarios_run=0

run_case() { # scenario expected_exit required_pattern [forbidden_pattern]
  local scenario="$1" expected="$2" pattern="$3" forbidden="${4:-}"
  scenario_index=$((scenario_index + 1))
  scenarios_run=$((scenarios_run + 1))
  local port=$((BASE_PORT + scenario_index))

  MOCK_SCENARIO="$scenario" python3 selftest/mock_api.py "$port" &
  local server_pid=$!
  sleep 0.5

  local out rc
  out=$(PERSONAL_DEV_URL="http://127.0.0.1:$port" \
        PERSONAL_DEV_ANON_KEY="anon-key-mock" \
        TEST_USER_EMAIL="a@selftest.local" TEST_USER_PASSWORD="mock-only" \
        TEST_NONMEMBER_EMAIL="c@selftest.local" TEST_NONMEMBER_PASSWORD="mock-only" \
        TEST_MEDIA_OBJECT_PATH="conv1/user-a/fixture.png" \
        bash ./api_denial.sh 2>&1)
  rc=$?

  kill "$server_pid" 2>/dev/null
  wait "$server_pid" 2>/dev/null

  local ok=1
  [[ $rc -eq $expected ]] || { echo "  ! exit code $rc, expected $expected"; ok=0; }
  grep -q "$pattern" <<<"$out" || { echo "  ! missing required output: $pattern"; ok=0; }
  if [[ -n "$forbidden" ]] && grep -q "$forbidden" <<<"$out"; then
    echo "  ! forbidden output present: $forbidden"; ok=0
  fi
  if grep -q "mock-only\|anon-key-mock\|tok-a\|tok-c" <<<"$out"; then
    echo "  ! CREDENTIAL/TOKEN LEAK in output"; ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    echo "PASS  scenario '$scenario' (exit $rc)"
  else
    echo "FAIL  scenario '$scenario'"
    echo "$out" | tail -6 | sed 's/^/      | /'
    failures=$((failures + 1))
  fi
}

echo "== 1. Missing required environment variable -> setup failure, exit 2 =="
scenarios_run=$((scenarios_run + 1))
out=$(bash ./api_denial.sh 2>&1); rc=$?
if [[ $rc -eq 2 ]] && grep -q "required environment variable" <<<"$out"; then
  echo "PASS  missing configuration aborts (exit 2)"
else
  echo "FAIL  missing configuration handling (exit $rc)"; failures=$((failures + 1))
fi

echo "== 2. Unreachable host -> transport FATAL, exit 2, no credential output =="
scenarios_run=$((scenarios_run + 1))
out=$(PERSONAL_DEV_URL="https://unreachable.invalid" PERSONAL_DEV_ANON_KEY="anon-key-mock" \
      TEST_USER_EMAIL="a@selftest.local" TEST_USER_PASSWORD="mock-only" \
      TEST_NONMEMBER_EMAIL="c@selftest.local" TEST_NONMEMBER_PASSWORD="mock-only" \
      TEST_MEDIA_OBJECT_PATH="conv1/user-a/fixture.png" bash ./api_denial.sh 2>&1); rc=$?
if [[ $rc -eq 2 ]] && grep -q "transport error" <<<"$out" && ! grep -q "mock-only" <<<"$out"; then
  echo "PASS  unreachable host (exit 2, transport reported, no leak)"
else
  echo "FAIL  unreachable host handling (exit $rc)"; failures=$((failures + 1))
fi

echo "== 3. Mock-server scenarios =="
run_case ok              0 "ALL API DENIAL CHECKS PASSED" "WARN"
run_case bad_json        2 "unparseable auth response"
run_case bad_uuid        2 "user id unparseable"
# Distinct fixture failures: missing object (404) vs. existing object the
# owner cannot read (403). Both are setup failures, never security passes.
run_case fixture_missing 2 "unreadable by its owner (HTTP 404)"
run_case owner_forbidden 2 "unreadable by its owner (HTTP 403)"
run_case list_500        1 "unexpected HTTP 500"
run_case leak            1 "discloses protected object"
run_case cleanup_500     0 "WARN  cleanup returned HTTP 500"

echo
if [[ $failures -eq 0 ]]; then
  echo "SELFTEST PASSED ($scenarios_run scenarios)"
  exit 0
fi
echo "SELFTEST FAILED ($failures of $scenarios_run scenario(s))"
exit 1
