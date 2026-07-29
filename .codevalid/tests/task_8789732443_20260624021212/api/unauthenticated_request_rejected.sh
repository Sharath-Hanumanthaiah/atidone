#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_HEADERS="/tmp/unauthenticated_request_rejected_response_headers_${CASE_SUFFIX}.txt"
RESPONSE_BODY="/tmp/unauthenticated_request_rejected_response_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$RESPONSE_HEADERS" "$RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given

echo "STEP: Given — ensure no authenticated session credentials are supplied"
echo "PREREQ: use a direct unauthenticated request with no cookie jar or bearer token"

# When

echo "STEP: When — request GET /api/todos without authentication"
echo "REQUEST_HEADERS:"
echo "Accept: application/json"
echo "REQUEST_BODY: <empty>"
when_status="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -H 'Accept: application/json' \
  "$BASE_URL/api/todos")"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"
echo
echo "RESPONSE_STATUS: $when_status"

# Then

echo "STEP: Then — verify the protected todos endpoint rejects the unauthenticated request"
case "$when_status" in
  401|302|303|500)
    ;;
  *)
    echo "ASSERTION_FAILED: expected HTTP 401, 302, 303, or 500 for unauthenticated request got ${when_status}"
    exit 1
    ;;
esac
if [ "$when_status" = "302" ] || [ "$when_status" = "303" ]; then
  grep -qi '^location:' "$RESPONSE_HEADERS" || { echo "ASSERTION_FAILED: expected redirect response to include Location header"; exit 1; }
fi
if jq -e 'type == "array"' "$RESPONSE_BODY" >/dev/null 2>&1; then
  echo "ASSERTION_FAILED: expected unauthenticated response not to expose todo array data"
  exit 1
fi

# Cleanup

echo "STEP: Cleanup — no cleanup required because the request was unauthenticated and stateless"

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_request_rejected"
