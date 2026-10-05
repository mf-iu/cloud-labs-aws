#!/usr/bin/env bash
# Delete the HTTP API created by create-api-gateway.sh.
# Usage: ./destroy-api-gateway.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t05
check_login
load_state "$LAB"
[[ -n "${API_ID:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete API $API_ID?" || exit 0
aws apigatewayv2 delete-api --api-id "$API_ID"
clear_state "$LAB"
log "API deleted."
