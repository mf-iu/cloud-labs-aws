#!/usr/bin/env bash
# Run the rate limit test of cloud-labs-local (tools/rate-limit-test.sh)
# against the API gateway from create-api-gateway.sh, with its key. Further
# arguments go to the test, e.g. --requests 200.
# Usage: ./rate-limit-test.sh [arguments of tools/rate-limit-test.sh]
source "$(dirname "$0")/../lib/provider.sh"

load_state t05
[[ -n "${API_URL:-}" ]] || die "No API gateway. Run ./create-api-gateway.sh first."
args=()
[[ -z "${API_HEADER:-}" ]] || args+=(--header "$API_HEADER")
exec "$LOCAL_LABS/tools/rate-limit-test.sh" "${args[@]}" "$@" "$API_URL"
