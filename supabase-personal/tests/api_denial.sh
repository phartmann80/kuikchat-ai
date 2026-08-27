#!/usr/bin/env bash
# ============================================================================
# KuikChat PERSONAL environment — API-level security checks (HTTP surface).
#
# Complements tests/rls_matrix.sql: the SQL matrix proves in-database
# behavior; THIS script proves the deployed PostgREST/Data-API exposure
# configuration and storage authorization, which SQL alone cannot prove
# (Supabase can expose custom schemas through Data API settings).
#
# Required environment (via the approved secret channel — NEVER hardcoded,
# never in CI YAML, logs, commits, or PRs):
#   PERSONAL_DEV_URL            https://<project-ref>.supabase.co
#   PERSONAL_DEV_ANON_KEY       anon/publishable key ONLY
#   TEST_USER_EMAIL             dev test user A (member of the fixture
#   TEST_USER_PASSWORD            conversation and uploader of the fixture)
#   TEST_NONMEMBER_EMAIL        dev test user C (NOT a member of the fixture
#   TEST_NONMEMBER_PASSWORD       conversation)
#   TEST_MEDIA_OBJECT_PATH      existing object in bucket personal-media,
#                               e.g. <conversation-uuid>/<userA-uuid>/f.png
#
# Fixture setup (one-time, documented, deterministic):
#   1. As user A, open a conversation with user B (NOT with the non-member).
#   2. As user A, upload a small file:
#        POST $URL/storage/v1/object/personal-media/<conv>/<userA>/fixture.png
#      with user A's JWT.
#   3. Export its path as TEST_MEDIA_OBJECT_PATH.
# The script HARD-FAILS if the fixture is missing; a nonexistent path is
# never accepted as proof of storage privacy.
#
# Failure semantics:
#   - Transport/curl errors are reported as FAIL (transport), never as a
#     security pass.
#   - Exit 0 only when every check passed. Exit 2 on setup/fixture failure.
# Credentials and tokens are never printed.
# ============================================================================
set -u

# Explicit configuration enforcement: missing configuration is a SETUP
# failure -> exit 2 (never a security result).
for required_var in PERSONAL_DEV_URL PERSONAL_DEV_ANON_KEY \
    TEST_USER_EMAIL TEST_USER_PASSWORD \
    TEST_NONMEMBER_EMAIL TEST_NONMEMBER_PASSWORD TEST_MEDIA_OBJECT_PATH; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "FATAL: required environment variable $required_var is not set (see header for setup)."
    exit 2
  fi
done

BODY_FILE=$(mktemp) || exit 2
CURL_ERR_FILE=$(mktemp) || exit 2
trap 'rm -f "$BODY_FILE" "$CURL_ERR_FILE"' EXIT

fail=0
pass_count=0
REST="$PERSONAL_DEV_URL/rest/v1"
STORAGE="$PERSONAL_DEV_URL/storage/v1"
UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

http() { # method url token [extra curl args...] -> sets HTTP_STATUS, body in BODY_FILE
  local method="$1" url="$2" token="$3"; shift 3
  if ! HTTP_STATUS=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X "$method" "$url" \
    -H "apikey: $PERSONAL_DEV_ANON_KEY" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$@" 2>"$CURL_ERR_FILE"); then
    HTTP_STATUS="CURL_ERROR"
    return 1
  fi
  return 0
}

check() { # name expected-status-regex
  local name="$1" expected="$2"
  if [[ "$HTTP_STATUS" == "CURL_ERROR" ]]; then
    echo "FAIL  $name — TRANSPORT ERROR (not a security pass): $(head -c 200 "$CURL_ERR_FILE")"
    fail=1; return
  fi
  if [[ "$HTTP_STATUS" =~ ^($expected)$ ]]; then
    echo "PASS  $name (HTTP $HTTP_STATUS)"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL  $name — got HTTP $HTTP_STATUS, expected $expected"
    echo "      body: $(head -c 200 "$BODY_FILE")"
    fail=1
  fi
}

# Storage-list assertions fail CLOSED. Only documented authorization
# outcomes are accepted; a server error (5xx) or unexpected status is a
# FAILURE — it is never evidence that authorization works.
# Accepted denial statuses for the deployed Storage API:
STORAGE_DENIAL_STATUSES='400|401|403|404'

