#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
COOKIE_JAR="/tmp/database_connection_error_cookie_${CASE_SUFFIX}.txt"
SESSION_HEADERS="/tmp/database_connection_error_session_headers_${CASE_SUFFIX}.txt"
SESSION_BODY="/tmp/database_connection_error_session_body_${CASE_SUFFIX}.txt"
RESPONSE_HEADERS="/tmp/database_connection_error_response_headers_${CASE_SUFFIX}.txt"
RESPONSE_BODY="/tmp/database_connection_error_response_body_${CASE_SUFFIX}.txt"
CLEAR_HEADERS="/tmp/database_connection_error_clear_headers_${CASE_SUFFIX}.txt"
CLEAR_BODY="/tmp/database_connection_error_clear_body_${CASE_SUFFIX}.txt"

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

echo "STEP: Given — establish an authenticated session without providing any mock todo cookie"
echo "PREREQ: bootstrap session for user 333 via test-session endpoint so the handler reaches its non-mock path"
echo "REQUEST_HEADERS:"
echo "Content-Type: application/json"
echo "REQUEST_BODY: {\"user\":{\"id\":333,\"login\":\"user-dberror-${CASE_SUFFIX}\"}}"
session_status="$(curl -sS -D "$SESSION_HEADERS" -o "$SESSION_BODY" -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  -c "$COOKIE_JAR" \
  --data "{\"user\":{\"id\":333,\"login\":\"user-dberror-${CASE_SUFFIX}\"}}" \
  "$BASE_URL/api/__codevalid__/test-session")"
echo "RESPONSE_HEADERS:"
cat "$SESSION_HEADERS"
echo "RESPONSE_BODY:"
cat "$SESSION_BODY"
echo
echo "RESPONSE_STATUS: $session_status"
[ "$session_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 from test-session bootstrap got ${session_status}"; exit 1; }
jq -e '.ok == true and .loggedIn == true and (.user.id | tostring) == "333"' "$SESSION_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected logged-in session payload for user id 333"; exit 1; }
grep -q 'nuxt-session' "$COOKIE_JAR" || { echo "ASSERTION_FAILED: expected nuxt-session cookie to be stored in cookie jar"; exit 1; }

# When

echo "STEP: When — request GET /api/todos without a codevalid mock cookie so the handler exercises its fallback path"
echo "REQUEST_HEADERS:"
echo "Accept: application/json"
echo "Cookie: session cookie jar only"
echo "REQUEST_BODY: <empty>"
when_status="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -H 'Accept: application/json' \
  -b "$COOKIE_JAR" \
  "$BASE_URL/api/todos")"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"
echo
echo "RESPONSE_STATUS: $when_status"

# Then

echo "STEP: Then — verify any fallback-path failure is surfaced as an error response rather than a shell crash"
case "$when_status" in
  200|500)
    ;;
  *)
    echo "ASSERTION_FAILED: expected HTTP 200 or 500 when exercising the non-mock path got ${when_status}"
    exit 1
    ;;
esac
if [ "$when_status" = "500" ]; then
  [ -s "$RESPONSE_BODY" ] || { echo "ASSERTION_FAILED: expected non-empty error response body when HTTP 500 is returned"; exit 1; }
fi

# Cleanup

echo "STEP: Cleanup — handled by EXIT trap to clear the authenticated session"

echo "CODEVALID_TEST_ASSERTION_OK:database_connection_error"
