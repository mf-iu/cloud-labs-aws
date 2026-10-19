#!/usr/bin/env bash
# Upload a file, e.g. a PMTiles extract, into the bucket.
# Usage: ./upload.sh <file> [key]   (default key: tiles/<name> for .pmtiles, else raw/<name>)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

load_state t07
[[ -n "${BUCKET:-}" ]] || die "No bucket. Run ./create-bucket.sh first."
file="${1:?Usage: $0 <file> [key]}"
default="raw/$(basename "$file")"
[[ "$file" != *.pmtiles ]] || default="tiles/$(basename "$file")"
key="${2:-$default}"
aws s3 cp "$file" "s3://$BUCKET/$key"
log "Uploaded to s3://$BUCKET/$key"
