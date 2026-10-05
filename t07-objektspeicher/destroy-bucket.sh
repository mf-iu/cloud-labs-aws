#!/usr/bin/env bash
# Delete the bucket including all objects.
# Usage: ./destroy-bucket.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t07
check_login
load_state "$LAB"
[[ -n "${BUCKET:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete bucket s3://$BUCKET with all objects?" || exit 0
aws s3 rb "s3://$BUCKET" --force
clear_state "$LAB"
log "Bucket deleted."
