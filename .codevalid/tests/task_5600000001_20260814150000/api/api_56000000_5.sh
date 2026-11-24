#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
TODO_TITLE="cv-logout-${SUFFIX}"
SESSION_COOKIE=""
NEW_SESSION_COOKIE=""
TODO_ID=""

# Extract "name=value" for a cookie from the last response's Set-Cookie headers.
cookie_from_headers() {
  local name="$1"
  grep -i '^set-cookie:' "$CV_HTTP_HEADERS_FILE" | tr -d '\r' \
    | sed -E 's/^[Ss]et-[Cc]ookie:[[:space:]]*//' | cut -d';' -f1 \
    | grep -E "^${name}=" | tail -n1 || true
}

# Sign in through the app's OAuth route (provider mocked by WireMock); prints nothing, sets SESSION_COOKIE.
sign_in() {
  cv_http GET /api/auth/github "" 302
  local loc state state_cookie
  loc="$(grep -i '^location:' "$CV_HTTP_HEADERS_FILE" | tail -n1 | tr -d '\r' | sed -E 's/^[Ll]ocation:[[:space:]]*//')"
  state="$(printf '%s' "$loc" | sed -nE 's/.*[?&]state=([^&]+).*/\1/p')"
  state_cookie="$(cookie_from_headers nuxt-auth-state)"
  [ -n "$state" ] && [ -n "$state_cookie" ] || cv_fail "expected OAuth state in redirect and cookie, got location=$loc cookie=$state_cookie" $LINENO
  cv_http GET "/api/auth/github?code=cv-code-${SUFFIX}&state=${state}" -H "Cookie: ${state_cookie}"
  case "$CV_HTTP_STATUS" in 301|302|303|307|308) ;; *) cv_fail "expected redirect after OAuth callback got $CV_HTTP_STATUS" $LINENO ;; esac
  SESSION_COOKIE="$(cookie_from_headers nuxt-session)"
  [ -n "$SESSION_COOKIE" ] && [ "$SESSION_COOKIE" != "nuxt-session=" ] || cv_fail "expected nuxt-session cookie after sign-in, got none" $LINENO
}

# Given
cv_step Given "user signs in, session works and owns a todo" $LINENO
cv_prereq "sign in via OAuth callback" $LINENO
sign_in
cv_prereq "create a todo with the session" $LINENO
cv_http POST /api/todos "{\"title\":\"${TODO_TITLE}\"}" 200 -H "Cookie: ${SESSION_COOKIE}"
TODO_ID="$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id // empty')"
[ -n "$TODO_ID" ] || cv_fail "expected created todo id got: $CV_HTTP_BODY" $LINENO
cv_prereq "confirm session can list todos before logout" $LINENO
cv_http GET /api/todos "" 200 -H "Cookie: ${SESSION_COOKIE}"
printf '%s' "$CV_HTTP_BODY" | jq -e --arg t "$TODO_TITLE" 'map(.title) | index($t) != null' >/dev/null \
  || cv_fail "expected own todo visible before logout" $LINENO

# When
cv_step When "user signs out with the session" $LINENO
cv_http DELETE /api/_auth/session -H "Cookie: ${SESSION_COOKIE}"
case "$CV_HTTP_STATUS" in 200|204) ;; *) cv_fail "expected logout 200/204 got $CV_HTTP_STATUS" $LINENO ;; esac

# Then
cv_step Then "the pre-logout session is rejected by a protected API and returns no data" $LINENO
cv_http GET /api/todos -H "Cookie: ${SESSION_COOKIE}"
if [ "$CV_HTTP_STATUS" = "200" ]; then
  cv_fail "expected pre-logout session to be rejected after logout got 200 with body: $(printf '%s' "$CV_HTTP_BODY" | head -c 200)" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qF "$TODO_TITLE"; then
  cv_fail "expected no todo data for logged-out session, but response contains $TODO_TITLE" $LINENO
fi

# Cleanup
cv_step Cleanup "delete the todo created by the test" $LINENO
if [ -n "$TODO_ID" ]; then
  SESSION_COOKIE=""
  sign_in
  cv_http DELETE "/api/todos/${TODO_ID}" -H "Cookie: ${SESSION_COOKIE}"
fi

echo "CODEVALID_TEST_ASSERTION_OK:api_56000000_5"
