#!/usr/bin/env bash
# Run the smoke test of cloud-labs-local (tools/smoke-test.sh) against the
# container service from deploy.sh or, with --gateway, against the API
# gateway from create-api-gateway.sh, with its key. Further arguments go to
# the smoke test; a URL replaces the one from the state.
# Usage: ./smoke-test.sh [--gateway] [arguments of tools/smoke-test.sh]
source "$(dirname "$0")/../lib/provider.sh"

args=()
if [[ "${1:-}" == --gateway ]]; then
  shift
  load_state t05
  [[ -n "${API_URL:-}" ]] || die "No API gateway. Run ./create-api-gateway.sh first."
  args+=("$API_URL")
  [[ -z "${API_HEADER:-}" ]] || args+=(--header "$API_HEADER")
else
  load_state t03
  [[ -z "${SERVICE_URL:-}" ]] || args+=("$SERVICE_URL")
  (( ${#args[@]} + $# )) || die "No service. Run ./deploy.sh or ./update-service.sh first, or pass a URL."
fi
exec "$LOCAL_LABS/tools/smoke-test.sh" "${args[@]}" "$@"
