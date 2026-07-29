#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
COOKIE_JAR="/tmp/user_isolation_other_users_not_visible_cookie_${CASE_SUFFIX}.txt"
SESSION_HEADERS="/tmp/user_isolation_other_users_not_visible_session_headers_${CASE_SUFFIX}.txt"
SESSION_BODY="/tmp/user_isolation_other_users_not_visible_session_body_${CASE_SUFFIX}.txt"
RESPONSE_HEADERS="/tmp/user_isolation_other_users_not_visible_response_headers_${CASE_SUFFIX}.txt"
RESPONSE_BODY="/tmp/user_isolation_other_users_not_visible_response_body_${CASE_SUFFIX}.txt"
CLEAR_HEADERS="/tmp/user_isolation_other_users_not_visible_clear_headers_${CASE_SUFFIX}.txt"
CLEAR_BODY="/tmp/user_isolation_other_users_not_visible_clear_body_${CASE_SUFFIX}.txt"
MOCK_TODOS="$(cat <<JSON
[{"id":"victim-todo-1-${CASE_SUFFIX}","userId":"555","title":"Victim todo one"},{"id":"victim-todo-2-${CASE_SUFFIX}","userId":"555","title":"Victim todo two"},{"id":"victim-todo-3-${CASE_SUFFIX}","userId":"555","title":"Victim todo three"},{"id":"victim-todo-4-${CASE_SUFFIX}","userId":"555","title":"Victim todo four"},{"id":"victim-todo-5-${CASE_SUFFIX}","userId":"555","title":"Victim todo five"},{"id":"attacker-todo-1-${CASE_SUFFIX}","userId":"999","title":"Attacker todo one"},{"id":"attacker-todo-2-${CASE_SUFFIX}","userId":"999","title":"Attacker todo two"},{"id":"attacker-todo-3-${CASE_SUFFIX}","userId":"999","title":"Attacker todo three"},{"id":"attacker-todo-4-${CASE_SUFFIX}","userId":"999","title":"Attacker todo four"},{"id":"attacker-todo-5-${CASE_SUFFIX}","userId":"999","title":"Attacker todo five"},{"id":"attacker-todo-6-${CASE_SUFFIX}","userId":"999","title":"Attacker todo six"},{"id":"attacker-todo-7-${CASE_SUFFIX}","userId":"999","title":"Attacker todo seven"},{"id":"attacker-todo-8-${CASE_SUFFIX}","userId":"999","title":"Attacker todo eight"},{"id":"attacker-todo-9-${CASE_SUFFIX}","userId":"999","title":"Attacker todo nine"},{"id":"attacker-todo-10-${CASE_SUFFIX}","userId":"999","title":"Attacker todo ten"}]
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

echo "STEP: Given — establish an authenticated session for victim user 555 and prepare mixed victim and attacker mock todos"
echo "PREREQ: bootstrap session for user 555 via test-session endpoint"
echo "REQUEST_HEADERS:"
echo "Content-Type: application/json"
echo "REQUEST_BODY: {\"user\":{\"id\":555,\"login\":\"user-victim-${CASE_SUFFIX}\"}}"
session_status="$(curl -sS -D "$SESSION_HEADERS" -o "$SESSION_BODY" -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  -c "$COOKIE_JAR" \
  --data "{\"user\":{\"id\":555,\"login\":\"user-victim-${CASE_SUFFIX}\"}}" \
  "$BASE_URL/api/__codevalid__/test-session")"
echo "RESPONSE_HEADERS:"
cat "$SESSION_HEADERS"
echo "RESPONSE_BODY:"
cat "$SESSION_BODY"
echo
echo "RESPONSE_STATUS: $session_status"
[ "$session_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 from test-session bootstrap got ${session_status}"; exit 1; }
jq -e '.ok == true and .loggedIn == true and (.user.id | tostring) == "555"' "$SESSION_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected logged-in session payload for user id 555"; exit 1; }
grep -q 'nuxt-session' "$COOKIE_JAR" || { echo "ASSERTION_FAILED: expected nuxt-session cookie to be stored in cookie jar"; exit 1; }

# When

echo "STEP: When — request GET /api/todos as victim user while mock cookie contains victim and attacker todos"
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

echo "STEP: Then — verify only victim todos are returned and attacker todos remain hidden"
[ "$when_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${when_status}"; exit 1; }
jq -e 'type == "array" and length == 5' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected exactly 5 victim todos and no attacker todos"; exit 1; }
jq -e 'all(.[]; (.userId | tostring) == "555")' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected every returned todo userId to equal 555"; exit 1; }
jq -e --arg id "victim-todo-1-${CASE_SUFFIX}" 'map(.id) | index($id) != null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to include victim-todo-1"; exit 1; }
jq -e --arg id "victim-todo-5-${CASE_SUFFIX}" 'map(.id) | index($id) != null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to include victim-todo-5"; exit 1; }
jq -e --arg id "attacker-todo-1-${CASE_SUFFIX}" 'map(.id) | index($id) == null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to exclude attacker-todo-1"; exit 1; }
jq -e --arg id "attacker-todo-10-${CASE_SUFFIX}" 'map(.id) | index($id) == null' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response to exclude attacker-todo-10"; exit 1; }

# Cleanup

echo "STEP: Cleanup — handled by EXIT trap to clear the authenticated session"

echo "CODEVALID_TEST_ASSERTION_OK:user_isolation_other_users_not_visible"