check_list_denied() { # name protected-object-name
  local name="$1" needle="$2"
  if [[ "$HTTP_STATUS" == "CURL_ERROR" ]]; then
    echo "FAIL  $name — TRANSPORT ERROR (not a security pass): $(head -c 200 "$CURL_ERR_FILE")"
    fail=1; return
  fi
  # Disclosure of the protected object is a HARD failure regardless of status.
  if grep -q -- "$needle" "$BODY_FILE"; then
    echo "FAIL  $name — HARD FAILURE: response (HTTP $HTTP_STATUS) discloses protected object"
    echo "      body: $(head -c 200 "$BODY_FILE")"
    fail=1; return
  fi
  if [[ "$HTTP_STATUS" == "200" ]]; then
    # 200 is acceptable only as a VALID, empty-of-fixture JSON list.
    if python3 -c 'import sys, json; d = json.load(sys.stdin); sys.exit(0 if isinstance(d, list) else 1)' <"$BODY_FILE" 2>/dev/null; then
      echo "PASS  $name (HTTP 200, valid list, object not disclosed)"
      pass_count=$((pass_count + 1))
    else
      echo "FAIL  $name — HTTP 200 but body is not a valid JSON list"
      echo "      body: $(head -c 200 "$BODY_FILE")"
      fail=1
    fi
  elif [[ "$HTTP_STATUS" =~ ^($STORAGE_DENIAL_STATUSES)$ ]]; then
    echo "PASS  $name (HTTP $HTTP_STATUS denial, object not disclosed)"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL  $name — unexpected HTTP $HTTP_STATUS (5xx/other is not authorization evidence)"
    echo "      body: $(head -c 200 "$BODY_FILE")"
    fail=1
  fi
}

json_field() { # stdin: json; $1: python expression on dict d
  python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = $1
    print(v if v else '')
except Exception:
    print('')"
}

login() { # $1 email  $2 password -> sets LOGIN_JWT, LOGIN_UID; exits on failure
  local resp
  if ! resp=$(curl -sS -X POST "$PERSONAL_DEV_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $PERSONAL_DEV_ANON_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" 2>"$CURL_ERR_FILE"); then
    echo "FATAL: transport error during sign-in: $(head -c 200 "$CURL_ERR_FILE")"
    exit 2
  fi
  LOGIN_JWT=$(printf '%s' "$resp" | json_field "d.get('access_token')")
  LOGIN_UID=$(printf '%s' "$resp" | json_field "(d.get('user') or {}).get('id')")
  if [[ -z "$LOGIN_JWT" || ! "$LOGIN_UID" =~ $UUID_RE ]]; then
    # Print only the server's error description — never the raw response,
    # which could contain tokens.
    local err
    err=$(printf '%s' "$resp" | json_field "d.get('error_description') or d.get('msg') or d.get('error')")
    echo "FATAL: sign-in failed or user id unparseable for $1: ${err:-unparseable auth response}"
    echo "       The script refuses to continue with an invalid identity."
    exit 2
  fi
}

redact() { printf '%s…' "${1:0:8}"; }

echo "== Signing in test identities (credentials/tokens are never printed) =="
login "$TEST_USER_EMAIL" "$TEST_USER_PASSWORD"
USER_JWT="$LOGIN_JWT"; USER_ID="$LOGIN_UID"
echo "OK    member user       id=$(redact "$USER_ID")"
login "$TEST_NONMEMBER_EMAIL" "$TEST_NONMEMBER_PASSWORD"
NM_JWT="$LOGIN_JWT"; NM_ID="$LOGIN_UID"
echo "OK    non-member user   id=$(redact "$NM_ID")"
if [[ "$USER_ID" == "$NM_ID" ]]; then
  echo "FATAL: member and non-member test users must be different accounts."
  exit 2
fi
ANON="$PERSONAL_DEV_ANON_KEY"

echo
echo "== 1. Private helper RPCs must NOT exist on the API surface =="
http POST "$REST/rpc/is_blocked_between" "$ANON" -d "{\"a\":\"$USER_ID\",\"b\":\"$NM_ID\"}"
check "anon  -> rpc/is_blocked_between unavailable" "404"
http POST "$REST/rpc/is_conversation_member" "$ANON" -d "{\"conv\":\"$USER_ID\",\"member\":\"$USER_ID\"}"
check "anon  -> rpc/is_conversation_member unavailable" "404"
http POST "$REST/rpc/is_blocked_between" "$USER_JWT" -d "{\"a\":\"$USER_ID\",\"b\":\"$NM_ID\"}"
check "auth  -> rpc/is_blocked_between unavailable" "404"
http POST "$REST/rpc/is_conversation_member" "$USER_JWT" -d "{\"conv\":\"$USER_ID\",\"member\":\"$USER_ID\"}"
check "auth  -> rpc/is_conversation_member unavailable" "404"

