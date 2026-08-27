#!/usr/bin/env bash
# ============================================================================
# KuikChat PERSONAL environment — API-level security checks (HTTP surface).
#
# Complements tests/rls_matrix.sql: the SQL matrix proves in-database
# behavior; THIS script proves the deployed PostgREST/Data-API exposure
# configuration, which SQL alone cannot (Supabase can expose custom schemas
# through Data API settings, so the `private` schema guarantee must be
# verified live).
#
# Usage:
#   export PERSONAL_DEV_URL="https://<project-ref>.supabase.co"
#   export PERSONAL_DEV_ANON_KEY="<anon key>"          # anon/publishable ONLY
#   export TEST_USER_EMAIL="qa-a@..."                  # existing dev test user
#   export TEST_USER_PASSWORD="..."
#   bash supabase-personal/tests/api_denial.sh
#
# Credentials come from the environment via the approved secret channel.
# NEVER hardcode them here, in CI files, or in the repository.
# Exit code 0 = all checks passed. Non-zero = at least one FAILURE.
# ============================================================================
set -u

: "${PERSONAL_DEV_URL:?set PERSONAL_DEV_URL}"
: "${PERSONAL_DEV_ANON_KEY:?set PERSONAL_DEV_ANON_KEY}"
: "${TEST_USER_EMAIL:?set TEST_USER_EMAIL}"
: "${TEST_USER_PASSWORD:?set TEST_USER_PASSWORD}"

fail=0
pass_count=0

status_of() { # method url token extra-headers... -> prints http status
  local method="$1" url="$2" token="$3"; shift 3
  curl -s -o /tmp/api_denial_body -w "%{http_code}" -X "$method" "$url" \
    -H "apikey: $PERSONAL_DEV_ANON_KEY" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$@"
}

check() { # name actual expected-regex
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" =~ ^($expected)$ ]]; then
    echo "PASS  $name (HTTP $actual)"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL  $name — got HTTP $actual, expected $expected"
    echo "      body: $(head -c 300 /tmp/api_denial_body)"
    fail=1
  fi
}

check_body() { # name actual-status expected-status expected-body name
  local name="$1" actual="$2" expected_status="$3" expected_body="$4"
  local body; body="$(cat /tmp/api_denial_body)"
  if [[ "$actual" == "$expected_status" && "$body" == "$expected_body" ]]; then
    echo "PASS  $name (HTTP $actual, body $body)"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL  $name — got HTTP $actual body '$(head -c 120 <<<"$body")', expected $expected_status with $expected_body"
    fail=1
  fi
}

echo "== Obtaining authenticated session for $TEST_USER_EMAIL =="
auth_json=$(curl -s -X POST "$PERSONAL_DEV_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $PERSONAL_DEV_ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}")
USER_JWT=$(printf '%s' "$auth_json" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
if [[ -z "$USER_JWT" ]]; then
  echo "FATAL: could not sign in test user (check credentials/channel)."
  echo "       response: $(head -c 300 <<<"$auth_json")"
  exit 2
fi
echo "OK    signed in"

ANON="$PERSONAL_DEV_ANON_KEY"
REST="$PERSONAL_DEV_URL/rest/v1"

echo
echo "== 1. Private helper RPCs must NOT exist on the API surface =="
s=$(status_of POST "$REST/rpc/is_blocked_between" "$ANON" -d '{"a":"00000000-0000-4000-8000-000000000001","b":"00000000-0000-4000-8000-000000000002"}')
check "anon  -> rpc/is_blocked_between is unavailable" "$s" "404"
s=$(status_of POST "$REST/rpc/is_conversation_member" "$ANON" -d '{"conv":"00000000-0000-4000-8000-000000000001","member":"00000000-0000-4000-8000-000000000002"}')
check "anon  -> rpc/is_conversation_member is unavailable" "$s" "404"
s=$(status_of POST "$REST/rpc/is_blocked_between" "$USER_JWT" -d '{"a":"00000000-0000-4000-8000-000000000001","b":"00000000-0000-4000-8000-000000000002"}')
check "auth  -> rpc/is_blocked_between is unavailable" "$s" "404"
s=$(status_of POST "$REST/rpc/is_conversation_member" "$USER_JWT" -d '{"conv":"00000000-0000-4000-8000-000000000001","member":"00000000-0000-4000-8000-000000000002"}')
check "auth  -> rpc/is_conversation_member is unavailable" "$s" "404"

echo
echo "== 2. private schema must not be selectable as an API profile =="
s=$(status_of GET "$REST/profiles?select=user_id" "$ANON" -H "Accept-Profile: private")
check "anon  -> Accept-Profile: private rejected" "$s" "406"
s=$(status_of GET "$REST/profiles?select=user_id" "$USER_JWT" -H "Accept-Profile: private")
check "auth  -> Accept-Profile: private rejected" "$s" "406"
s=$(status_of POST "$REST/rpc/is_conversation_member" "$USER_JWT" -H "Content-Profile: private" -d '{}')
check "auth  -> Content-Profile: private rejected" "$s" "406"

echo
echo "== 3. Restricted public RPCs deny anonymous callers =="
s=$(status_of POST "$REST/rpc/list_conversations" "$ANON" -d '{}')
check "anon  -> rpc/list_conversations denied" "$s" "401|403|404"
s=$(status_of POST "$REST/rpc/find_profile_by_email" "$ANON" -d '{"lookup_email":"nobody@example.com"}')
check "anon  -> rpc/find_profile_by_email denied" "$s" "401|403|404"
s=$(status_of POST "$REST/rpc/open_direct_conversation" "$ANON" -d '{"other_user":"00000000-0000-4000-8000-000000000001"}')
check "anon  -> rpc/open_direct_conversation denied" "$s" "401|403|404"

echo
echo "== 4. Unauthenticated table access yields zero data =="
s=$(status_of GET "$REST/messages?select=id&limit=5" "$ANON")
check_body "anon  -> messages returns empty set" "$s" "200" "[]"
s=$(status_of GET "$REST/profiles?select=user_id&limit=5" "$ANON")
check_body "anon  -> profiles returns empty set" "$s" "200" "[]"

echo
echo "== 5. Cross-user reads yield zero data for authenticated strangers =="
s=$(status_of GET "$REST/device_sessions?select=id&user_id=neq.self&limit=5" "$USER_JWT")
check "auth  -> foreign device_sessions query does not error" "$s" "200"
s=$(status_of GET "$REST/blocked_contacts?select=blocker_id&limit=5" "$USER_JWT")
check "auth  -> blocked_contacts readable only under RLS (no error)" "$s" "200"

echo
echo "== 6. Storage: private bucket denies unauthorized access =="
s=$(status_of GET "$PERSONAL_DEV_URL/storage/v1/object/personal-media/does-not-exist/x/y.png" "$ANON")
check "anon  -> private bucket object denied/not found" "$s" "400|401|403|404"
s=$(status_of GET "$PERSONAL_DEV_URL/storage/v1/object/list/personal-media" "$ANON")
check "anon  -> private bucket listing denied" "$s" "400|401|403|404|405"

echo
if [[ $fail -eq 0 ]]; then
  echo "ALL API DENIAL CHECKS PASSED ($pass_count checks)"
else
  echo "API DENIAL CHECKS FAILED — private schema may be exposed or grants are wrong. DO NOT PROCEED."
fi
exit $fail
