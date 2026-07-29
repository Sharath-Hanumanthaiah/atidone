#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
COOKIE_JAR="/tmp/mock_data_filtering_in_e2e_mode_cookie_${CASE_SUFFIX}.txt"
SESSION_HEADERS="/tmp/mock_data_filtering_in_e2e_mode_session_headers_${CASE_SUFFIX}.txt"
SESSION_BODY="/tmp/mock_data_filtering_in_e2e_mode_session_body_${CASE_SUFFIX}.txt"
RESPONSE_HEADERS="/tmp/mock_data_filtering_in_e2e_mode_response_headers_${CASE_SUFFIX}.txt"
RESPONSE_BODY="/tmp/mock_data_filtering_in_e2e_mode_response_body_${CASE_SUFFIX}.txt"
CLEAR_HEADERS="/tmp/mock_data_filtering_in_e2e_mode_clear_headers_${CASE_SUFFIX}.txt"
CLEAR_BODY="/tmp/mock_data_filtering_in_e2e_mode_clear_body_${CASE_SUFFIX}.txt"
MOCK_TODOS="$(cat <<JSON
[{"id":"mock-1-${CASE_SUFFIX}","userId":"777","title":"Test todo"},{"id":"mock-2-${CASE_SUFFIX}","userId":"888","title":"Other todo"},{"id":"mock-3-${CASE_SUFFIX}","title":"Global todo"}]
JSON
)"
ENCODED_MOCK_TODOS="$(printf '%s' "$MOCK_TODOS" | jq -sRr @uri)"

cleanup_files() {
  rm -f "$COOKIE_JAR" "$SESSION_HEADERS" "$SESSION_BODY" "$RESPONSE_HEADERS" "$RESPONSE_BODY" "$CLEAR_HEADERS" "$CLEAR_BODY"
}

cleanup_session() {
  if [ -f "$COOKIE_JAR" ]; then
    echo "STEP: Cleanup — clear the authenticated test session"
    echo "REQUEST_HEADERS:"
    echo "Content-Type: application/json"
    echo "REQUEST_BODY: {\"clear\":true}"
    clear_status="$(curl -sS -D "$CLEAR_HEADERS" -o "$CLEAR_BODY" -w '%{http_code}' \
      -X POST \
      -H 'Content-Type: application/json' \
      -b "$COOKIE_JAR" \
      -c "$COOKIE_JAR" \
      --data '{"clear":true}' \
      "$BASE_URL/api/__codevalid__/test-session" || true)"
    echo "RESPONSE_HEADERS:"
    cat "$CLEAR_HEADERS" 2>/dev/null || true
    echo "RESPONSE_BODY:"
    cat "$CLEAR_BODY" 2>/dev/null || true
    echo
    echo "RESPONSE_STATUS: ${clear_status:-unknown}"
  fi
}
trap 'cleanup_session; cleanup_files' EXIT

# Given

echo "STEP: Given — establish authenticated session for user 777 and prepare mixed-user mock todos for e2e filtering"
echo "PREREQ: bootstrap session for user 777 via test-session endpoint"
echo "REQUEST_HEADERS:"
echo "Content-Type: application/json"
echo "REQUEST_BODY: {\"user\":{\"id\":777,\"login\":\"user-test-${CASE_SUFFIX}\"}}"
session_status="$(curl -sS -D "$SESSION_HEADERS" -o "$SESSION_BODY" -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  -c "$COOKIE_JAR" \
  --data "{\"user\":{\"id\":777,\"login\":\"user-test-${CASE_SUFFIX}\"}}" \
  "$BASE_URL/api/__codevalid__/test-session")"
echo "RESPONSE_HEADERS:"
cat "$SESSION_HEADERS"
echo "RESPONSE_BODY:"
cat "$SESSION_BODY"
echo
echo "RESPONSE_STATUS: $session_status"
[ "$session_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 from test-session bootstrap got ${session_status}"; exit 1; }
jq -e '.ok == true and .loggedIn == true and .user.id == 777' "$SESSION_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected logged-in session payload for user id 777"; exit 1; }
grep -q 'nuxt-session' "$COOKIE_JAR" || { echo "ASSERTION_FAILED: expected nuxt-session cookie to be stored in cookie jar"; exit 1; }

# When

echo "STEP: When — request GET /api/todos with mixed-user mock todo cookie in e2e mode"
echo "REQUEST_HEADERS:"
echo "Accept: application/json"
echo "Cookie: codevalid_mock_todos=<urlencoded-json> plus session cookie jar"
echo "REQUEST_BODY: <empty>"
when_status="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -H 'Accept: application/json' \
  -H "Cookie: codevalid_mock_todos=${ENCODED_MOCK_TODOS}" \
  -b "$COOKIE_JAR" \
  "$BASE_URL/api/todos")"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"
echo
echo "RESPONSE_STATUS: $when_status"

# Then

echo "STEP: Then — verify response includes only matching user todo and global todo, excluding other-user todo"
[ "$when_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${when_status}"; exit 1; }
jq -e 'type == "array" and length == 2' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected exactly 2 filtered mock todos"; exit 1; }
jq -e --arg id "mock-1-${CASE_SUFFIX}" 'map(.id) | index($id) != null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to include user-matching mock todo"; exit 1; }
jq -e --arg id "mock-3-${CASE_SUFFIX}" 'map(.id) | index($id) != null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to include global todo without userId"; exit 1; }
jq -e --arg id "mock-2-${CASE_SUFFIX}" 'map(.id) | index($id) == null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to exclude other-user mock todo"; exit 1; }

# Cleanup

echo "STEP: Cleanup — handled by EXIT trap to clear the authenticated session"

echo "CODEVALID_TEST_ASSERTION_OK:mock_data_filtering_in_e2e_mode"
