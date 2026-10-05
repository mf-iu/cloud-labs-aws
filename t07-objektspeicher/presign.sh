#!/usr/bin/env bash
# Create a pre-signed URL (valid for one hour) and test a range request.
# Usage: ./presign.sh [key]   (default: raw/geonames/cities15000.txt)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

load_state t07
[[ -n "${BUCKET:-}" ]] || die "No bucket. Run ./create-bucket.sh first."
key="${1:-raw/geonames/cities15000.txt}"

url=$(aws s3 presign "s3://$BUCKET/$key" --expires-in 3600)
printf '\nPre-signed URL (1 hour):\n%s\n\n' "$url"

log "Without signature the object is private (expect 403):"
curl -s -o /dev/null -w '%{http_code}\n' "https://$BUCKET.s3.$AWS_REGION.amazonaws.com/$key"

log "Range request for the first 100 bytes (expect 206 Partial Content):"
curl -s -D - -o /dev/null -r 0-99 "$url" | grep -iE '^HTTP|^content-range|^content-length'