echo
echo "== 2. private schema must not be selectable as an API profile =="
http GET "$REST/profiles?select=user_id" "$ANON" -H "Accept-Profile: private"
check "anon  -> Accept-Profile: private rejected" "406"
http GET "$REST/profiles?select=user_id" "$USER_JWT" -H "Accept-Profile: private"
check "auth  -> Accept-Profile: private rejected" "406"
http POST "$REST/rpc/is_conversation_member" "$USER_JWT" -H "Content-Profile: private" -d '{}'
check "auth  -> Content-Profile: private rejected" "406"

echo
echo "== 3. Restricted public RPCs deny anonymous callers =="
http POST "$REST/rpc/list_conversations" "$ANON" -d '{}'
check "anon  -> rpc/list_conversations denied" "401|403|404"
http POST "$REST/rpc/find_profile_by_email" "$ANON" -d '{"lookup_email":"nobody@example.com"}'
check "anon  -> rpc/find_profile_by_email denied" "401|403|404"
http POST "$REST/rpc/open_direct_conversation" "$ANON" -d "{\"other_user\":\"$USER_ID\"}"
check "anon  -> rpc/open_direct_conversation denied" "401|403|404"

echo
echo "== 4. Unauthenticated table access yields zero data =="
http GET "$REST/messages?select=id&limit=5" "$ANON"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
  echo "PASS  anon  -> messages returns empty set (HTTP 200, [])"; pass_count=$((pass_count+1))
else
  echo "FAIL  anon  -> messages — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi
http GET "$REST/profiles?select=user_id&limit=5" "$ANON"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
  echo "PASS  anon  -> profiles returns empty set (HTTP 200, [])"; pass_count=$((pass_count+1))
else
  echo "FAIL  anon  -> profiles — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi

echo
echo "== 5. Device sessions: real-UUID ownership checks =="
# 5a. UUID filter itself must be accepted by PostgREST (200, not 400).
http GET "$REST/device_sessions?select=id&user_id=eq.$USER_ID" "$USER_JWT"
check "auth  -> uuid filter user_id=eq.<own-uuid> accepted" "200"
# 5b. Create an own session row, prove the owner can read it back.
http POST "$REST/device_sessions" "$USER_JWT" \
  -H "Prefer: return=representation" \
  -d "{\"user_id\":\"$USER_ID\",\"device_name\":\"api-denial-check\",\"platform\":\"android\"}"
check "auth  -> owner can create own device session" "201"
SESSION_ID=$(cat "$BODY_FILE" | json_field "(d[0] if isinstance(d, list) and d else {}).get('id')")
http GET "$REST/device_sessions?select=id&user_id=eq.$USER_ID&device_name=eq.api-denial-check" "$USER_JWT"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" != "[]" ]]; then
  echo "PASS  auth  -> owner reads own session when one exists (HTTP 200, non-empty)"; pass_count=$((pass_count+1))
else
  echo "FAIL  auth  -> owner cannot read own session — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi
# 5c. Foreign sessions with the REAL authenticated uuid: must be empty.
http GET "$REST/device_sessions?select=user_id&user_id=neq.$USER_ID" "$USER_JWT"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
  echo "PASS  auth  -> foreign sessions (user_id=neq.$(redact "$USER_ID")) empty"; pass_count=$((pass_count+1))
else
  echo "FAIL  auth  -> foreign sessions leak — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi
# 5d. The other authenticated account must not see A's session.
http GET "$REST/device_sessions?select=user_id&user_id=eq.$USER_ID" "$NM_JWT"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
  echo "PASS  auth  -> another user cannot read A's device session (empty set)"; pass_count=$((pass_count+1))
else
  echo "FAIL  auth  -> cross-user session read — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi
