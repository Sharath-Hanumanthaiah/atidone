#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
TODO_TITLE="cv-forged-${SUFFIX}"
SESSION_COOKIE=""
FORGED_COOKIE=""
TAMPERED_COOKIE=""
TODO_ID=""

cookie_from_headers() {
  local name="$1"
  grep -i '^set-cookie:' "$CV_HTTP_HEADERS_FILE" | tr -d '\r' \
    | sed -E 's/^[Ss]et-[Cc]ookie:[[:space:]]*//' | cut -d';' -f1 \
    | grep -E "^${name}=" | tail -n1 || true
}

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
cv_step Given "a signed-in owner has a todo; a forged and a tampered session value are prepared" $LINENO
cv_prereq "owner signs in" $LINENO
sign_in
cv_http POST /api/todos "{\"title\":\"${TODO_TITLE}\"}" 200 -H "Cookie: ${SESSION_COOKIE}"
TODO_ID="$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id // empty')"
[ -n "$TODO_ID" ] || cv_fail "expected created todo id got: $CV_HTTP_BODY" $LINENO
FORGED_COOKIE="nuxt-session=cv-made-up-${SUFFIX}"
# Alter the real sealed value: flip characters in the middle of it.
REAL_VALUE="${SESSION_COOKIE#nuxt-session=}"
MID=$(( ${#REAL_VALUE} / 2 ))
ORIG_CHARS="${REAL_VALUE:$MID:4}"
NEW_CHARS="AAAA"; [ "$ORIG_CHARS" = "AAAA" ] && NEW_CHARS="BBBB"
TAMPERED_COOKIE="nuxt-session=${REAL_VALUE:0:$MID}${NEW_CHARS}${REAL_VALUE:$((MID + 4))}"
[ "$TAMPERED_COOKIE" != "$SESSION_COOKIE" ] || cv_fail "expected tampered cookie to differ from real one" $LINENO

# When
cv_step When "call protected todo APIs with no session, a forged session and a tampered session" $LINENO
cv_http GET /api/todos
NOAUTH_LIST_STATUS="$CV_HTTP_STATUS"; NOAUTH_LIST_BODY="$CV_HTTP_BODY"
cv_http GET /api/todos -H "Cookie: ${FORGED_COOKIE}"
FORGED_LIST_STATUS="$CV_HTTP_STATUS"; FORGED_LIST_BODY="$CV_HTTP_BODY"
cv_http GET /api/todos -H "Cookie: ${TAMPERED_COOKIE}"
TAMPERED_LIST_STATUS="$CV_HTTP_STATUS"; TAMPERED_LIST_BODY="$CV_HTTP_BODY"
cv_http PATCH "/api/todos/${TODO_ID}" '{"completed":true}'
NOAUTH_PATCH_STATUS="$CV_HTTP_STATUS"
cv_http PATCH "/api/todos/${TODO_ID}" '{"completed":true}' -H "Cookie: ${FORGED_COOKIE}"
FORGED_PATCH_STATUS="$CV_HTTP_STATUS"
cv_http DELETE "/api/todos/${TODO_ID}" -H "Cookie: ${TAMPERED_COOKIE}"
TAMPERED_DELETE_STATUS="$CV_HTTP_STATUS"

# Then
cv_step Then "all attempts are rejected, no data leaks and the owner's todo is unchanged" $LINENO
for pair in "none:$NOAUTH_LIST_STATUS" "forged:$FORGED_LIST_STATUS" "tampered:$TAMPERED_LIST_STATUS" \
            "none-patch:$NOAUTH_PATCH_STATUS" "forged-patch:$FORGED_PATCH_STATUS" "tampered-delete:$TAMPERED_DELETE_STATUS"; do
  st="${pair##*:}"
  case "$st" in 2*) cv_fail "expected rejection for ${pair%%:*} session got HTTP $st" $LINENO ;; esac
done
for body in "$NOAUTH_LIST_BODY" "$FORGED_LIST_BODY" "$TAMPERED_LIST_BODY"; do
  if printf '%s' "$body" | grep -qF "$TODO_TITLE"; then
    cv_fail "expected no protected data without valid session, but response contains $TODO_TITLE" $LINENO
  fi
done
cv_http GET /api/todos "" 200 -H "Cookie: ${SESSION_COOKIE}"
ROW="$(printf '%s' "$CV_HTTP_BODY" | jq -c --argjson id "$TODO_ID" 'map(select(.id == $id)) | .[0] // empty')"
[ -n "$ROW" ] || cv_fail "expected owner's todo $TODO_ID to still exist, got: $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$ROW" | jq -r '.completed')" = "0" ] || cv_fail "expected owner's todo completed=0 unchanged got $ROW" $LINENO

# Cleanup
cv_step Cleanup "delete the owner's todo" $LINENO
cv_http DELETE "/api/todos/${TODO_ID}" -H "Cookie: ${SESSION_COOKIE}"

echo "CODEVALID_TEST_ASSERTION_OK:api_56000000_6"
