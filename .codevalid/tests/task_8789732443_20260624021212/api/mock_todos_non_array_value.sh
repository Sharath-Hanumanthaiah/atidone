#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
COOKIE_JAR="/tmp/mock_todos_non_array_value_cookie_${CASE_SUFFIX}.txt"
SESSION_HEADERS="/tmp/mock_todos_non_array_value_session_headers_${CASE_SUFFIX}.txt"
SESSION_BODY="/tmp/mock_todos_non_array_value_session_body_${CASE_SUFFIX}.txt"
RESPONSE_HEADERS="/tmp/mock_todos_non_array_value_response_headers_${CASE_SUFFIX}.txt"
RESPONSE_BODY="/tmp/mock_todos_non_array_value_response_body_${CASE_SUFFIX}.txt"
CLEAR_HEADERS="/tmp/mock_todos_non_array_value_clear_headers_${CASE_SUFFIX}.txt"
CLEAR_BODY="/tmp/mock_todos_non_array_value_clear_body_${CASE_SUFFIX}.txt"
NON_ARRAY_COOKIE_VALUE='%7B%22not%22%3A%22an%20array%22%7D'

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

echo "STEP: Given — establish authenticated session for user 222 and prepare a non-array mock cookie value"
echo "PREREQ: bootstrap session for user 222 via test-session endpoint"
echo "REQUEST_HEADERS:"
echo "Content-Type: application/json"
echo "REQUEST_BODY: {\"user\":{\"id\":222,\"login\":\"user-object-${CASE_SUFFIX}\"}}"
session_status="$(curl -sS -D "$SESSION_HEADERS" -o "$SESSION_BODY" -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  -c "$COOKIE_JAR" \
  --data "{\"user\":{\"id\":222,\"login\":\"user-object-${CASE_SUFFIX}\"}}" \
  "$BASE_URL/api/__codevalid__/test-session")"
echo "RESPONSE_HEADERS:"
cat "$SESSION_HEADERS"
echo "RESPONSE_BODY:"
cat "$SESSION_BODY"
echo
echo "RESPONSE_STATUS: $session_status"
[ "$session_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 from test-session bootstrap got ${session_status}"; exit 1; }
jq -e '.ok == true and .loggedIn == true and (.user.id | tostring) == "222"' "$SESSION_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected logged-in session payload for user id 222"; exit 1; }
grep -q 'nuxt-session' "$COOKIE_JAR" || { echo "ASSERTION_FAILED: expected nuxt-session cookie to be stored in cookie jar"; exit 1; }

# When

echo "STEP: When — request GET /api/todos with valid JSON that is not an array in the mock cookie"
echo "REQUEST_HEADERS:"
echo "Accept: application/json"
echo "Cookie: codevalid_mock_todos=${NON_ARRAY_COOKIE_VALUE} plus session cookie jar"
echo "REQUEST_BODY: <empty>"
when_status="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -H 'Accept: application/json' \
  -H "Cookie: codevalid_mock_todos=${NON_ARRAY_COOKIE_VALUE}" \
  -b "$COOKIE_JAR" \
  "$BASE_URL/api/todos")"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"
echo
echo "RESPONSE_STATUS: $when_status"

# Then

echo "STEP: Then — verify non-array mock cookie content results in an empty array"
[ "$when_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${when_status}"; exit 1; }
jq -e 'type == "array" and length == 0' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected empty todo array when mock cookie parses to a non-array value"; exit 1; }

# Cleanup

echo "STEP: Cleanup — handled by EXIT trap to clear the authenticated session"

echo "CODEVALID_TEST_ASSERTION_OK:mock_todos_non_array_value"