# Cleanup (non-blocking: failures are WARNED, never silent, and never count
# as a security pass). SESSION_ID must be a valid UUID before the delete
# request is constructed; transport and HTTP failures are reported
# separately; tokens/raw responses are never printed; temp files remain
# owned by the EXIT trap.
if [[ "$SESSION_ID" =~ $UUID_RE ]]; then
  if ! http DELETE "$REST/device_sessions?id=eq.$SESSION_ID" "$USER_JWT"; then
    echo "WARN  cleanup request failed (transport): $(head -c 200 "$CURL_ERR_FILE")"
  elif [[ ! "$HTTP_STATUS" =~ ^20(0|4)$ ]]; then
    echo "WARN  cleanup returned HTTP $HTTP_STATUS"
  fi
  # Regression: the generated test session must be gone, or its survival
  # must be explicitly reported.
  if http GET "$REST/device_sessions?select=id&id=eq.$SESSION_ID" "$USER_JWT" \
     && [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
    echo "PASS  cleanup verified: test session removed"
    pass_count=$((pass_count + 1))
  else
    echo "WARN  cleanup NOT verified — test session may remain (HTTP $HTTP_STATUS)."
    echo "      Remove manually: device_sessions id=$SESSION_ID"
  fi
else
  echo "WARN  no valid session id captured; delete skipped (creation may have failed above)"
fi

echo
echo "== 6. Cross-user profile access (no shared conversation) =="
http GET "$REST/profiles?select=user_id&user_id=eq.$USER_ID" "$NM_JWT"
if [[ "$HTTP_STATUS" == "200" && "$(cat "$BODY_FILE")" == "[]" ]]; then
  echo "PASS  auth  -> stranger cannot read A's profile (empty set)"; pass_count=$((pass_count+1))
else
  echo "FAIL  auth  -> stranger profile read — HTTP $HTTP_STATUS body $(head -c 120 "$BODY_FILE")"; fail=1
fi

echo
echo "== 7. Storage: fixture-based read/list authorization =="
OBJECT_PREFIX=$(dirname "$TEST_MEDIA_OBJECT_PATH")
OBJECT_NAME=$(basename "$TEST_MEDIA_OBJECT_PATH")
# 7a. Fixture must exist: authorized member read must succeed. HARD gate —
#     a nonexistent path proves nothing about privacy.
http GET "$STORAGE/object/personal-media/$TEST_MEDIA_OBJECT_PATH" "$USER_JWT"
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "PASS  auth member -> fixture object readable (HTTP 200)"; pass_count=$((pass_count+1))
else
  echo "FATAL fixture missing or unreadable by its owner (HTTP $HTTP_STATUS)."
  echo "      Create it per the header instructions, then re-run."
  echo "      body: $(head -c 200 "$BODY_FILE")"
  exit 2
fi
# 7b. Authorized member list must contain the fixture (validates the list
#     endpoint + fixture together).
http POST "$STORAGE/object/list/personal-media" "$USER_JWT" \
  -d "{\"prefix\":\"$OBJECT_PREFIX\",\"limit\":100}"
if [[ "$HTTP_STATUS" == "200" ]] && grep -q -- "$OBJECT_NAME" "$BODY_FILE"; then
  echo "PASS  auth member -> list shows fixture (HTTP 200)"; pass_count=$((pass_count+1))
else
  echo "FAIL  auth member -> list does not show fixture — HTTP $HTTP_STATUS body $(head -c 200 "$BODY_FILE")"; fail=1
fi
# 7c. Anonymous read of the KNOWN object must not return it.
http GET "$STORAGE/object/personal-media/$TEST_MEDIA_OBJECT_PATH" "$ANON"
check "anon  -> known private object read denied" "400|401|403|404"
echo "      recorded: HTTP $HTTP_STATUS, body: $(head -c 160 "$BODY_FILE")"
# 7d. Anonymous list of the KNOWN prefix must not disclose the object.
#     Fail-closed: only 200-with-valid-empty-list or documented 4xx denials
#     are accepted; 5xx or disclosure is a failure.
http POST "$STORAGE/object/list/personal-media" "$ANON" \
  -d "{\"prefix\":\"$OBJECT_PREFIX\",\"limit\":100}"
check_list_denied "anon  -> list of known prefix denied without disclosure" "$OBJECT_NAME"
# 7e. Authenticated NON-MEMBER read of the known object must not return it.
http GET "$STORAGE/object/personal-media/$TEST_MEDIA_OBJECT_PATH" "$NM_JWT"
check "auth non-member -> known private object read denied" "400|401|403|404"
echo "      recorded: HTTP $HTTP_STATUS, body: $(head -c 160 "$BODY_FILE")"
# 7f. Authenticated NON-MEMBER list must not disclose the object.
http POST "$STORAGE/object/list/personal-media" "$NM_JWT" \
  -d "{\"prefix\":\"$OBJECT_PREFIX\",\"limit\":100}"
check_list_denied "auth non-member -> list denied without disclosure" "$OBJECT_NAME"

echo
echo "== Evidence reminders (manual, attach to validation report) =="
echo "  * Data API exposed schemas (Dashboard -> Settings -> Data API):"
echo "    record the actual deployed list; it must contain 'public' and"
echo "    must NOT contain 'private'."
echo "  * Storage fixture path used: personal-media/$TEST_MEDIA_OBJECT_PATH"
echo "  * Test user (redacted): $(redact "$USER_ID") / non-member: $(redact "$NM_ID")"

echo
if [[ $fail -eq 0 ]]; then
  echo "ALL API DENIAL CHECKS PASSED ($pass_count checks)"
else
  echo "API DENIAL CHECKS FAILED ($pass_count passed) — DO NOT PROCEED."
fi
exit $fail
