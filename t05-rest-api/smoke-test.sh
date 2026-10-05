#!/usr/bin/env bash
# Check the PlaceFinder API of session 5 against a base URL.
# Usage: ./smoke-test.sh <base url>   e.g. https://placefinder.example.net
set -euo pipefail
base="${1:?Usage: $0 <base url>}"
base="${base%/}"
fail=0

check() {   # check <description> <expected status> <curl arguments...>
  local what=$1 expected=$2 status
  shift 2
  status=$(curl -sS -o /dev/null -w '%{http_code}' "$@") || status="error"
  if [[ "$status" == "$expected" ]]; then
    printf '  \033[32mOK\033[0m   %-45s %s\n' "$what" "$status"
  else
    printf '  \033[31mFAIL\033[0m %-45s %s (expected %s)\n' "$what" "$status" "$expected"
    fail=1
  fi
}

echo "PlaceFinder smoke test against $base"
check "GET /health" 200 "$base/health"
check "GET /v1/places?q=Berlin" 200 "$base/v1/places?q=Berlin"
check "GET /v1/places/2950159 (Berlin)" 200 "$base/v1/places/2950159"
check "GET /v1/places/0 (unknown)" 404 "$base/v1/places/0"
check "GET /v1/places?bbox=13.0,52.3 (invalid)" 422 "$base/v1/places?bbox=13.0,52.3"

# Conditional request: the second call with the ETag must return 304
etag=$(curl -sS -D - -o /dev/null "$base/v1/places/2950159" | tr -d '\r' \
  | awk 'tolower($1) == "etag:" { $1 = ""; sub(/^ /, ""); print }')
if [[ -n "$etag" ]]; then
  check "GET with If-None-Match: $etag" 304 -H "If-None-Match: $etag" "$base/v1/places/2950159"
else
  printf '  \033[33mSKIP\033[0m %-45s no ETag header\n' "conditional request"
fi

echo
curl -sS -i "$base/v1/places?bbox=13.0,52.3" | head -n 20
exit "$fail"
